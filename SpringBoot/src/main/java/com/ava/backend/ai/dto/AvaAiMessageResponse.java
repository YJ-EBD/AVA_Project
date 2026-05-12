package com.ava.backend.ai.dto;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public record AvaAiMessageResponse(
	UUID id,
	String role,
	String content,
	Instant createdAt,
	List<AvaAiReferenceResponse> references
) {
}
