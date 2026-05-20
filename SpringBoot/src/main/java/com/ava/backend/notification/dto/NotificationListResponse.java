package com.ava.backend.notification.dto;

import java.util.List;

public record NotificationListResponse(
	long unreadCount,
	List<NotificationResponse> items
) {
}
