package com.ava.backend.azoom.dto;

import java.util.UUID;

public record AzoomInviteCandidateResponse(
	UUID accountId,
	String email,
	String displayName,
	String department,
	String position,
	String avatarColor,
	String avatarImageUrl
) {
}
