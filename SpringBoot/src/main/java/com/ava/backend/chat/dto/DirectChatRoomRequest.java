package com.ava.backend.chat.dto;

import java.util.UUID;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record DirectChatRoomRequest(
	UUID targetUserId,
	@Email @Size(max = 160) String targetEmail,
	@NotBlank @Size(max = 80) String targetName
) {
}
