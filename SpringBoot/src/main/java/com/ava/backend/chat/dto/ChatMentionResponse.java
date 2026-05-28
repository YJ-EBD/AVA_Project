package com.ava.backend.chat.dto;

import java.util.UUID;

public record ChatMentionResponse(
	UUID userId,
	String displayName
) {
}
