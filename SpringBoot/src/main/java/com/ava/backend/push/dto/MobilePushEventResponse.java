package com.ava.backend.push.dto;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

public record MobilePushEventResponse(
	UUID id,
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
	Instant createdAt,
	Map<String, String> data
) {
}
