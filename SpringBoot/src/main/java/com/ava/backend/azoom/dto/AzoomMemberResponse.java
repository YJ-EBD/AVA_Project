package com.ava.backend.azoom.dto;

import java.util.UUID;

public record AzoomMemberResponse(
	UUID id,
	String email,
	String displayName,
	String role
) {
}
