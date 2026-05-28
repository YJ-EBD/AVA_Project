package com.ava.backend.azoom.service;

import java.security.Principal;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

import org.springframework.context.event.EventListener;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.messaging.SessionConnectEvent;
import org.springframework.web.socket.messaging.SessionDisconnectEvent;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.azoom.dto.AzoomVoiceChannelResponse;

import jakarta.annotation.PreDestroy;

@Component
public class AzoomVoiceWebSocketPresenceListener {

	private static final long DISCONNECT_CLEANUP_DELAY_MILLIS = 1500;

	private final AzoomService azoomService;
	private final AzoomNotivaService notivaService;
	private final SimpMessagingTemplate messagingTemplate;
	private final ConcurrentHashMap<String, AuthPrincipal> sessionPrincipals = new ConcurrentHashMap<>();
	private final ConcurrentHashMap<UUID, Set<String>> userSessions = new ConcurrentHashMap<>();
	private final ScheduledExecutorService cleanupExecutor = Executors.newSingleThreadScheduledExecutor(task -> {
		Thread thread = new Thread(task, "azoom-voice-websocket-presence-cleanup");
		thread.setDaemon(true);
		return thread;
	});

	public AzoomVoiceWebSocketPresenceListener(
		AzoomService azoomService,
		AzoomNotivaService notivaService,
		SimpMessagingTemplate messagingTemplate
	) {
		this.azoomService = azoomService;
		this.notivaService = notivaService;
		this.messagingTemplate = messagingTemplate;
	}

	@EventListener
	public void onConnect(SessionConnectEvent event) {
		StompHeaderAccessor accessor = StompHeaderAccessor.wrap(event.getMessage());
		String sessionId = accessor.getSessionId();
		AuthPrincipal principal = authPrincipal(accessor.getUser());
		if (sessionId == null || principal == null) {
			return;
		}
		sessionPrincipals.put(sessionId, principal);
		userSessions
			.computeIfAbsent(principal.userId(), ignored -> ConcurrentHashMap.newKeySet())
			.add(sessionId);
	}

	@EventListener
	public void onDisconnect(SessionDisconnectEvent event) {
		String sessionId = event.getSessionId();
		AuthPrincipal principal = authPrincipal(event.getUser());
		if (principal == null && sessionId != null) {
			principal = sessionPrincipals.remove(sessionId);
		} else if (sessionId != null) {
			sessionPrincipals.remove(sessionId);
		}
		if (sessionId == null || principal == null) {
			return;
		}
		Set<String> sessions = userSessions.get(principal.userId());
		if (sessions != null) {
			sessions.remove(sessionId);
			if (!sessions.isEmpty()) {
				return;
			}
			userSessions.remove(principal.userId(), sessions);
		}
		scheduleVoiceCleanup(principal);
	}

	@PreDestroy
	public void shutdown() {
		cleanupExecutor.shutdownNow();
	}

	private void scheduleVoiceCleanup(AuthPrincipal principal) {
		cleanupExecutor.schedule(
			() -> cleanupVoiceIfDisconnected(principal),
			DISCONNECT_CLEANUP_DELAY_MILLIS,
			TimeUnit.MILLISECONDS
		);
	}

	private void cleanupVoiceIfDisconnected(AuthPrincipal principal) {
		if (hasActiveSession(principal.userId())) {
			return;
		}
		List<AzoomVoiceChannelResponse> responses = azoomService.leaveDisconnectedVoice(principal);
		for (AzoomVoiceChannelResponse response : responses) {
			if (response.participants().isEmpty()) {
				notivaService.finishIfVoiceChannelEnded(response.id(), principal, true);
			}
			messagingTemplate.convertAndSend("/topic/azoom/voice/" + response.roomName(), response);
		}
	}

	private boolean hasActiveSession(UUID userId) {
		Set<String> sessions = userSessions.get(userId);
		return sessions != null && !sessions.isEmpty();
	}

	private AuthPrincipal authPrincipal(Principal principal) {
		return principal instanceof AuthPrincipal authPrincipal ? authPrincipal : null;
	}
}
