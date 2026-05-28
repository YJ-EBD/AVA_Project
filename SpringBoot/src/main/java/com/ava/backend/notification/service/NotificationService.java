package com.ava.backend.notification.service;

import java.util.UUID;

import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.notification.dto.NotificationListResponse;
import com.ava.backend.notification.dto.NotificationResponse;
import com.ava.backend.notification.entity.NotificationEntity;
import com.ava.backend.notification.repository.NotificationRepository;
import com.ava.backend.push.service.MobilePushService;
import com.ava.backend.user.repository.UserAccountRepository;

@Service
public class NotificationService {

	private final NotificationRepository notificationRepository;
	private final UserAccountRepository userAccountRepository;
	private final SimpMessagingTemplate messagingTemplate;
	private final MobilePushService mobilePushService;

	public NotificationService(
		NotificationRepository notificationRepository,
		UserAccountRepository userAccountRepository,
		SimpMessagingTemplate messagingTemplate,
		MobilePushService mobilePushService
	) {
		this.notificationRepository = notificationRepository;
		this.userAccountRepository = userAccountRepository;
		this.messagingTemplate = messagingTemplate;
		this.mobilePushService = mobilePushService;
	}

	@Transactional(readOnly = true)
	public NotificationListResponse list(AuthPrincipal principal) {
		return new NotificationListResponse(
			notificationRepository.countByAccountIdAndReadAtIsNull(principal.userId()),
			notificationRepository.findTop50ByAccountIdOrderByCreatedAtDesc(principal.userId())
				.stream()
				.map(this::toResponse)
				.toList()
		);
	}

	@Transactional
	public NotificationResponse notifyUser(
		UUID accountId,
		String type,
		String title,
		String body,
		String sourceType,
		String sourceId
	) {
		NotificationEntity saved = notificationRepository.save(new NotificationEntity(
			accountId,
			limit(type, 60),
			limit(title, 160),
			limit(body, 1000),
			limit(sourceType, 80),
			limit(sourceId, 160)
		));
		NotificationResponse response = toResponse(saved);
		userAccountRepository.findById(accountId).ifPresent(account ->
			messagingTemplate.convertAndSendToUser(account.getEmail(), "/queue/notifications", response)
		);
		mobilePushService.sendNotification(accountId, response);
		return response;
	}

	@Transactional
	public NotificationResponse markRead(UUID id, AuthPrincipal principal) {
		NotificationEntity notification = notificationRepository.findById(id)
			.filter(item -> item.getAccountId().equals(principal.userId()))
			.orElseThrow(() -> new IllegalArgumentException("Notification not found."));
		notification.markRead();
		return toResponse(notification);
	}

	@Transactional
	public NotificationListResponse markAllRead(AuthPrincipal principal) {
		notificationRepository.findTop50ByAccountIdOrderByCreatedAtDesc(principal.userId())
			.forEach(NotificationEntity::markRead);
		return list(principal);
	}

	private NotificationResponse toResponse(NotificationEntity notification) {
		return new NotificationResponse(
			notification.getId(),
			notification.getType(),
			notification.getTitle(),
			notification.getBody(),
			notification.getSourceType(),
			notification.getSourceId(),
			notification.getCreatedAt(),
			notification.getReadAt(),
			notification.getReadAt() != null
		);
	}

	private String limit(String value, int maxLength) {
		if (value == null) {
			return "";
		}
		String trimmed = value.trim();
		return trimmed.length() <= maxLength ? trimmed : trimmed.substring(0, maxLength);
	}
}
