package com.ava.backend.ops.dto;

import java.time.Instant;
import java.util.UUID;

public record AuditLogResponse(
	UUID id,
	UUID actorAccountId,
	String actorEmail,
	String action,
	String resourceType,
	String resourceId,
	String ipAddress,
	String userAgent,
	String metadata,
	Instant createdAt
) {
}
