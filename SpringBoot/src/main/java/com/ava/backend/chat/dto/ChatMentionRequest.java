package com.ava.backend.chat.dto;

import java.util.UUID;

public record ChatMentionRequest(
	UUID userId,
	String displayName
) {
}
