package com.ava.backend.chat.dto;

public record ChatAttachmentResponse(
	String id,
	String fileName,
	String contentType,
	long size,
	String downloadUrl,
	String groupId
) {
}
