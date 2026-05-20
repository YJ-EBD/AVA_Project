package com.ava.backend.ai.dto;

import java.util.List;

import jakarta.validation.constraints.Size;

public record AvaAiWorkspaceSendRequest(
	@Size(max = 80) String roomCode,
	@Size(max = 120) String targetName,
	@Size(max = 2000) String message,
	List<@Size(max = 800) String> paths
) {
}
