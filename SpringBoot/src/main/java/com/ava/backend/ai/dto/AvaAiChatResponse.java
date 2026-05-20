package com.ava.backend.ai.dto;

import java.util.List;

public record AvaAiChatResponse(
	AvaAiMessageResponse userMessage,
	AvaAiMessageResponse assistantMessage,
	List<AvaAiWorkspaceItemResponse> workspaceItems,
	String workspaceStatus
) {
}
