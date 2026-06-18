package com.ava.backend.push.service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.chat.dto.ChatMessageResponse;
import com.ava.backend.chat.entity.ChatRoomEntity;
import com.ava.backend.chat.repository.ChatRoomMemberRepository;
import com.ava.backend.chat.repository.ChatRoomRepository;
import com.ava.backend.notification.dto.NotificationResponse;
import com.ava.backend.push.dto.MobilePushEventResponse;
import com.ava.backend.push.entity.MobilePushEventEntity;
import com.ava.backend.push.repository.MobilePushEventRepository;
import com.ava.backend.user.entity.UserAccount;
import com.ava.backend.user.repository.UserAccountRepository;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

@Service
public class MobilePushService {

	private static final Logger log = LoggerFactory.getLogger(MobilePushService.class);
	private static final int MAX_BACKLOG_LIMIT = 100;
	private static final TypeReference<Map<String, String>> STRING_MAP = new TypeReference<>() {
	};

	private final MobilePushEventRepository eventRepository;
	private final ChatRoomMemberRepository memberRepository;
	private final ChatRoomRepository roomRepository;
	private final UserAccountRepository userAccountRepository;
	private final SimpMessagingTemplate messagingTemplate;
	private final ObjectMapper objectMapper;

	public MobilePushService(
		MobilePushEventRepository eventRepository,
		ChatRoomMemberRepository memberRepository,
		ChatRoomRepository roomRepository,
		UserAccountRepository userAccountRepository,
		SimpMessagingTemplate messagingTemplate,
		ObjectMapper objectMapper
	) {
		this.eventRepository = eventRepository;
		this.memberRepository = memberRepository;
		this.roomRepository = roomRepository;
		this.userAccountRepository = userAccountRepository;
		this.messagingTemplate = messagingTemplate;
		this.objectMapper = objectMapper;
	}

	@Transactional
	public void sendChatMessage(String roomCode, ChatMessageResponse message) {
		if (message == null || message.silent() || message.systemMessage()) {
			return;
		}
		List<UserAccount> recipients = memberRepository.findByRoomCode(roomCode).stream()
			.map(member -> member.getAccount())
			.filter(account -> !account.getId().equals(message.senderId()))
			.toList();
		if (recipients.isEmpty()) {
			return;
		}
		String roomTitle = roomRepository.findByCode(roomCode)
			.map(ChatRoomEntity::getTitle)
			.orElse("AVA");
		String body = message.attachment() == null
			? limit(message.content(), 180)
			: "\uD30C\uC77C\uC774 \uB3C4\uCC29\uD588\uC2B5\uB2C8\uB2E4.";
		Map<String, String> data = new LinkedHashMap<>();
		data.put("type", "chat_message");
		data.put("roomCode", roomCode);
		data.put("roomTitle", roomTitle);
		data.put("messageId", message.id());
		data.put("senderId", message.senderId().toString());
		data.put("senderName", message.senderName());
		data.put("senderNickname", message.senderNickname());
		data.put("avatarColor", message.senderAvatarColor());
		data.put("body", body);
		sendToAccounts(
			recipients,
			"chat_message",
			roomTitle,
			body,
			roomCode,
			roomTitle,
			message.senderName(),
			message.senderNickname(),
			message.senderAvatarColor(),
			"chat",
			roomCode,
			data
		);
	}

	@Transactional
	public void sendNotification(UUID accountId, NotificationResponse notification) {
		if (accountId == null || notification == null) {
			return;
		}
		userAccountRepository.findById(accountId).ifPresent(account -> {
			Map<String, String> data = new LinkedHashMap<>();
			data.put("type", "notification");
			data.put("notificationId", notification.id().toString());
			data.put("sourceType", notification.sourceType());
			data.put("sourceId", notification.sourceId());
			data.put("title", notification.title());
			data.put("body", notification.body());
			sendToAccounts(
				List.of(account),
				"notification",
				notification.title(),
				notification.body(),
				notification.sourceId(),
				notification.title(),
				"AVA",
				"AVA",
				"#0B63CE",
				notification.sourceType(),
				notification.sourceId(),
				data
			);
		});
	}

	@Transactional
	public void sendAzoomVoiceStarted(
		Collection<UserAccount> recipients,
		UUID starterAccountId,
		String channelId,
		String channelName,
		String roomName
	) {
		if (recipients == null || recipients.isEmpty()) {
			return;
		}
		String title = "AZOOM";
		String normalizedChannelName = limit(channelName, 120).isBlank() ? "AZOOM" : limit(channelName, 120);
		String body = normalizedChannelName + " 음성채널 회의가 시작되었습니다.";
		Map<String, String> data = new LinkedHashMap<>();
		data.put("type", "azoom");
		data.put("channelId", channelId);
		data.put("channelName", normalizedChannelName);
		data.put("roomName", roomName);
		sendToAccounts(
			recipients.stream()
				.filter(account -> starterAccountId == null || !account.getId().equals(starterAccountId))
				.toList(),
			"azoom",
			title,
			body,
			channelId,
			normalizedChannelName,
			"AZOOM",
			"AZOOM",
			"#0B63CE",
			"azoom_voice",
			channelId,
			data
		);
	}

	@Transactional(readOnly = true)
	public List<MobilePushEventResponse> backlog(AuthPrincipal principal, Instant after, int limit) {
		int normalizedLimit = Math.max(1, Math.min(limit, MAX_BACKLOG_LIMIT));
		List<MobilePushEventEntity> events;
		if (after == null) {
			events = eventRepository.findByAccountIdOrderByCreatedAtDesc(
				principal.userId(),
				PageRequest.of(0, normalizedLimit)
			);
			return events.stream()
				.sorted((left, right) -> left.getCreatedAt().compareTo(right.getCreatedAt()))
				.map(this::toResponse)
				.toList();
		}
		events = eventRepository.findByAccountIdAndCreatedAtAfterOrderByCreatedAtAsc(
			principal.userId(),
			after,
			PageRequest.of(0, normalizedLimit)
		);
		return events.stream().map(this::toResponse).toList();
	}

	private void sendToAccounts(
		Collection<UserAccount> recipients,
		String type,
		String title,
		String body,
		String roomId,
		String roomTitle,
		String senderName,
		String senderNickname,
		String avatarColor,
		String sourceType,
		String sourceId,
		Map<String, String> data
	) {
		List<MobilePushEventEntity> events = new ArrayList<>();
		for (UserAccount account : new LinkedHashSet<>(recipients)) {
			MobilePushEventEntity event = new MobilePushEventEntity(
				account.getId(),
				limit(type, 60),
				limit(title, 160),
				limit(body, 1000),
				limitNullable(roomId, 120),
				limitNullable(roomTitle, 160),
				limitNullable(senderName, 160),
				limitNullable(senderNickname, 160),
				limitNullable(avatarColor, 32),
				limitNullable(sourceType, 80),
				limitNullable(sourceId, 160),
				writeData(data)
			);
			MobilePushEventResponse response = toResponse(event);
			messagingTemplate.convertAndSendToUser(account.getEmail(), "/queue/mobile-push", response);
			events.add(event);
		}
		if (!events.isEmpty()) {
			eventRepository.saveAll(events);
		}
	}

	private MobilePushEventResponse toResponse(MobilePushEventEntity event) {
		return new MobilePushEventResponse(
			event.getId(),
			event.getType(),
			event.getTitle(),
			event.getBody(),
			event.getRoomId(),
			event.getRoomTitle(),
			event.getSenderName(),
			event.getSenderNickname(),
			event.getAvatarColor(),
			event.getSourceType(),
			event.getSourceId(),
			event.getCreatedAt(),
			readData(event.getDataJson())
		);
	}

	private String writeData(Map<String, String> data) {
		try {
			return objectMapper.writeValueAsString(cleanData(data));
		} catch (Exception exception) {
			log.warn("Failed to serialize mobile push data: {}", exception.getMessage());
			return "{}";
		}
	}

	private Map<String, String> readData(String value) {
		if (value == null || value.isBlank()) {
			return Map.of();
		}
		try {
			return objectMapper.readValue(value, STRING_MAP);
		} catch (Exception exception) {
			return Map.of();
		}
	}

	private Map<String, String> cleanData(Map<String, String> data) {
		Map<String, String> result = new HashMap<>();
		data.forEach((key, value) -> {
			if (key != null && !key.isBlank() && value != null) {
				result.put(key, limit(value, 1000));
			}
		});
		return result;
	}

	private String limitNullable(String value, int maxLength) {
		return value == null ? null : limit(value, maxLength);
	}

	private String limit(String value, int maxLength) {
		if (value == null) {
			return "";
		}
		String trimmed = value.trim();
		return trimmed.length() <= maxLength ? trimmed : trimmed.substring(0, maxLength);
	}
}
