package com.ava.backend.ai.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record AvaAiWorkspaceFileRequest(
	@NotBlank @Size(max = 800) String path,
	@Size(max = 2_000_000) String content,
	Boolean directory,
	@Size(max = 800) String newPath
) {
	public AvaAiWorkspaceFileRequest(String path, String content, Boolean directory) {
		this(path, content, directory, "");
	}

	public boolean isDirectory() {
		return Boolean.TRUE.equals(directory);
	}

	public String normalizedNewPath() {
		return newPath == null ? "" : newPath.strip();
	}
}
