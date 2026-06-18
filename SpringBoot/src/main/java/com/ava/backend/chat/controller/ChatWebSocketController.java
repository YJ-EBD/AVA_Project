package com.ava.backend.chat.controller;

import java.security.Principal;
import java.time.Instant;
import java.util.concurrent.Executor;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.messaging.handler.annotation.DestinationVariable;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Controller;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.auth.service.LoginSessionService;
import com.ava.backend.auth.service.TokenService;
import com.ava.backend.chat.dto.ChatMessageRequest;
import com.ava.backend.chat.dto.ChatMessageResponse;
import com.ava.backend.chat.dto.ChatRealtimeEvent;
import com.ava.backend.chat.dto.ChatRoomResponse;
import com.ava.backend.chat.dto.ChatTypingEvent;
import com.ava.backend.chat.dto.ChatTypingRequest;
import com.ava.backend.chat.service.ChatService;
import com.ava.backend.push.service.MobilePushService;

@Controller
public class ChatWebSocketController {

	private static final Logger log = LoggerFactory.getLogger(ChatWebSocketController.class);

	private final ChatService chatService;
	private final SimpMessagingTemplate messagingTemplate;
	private final TokenService tokenService;
	private final LoginSessionService loginSessionService;
	private final MobilePushService mobilePushService;
	private final Executor chatRealtimeEventExecutor;

	public ChatWebSocketController(
		ChatService chatService,
		SimpMessagingTemplate messagingTemplate,
		TokenService tokenService,
		LoginSessionService loginSessionService,
		MobilePushService mobilePushService,
		@Qualifier("chatRealtimeEventExecutor") Executor chatRealtimeEventExecutor
	) {
		this.chatService = chatService;
		this.messagingTemplate = messagingTemplate;
		this.tokenService = tokenService;
		this.loginSessionService = loginSessionService;
		this.mobilePushService = mobilePushService;
		this.chatRealtimeEventExecutor = chatRealtimeEventExecutor;
	}

	@MessageMapping("/rooms/{roomCode}/send")
	public void send(
		@DestinationVariable String roomCode,
		@Payload ChatMessageRequest request,
		Principal principal,
		@Header(name = "Authorization", required = false) String authorization
	) {
		AuthPrincipal authPrincipal = resolvePrincipal(principal, authorization);
		if (authPrincipal == null) {
			throw new IllegalArgumentException("웹소켓 인증이 필요합니다.");
		}
		assertRegularChatRoomCode(roomCode);
		ChatMessageResponse response = chatService.send(roomCode, request, authPrincipal);
		messagingTemplate.convertAndSend("/topic/rooms/" + roomCode, response);
		publishRoomEvent(roomCode, response);
	}

	@MessageMapping("/rooms/{roomCode}/typing")
	public void typing(
		@DestinationVariable String roomCode,
		@Payload ChatTypingRequest request,
		Principal principal,
		@Header(name = "Authorization", required = false) String authorization
	) {
		AuthPrincipal authPrincipal = resolvePrincipal(principal, authorization);
		if (authPrincipal == null) {
			throw new IllegalArgumentException("WebSocket authentication is required.");
		}
		assertRegularChatRoomCode(roomCode);
		chatService.assertRoomMember(roomCode, authPrincipal);
		messagingTemplate.convertAndSend(
			"/topic/rooms/" + roomCode + "/typing",
			new ChatTypingEvent(
				roomCode,
				authPrincipal.userId(),
				authPrincipal.displayName(),
				request.typing(),
				Instant.now()
			)
		);
	}

	private void publishRoomEvent(String roomCode, ChatMessageResponse message) {
		ChatRoomResponse room = chatService.room(roomCode);
		ChatRealtimeEvent immediateEvent = new ChatRealtimeEvent("message", room, message);
		for (var member : room.members()) {
			messagingTemplate.convertAndSendToUser(member.email(), "/queue/chat-events", immediateEvent);
		}
		mobilePushService.sendChatMessage(roomCode, message);
		chatRealtimeEventExecutor.execute(() -> publishRecipientRoomStateEvents(roomCode, room));
	}

	private void publishRecipientRoomStateEvents(String roomCode, ChatRoomResponse room) {
		try {
			for (var member : room.members()) {
				if (member.id() == null) {
					continue;
				}
				ChatRoomResponse recipientRoom = chatService.roomForMember(roomCode, member.id());
				ChatRealtimeEvent stateEvent = new ChatRealtimeEvent("room", recipientRoom, null);
				messagingTemplate.convertAndSendToUser(member.email(), "/queue/chat-events", stateEvent);
			}
		} catch (Exception exception) {
			log.warn("Failed to publish chat room state event for room {}: {}", roomCode, exception.getMessage());
		}
	}

	private AuthPrincipal resolvePrincipal(Principal principal, String authorization) {
		if (principal instanceof AuthPrincipal authPrincipal) {
			return authPrincipal;
		}
		if (authorization == null || !authorization.startsWith("Bearer ")) {
			return null;
		}
		return tokenService.parse(authorization.substring(7))
			.filter(TokenService.TokenClaims::isAccessToken)
			.filter(claims -> loginSessionService.isCurrentSession(claims.userId(), claims.sessionId()))
			.map(claims -> new AuthPrincipal(
				claims.userId(),
				claims.email(),
				claims.displayName(),
				claims.role(),
				claims.sessionId()
			))
			.orElse(null);
	}

	private void assertRegularChatRoomCode(String roomCode) {
		if (chatService.isAzoomRoomCode(roomCode)) {
			throw new IllegalArgumentException("AZOOM text chat rooms are no longer supported.");
		}
	}
}
