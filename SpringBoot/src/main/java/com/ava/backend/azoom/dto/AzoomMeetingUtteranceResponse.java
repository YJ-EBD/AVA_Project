package com.ava.backend.azoom.dto;

import java.time.Instant;
import java.util.UUID;

public record AzoomMeetingUtteranceResponse(
	UUID id,
	int sequenceNo,
	UUID speakerUserId,
	String speakerName,
	String speakerEmail,
	String content,
	Instant startedAt,
	Instant endedAt
) {
}
