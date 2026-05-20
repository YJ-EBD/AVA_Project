package com.ava.backend.ops.dto;

import java.time.Instant;
import java.util.UUID;

public record SystemLogResponse(
	UUID id,
	String requestId,
	UUID accountId,
	String accountEmail,
	String method,
	String path,
	String queryString,
	int status,
	long durationMs,
	String ipAddress,
	String userAgent,
	String errorMessage,
	Instant createdAt
) {
}
