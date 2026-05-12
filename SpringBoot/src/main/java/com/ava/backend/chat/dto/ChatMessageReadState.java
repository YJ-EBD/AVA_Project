package com.ava.backend.chat.dto;

public record ChatMessageReadState(
	String messageId,
	int unreadCount
) {
}
