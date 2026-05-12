package com.ava.backend.ai.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record AvaAiMessageRequest(
	@NotBlank
	@Size(max = 4000)
	String content
) {
}
