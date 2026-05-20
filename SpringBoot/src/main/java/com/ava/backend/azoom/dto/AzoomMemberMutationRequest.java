package com.ava.backend.azoom.dto;

import java.util.UUID;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.Pattern;

public record AzoomMemberMutationRequest(
	UUID accountId,
	@Email String email,
	@Pattern(regexp = "OWNER|MANAGER|MEMBER") String role
) {
}
