package com.ava.backend.notification.controller;

import java.util.UUID;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.notification.dto.NotificationListResponse;
import com.ava.backend.notification.dto.NotificationResponse;
import com.ava.backend.notification.service.NotificationService;

@RestController
@RequestMapping("/api/notifications")
public class NotificationController {

	private final NotificationService notificationService;

	public NotificationController(NotificationService notificationService) {
		this.notificationService = notificationService;
	}

	@GetMapping
	public NotificationListResponse list(@AuthenticationPrincipal AuthPrincipal principal) {
		return notificationService.list(principal);
	}

	@PostMapping("/{id}/read")
	public NotificationResponse markRead(
		@PathVariable UUID id,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return notificationService.markRead(id, principal);
	}

	@PostMapping("/read-all")
	public NotificationListResponse markAllRead(@AuthenticationPrincipal AuthPrincipal principal) {
		return notificationService.markAllRead(principal);
	}
}
