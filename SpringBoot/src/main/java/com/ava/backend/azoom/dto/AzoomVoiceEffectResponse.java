package com.ava.backend.azoom.dto;

import java.time.Instant;
import java.util.UUID;

public record AzoomVoiceEffectResponse(
	String type,
	String channelId,
	String roomName,
	UUID senderUserId,
	Instant occurredAt
) {
}
