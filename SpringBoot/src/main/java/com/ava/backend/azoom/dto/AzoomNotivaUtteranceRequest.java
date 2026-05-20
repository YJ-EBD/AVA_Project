package com.ava.backend.azoom.dto;

import java.time.Instant;
import java.util.UUID;

import jakarta.validation.constraints.NotBlank;

public record AzoomNotivaUtteranceRequest(
	UUID speakerUserId,
	String speakerName,
	String speakerEmail,
	@NotBlank String content,
	Instant startedAt,
	Instant endedAt
) {
}
