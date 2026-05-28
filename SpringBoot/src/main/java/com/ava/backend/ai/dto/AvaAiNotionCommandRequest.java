package com.ava.backend.ai.dto;

public record AvaAiNotionCommandRequest(
	String command,
	String activePageId,
	String activePageObject,
	boolean approved
) {
}
