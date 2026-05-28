package com.ava.backend.ai.dto;

import java.time.Instant;
import java.util.UUID;

public record AvaAiAgentStepResponse(
	UUID id,
	int stepIndex,
	String toolName,
	String status,
	String description,
	String resultSummary,
	String verificationSummary,
	String errorMessage,
	Instant createdAt,
	Instant updatedAt
) {
}
