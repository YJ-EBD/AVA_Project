package com.ava.backend.chat.dto;

public record ChatRoomLeaveResponse(
	ChatRoomResponse room,
	ChatMessageResponse message,
	String leaverEmail,
	boolean deleted
) {
}
