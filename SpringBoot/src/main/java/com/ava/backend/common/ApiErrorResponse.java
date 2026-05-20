package com.ava.backend.common;

import java.time.Instant;
import java.util.Map;

public record ApiErrorResponse(
	Instant timestamp,
	int status,
	String code,
	String message,
	String path,
	Map<String, Object> details
) {
	public static ApiErrorResponse of(int status, String code, String message, String path) {
		return new ApiErrorResponse(Instant.now(), status, code, message, path, Map.of());
	}

	public static ApiErrorResponse of(
		int status,
		String code,
		String message,
		String path,
		Map<String, Object> details
	) {
		return new ApiErrorResponse(Instant.now(), status, code, message, path, details == null ? Map.of() : details);
	}
}
