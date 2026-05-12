package com.ava.backend.ai.dto;

import java.time.Instant;
import java.util.UUID;

public record AvaAiReferenceResponse(
	UUID id,
	String questionPreview,
	String answerPreview,
	Instant createdAt
) {
}
