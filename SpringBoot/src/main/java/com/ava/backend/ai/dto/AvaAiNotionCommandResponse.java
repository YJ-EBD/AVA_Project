package com.ava.backend.ai.dto;

import java.util.List;

public record AvaAiNotionCommandResponse(
	String answer,
	String status,
	AvaAiNotionPageResponse activePage,
	List<AvaAiNotionPageResponse> results,
	boolean requiresApproval,
	String approvalTitle,
	String approvalDescription,
	String executionMode
) {
}
