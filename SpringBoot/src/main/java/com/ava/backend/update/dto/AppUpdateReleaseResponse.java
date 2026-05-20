package com.ava.backend.update.dto;

import java.time.Instant;

public record AppUpdateReleaseResponse(
	String platform,
	String version,
	String fileName,
	boolean required,
	String releaseNotes,
	String sha256,
	long sizeBytes,
	boolean packageAvailable,
	Instant updatedAt
) {
}
