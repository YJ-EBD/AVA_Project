package com.ava.backend.azoom.dto;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public record AzoomMeetingTranscriptResponse(
	UUID id,
	String companyName,
	String companySlug,
	String channelId,
	String channelName,
	String roomName,
	String kind,
	String status,
	String titleTimestamp,
	String audioFilePath,
	Instant startedAt,
	Instant endedAt,
	List<AzoomMeetingUtteranceResponse> utterances
) {
}
