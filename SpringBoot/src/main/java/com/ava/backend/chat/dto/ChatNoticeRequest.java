package com.ava.backend.chat.dto;

import java.time.Instant;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record ChatNoticeRequest(
	@Size(max = 80) String messageId,
	@Size(max = 80) String senderId,
	@NotBlank @Size(max = 120) String senderName,
	@NotBlank @Size(max = 2000) String content,
	Instant sentAt
) {
}
