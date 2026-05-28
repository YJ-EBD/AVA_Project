package com.ava.backend.azoom.dto;

import java.time.Instant;
import java.util.List;

public record AzoomVoiceChannelResponse(
	String id,
	String name,
	String roomName,
	Instant startedAt,
	Instant serverNow,
	String accessMode,
	List<String> allowedDepartments,
	boolean canJoin,
	List<AzoomVoiceParticipantResponse> participants
) {
}
