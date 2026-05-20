package com.ava.backend.ops.dto;

import java.time.Instant;
import java.util.UUID;

public record AppSettingResponse(
	String key,
	String value,
	String description,
	UUID updatedByAccountId,
	Instant updatedAt
) {
}
