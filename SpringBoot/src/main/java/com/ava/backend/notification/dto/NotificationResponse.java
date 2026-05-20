package com.ava.backend.notification.dto;

import java.time.Instant;
import java.util.UUID;

public record NotificationResponse(
	UUID id,
	String type,
	String title,
	String body,
	String sourceType,
	String sourceId,
	Instant createdAt,
	Instant readAt,
	boolean read
) {
}
