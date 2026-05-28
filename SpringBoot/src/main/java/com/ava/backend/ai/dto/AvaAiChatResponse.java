package com.ava.backend.ai.dto;

import java.util.List;

import com.ava.backend.calendar.CalendarAiWorkspaceResponse;

public record AvaAiChatResponse(
	AvaAiMessageResponse userMessage,
	AvaAiMessageResponse assistantMessage,
	List<AvaAiWorkspaceItemResponse> workspaceItems,
	String workspaceStatus,
	AvaAiAgentTaskResponse agentTask,
	CalendarAiWorkspaceResponse calendarWorkspace
) {
}
