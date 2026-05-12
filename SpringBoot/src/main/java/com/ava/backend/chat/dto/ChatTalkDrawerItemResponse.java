package com.ava.backend.chat.dto;

import java.time.Instant;
import java.util.UUID;

import com.ava.backend.chat.entity.ChatTalkDrawerMediaType;

public record ChatTalkDrawerItemResponse(
	UUID id,
	String companyName,
	String roomCode,
	String messageId,
	String attachmentId,
	String groupId,
	String fileName,
	String contentType,
	long size,
	ChatTalkDrawerMediaType mediaType,
	String downloadUrl,
	String checksumSha256,
	UUID uploadedByAccountId,
	String uploadedByName,
	Instant uploadedAt
) {
}
