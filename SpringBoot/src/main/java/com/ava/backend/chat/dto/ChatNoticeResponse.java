package com.ava.backend.chat.dto;

import java.time.Instant;

public record ChatNoticeResponse(
	String messageId,
	String senderId,
	String senderName,
	String content,
	Instant sentAt
) {
}
