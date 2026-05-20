package com.ava.backend.ai.dto;

import java.time.Instant;

public record AvaAiWorkspaceItemResponse(
	String type,
	String title,
	String subtitle,
	String path,
	String url,
	String imageUrl,
	String content,
	Long size,
	Instant updatedAt,
	String roomCode
) {
}
