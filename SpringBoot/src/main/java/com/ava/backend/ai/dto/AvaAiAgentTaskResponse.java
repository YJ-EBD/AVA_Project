package com.ava.backend.ai.dto;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public record AvaAiAgentTaskResponse(
	UUID id,
	String status,
	String mode,
	String riskLevel,
	String goal,
	String currentStep,
	String summary,
	String verificationSummary,
	String failureReason,
	List<AvaAiAgentStepResponse> steps,
	Instant createdAt,
	Instant updatedAt
) {
}
