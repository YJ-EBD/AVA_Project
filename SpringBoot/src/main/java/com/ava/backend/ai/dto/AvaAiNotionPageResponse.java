package com.ava.backend.ai.dto;

import java.time.Instant;
import java.util.List;

public record AvaAiNotionPageResponse(
	String id,
	String object,
	String title,
	String subtitle,
	String url,
	String icon,
	String coverUrl,
	String content,
	Instant updatedAt,
	List<AvaAiNotionPropertyResponse> properties,
	List<AvaAiNotionBlockResponse> blocks,
	List<AvaAiNotionPageResponse> children
) {
}
