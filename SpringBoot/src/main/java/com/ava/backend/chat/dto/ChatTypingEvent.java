package com.ava.backend.chat.dto;

import java.time.Instant;
import java.util.UUID;

public record ChatTypingEvent(
	String roomCode,
	UUID userId,
	String displayName,
	boolean typing,
	Instant sentAt
) {
}
