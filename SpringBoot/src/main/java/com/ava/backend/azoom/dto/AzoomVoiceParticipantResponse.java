package com.ava.backend.azoom.dto;

import java.time.Instant;
import java.util.UUID;

public record AzoomVoiceParticipantResponse(
	UUID userId,
	String email,
	String displayName,
	String nickname,
	String status,
	String avatarColor,
	String avatarImageUrl,
	Instant joinedAt,
	boolean muted,
	boolean deafened,
	boolean cameraEnabled,
	boolean screenSharing
) {
}
