package com.ava.backend.chat.dto;

import java.util.List;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record ChatMessageRequest(
	@NotBlank @Size(max = 2000) String content,
	Boolean silent,
	Boolean spoiler,
	List<ChatMentionRequest> mentions
) {
	public boolean isSilent() {
		return Boolean.TRUE.equals(silent);
	}

	public boolean isSpoiler() {
		return Boolean.TRUE.equals(spoiler);
	}

	public List<ChatMentionRequest> normalizedMentions() {
		return mentions == null ? List.of() : mentions;
	}
}
