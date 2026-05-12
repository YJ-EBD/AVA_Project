package com.ava.backend.chat.dto;

import java.util.List;
import java.util.UUID;

import jakarta.validation.constraints.NotEmpty;

public record GroupChatRoomRequest(
	@NotEmpty List<UUID> targetUserIds,
	String title,
	String avatarImageUrl
) {
}
