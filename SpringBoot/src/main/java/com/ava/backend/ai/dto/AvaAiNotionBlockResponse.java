package com.ava.backend.ai.dto;

import java.util.List;

public record AvaAiNotionBlockResponse(
	String id,
	String type,
	String text,
	int depth,
	boolean checked,
	String url,
	String icon,
	String color,
	List<List<String>> cells,
	List<AvaAiNotionBlockResponse> children,
	AvaAiNotionPageResponse database
) {
}
