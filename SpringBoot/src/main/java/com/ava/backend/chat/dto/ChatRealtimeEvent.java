package com.ava.backend.chat.dto;

public record ChatRealtimeEvent(
	String type,
	ChatRoomResponse room,
	ChatMessageResponse message
) {
}
