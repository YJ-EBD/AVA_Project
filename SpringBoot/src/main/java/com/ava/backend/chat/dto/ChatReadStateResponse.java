package com.ava.backend.chat.dto;

import java.util.List;

public record ChatReadStateResponse(
	String roomCode,
	List<ChatMessageReadState> messages
) {
}
