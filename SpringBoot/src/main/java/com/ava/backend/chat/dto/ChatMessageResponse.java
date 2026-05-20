package com.ava.backend.chat.dto;

import java.time.Instant;
import java.util.UUID;

public record ChatMessageResponse(
	String id,
	String roomCode,
	UUID senderId,
	String senderName,
	String senderNickname,
	String senderAvatarColor,
	String senderAvatarImageUrl,
	String content,
	Instant sentAt,
	int unreadCount,
	boolean systemMessage,
	boolean silent,
	boolean spoiler,
	ChatAttachmentResponse attachment
) {
	public static ChatMessageResponse local(String roomCode, UUID senderId, String senderName, String content) {
		return new ChatMessageResponse(
			"local-" + UUID.randomUUID(),
			roomCode,
			senderId,
			senderName,
			"",
			"#7AA06A",
			"",
			content,
			Instant.now(),
			0,
			false,
			false,
			false,
			null
		);
	}
}
