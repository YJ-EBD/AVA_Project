package com.ava.backend.ai.dto;

public record AvaAiChatResponse(
	AvaAiMessageResponse userMessage,
	AvaAiMessageResponse assistantMessage
) {
}
