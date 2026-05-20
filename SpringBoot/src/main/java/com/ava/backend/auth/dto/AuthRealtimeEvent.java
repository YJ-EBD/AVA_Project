package com.ava.backend.auth.dto;

import java.time.Instant;

public record AuthRealtimeEvent(
	String type,
	String reason,
	String message,
	Instant occurredAt
) {
}
