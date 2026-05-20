package com.ava.backend.azoom.dto;

import java.time.Instant;
import java.util.UUID;

public record AzoomMeetingTranscriptSummaryResponse(
	UUID id,
	String channelId,
	String channelName,
	String roomName,
	String kind,
	String status,
	String titleTimestamp,
	Instant startedAt,
	Instant endedAt,
	long utteranceCount
) {
}
