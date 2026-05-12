package com.ava.backend.update.dto;

public record AppUpdateManifestResponse(
	String platform,
	String currentVersion,
	String latestVersion,
	boolean updateAvailable,
	boolean required,
	String fileName,
	String downloadUrl,
	String sha256,
	long sizeBytes,
	String releaseNotes
) {
}
