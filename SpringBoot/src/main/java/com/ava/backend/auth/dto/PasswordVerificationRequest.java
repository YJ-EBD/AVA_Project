package com.ava.backend.auth.dto;

import jakarta.validation.constraints.NotBlank;

public record PasswordVerificationRequest(
	@NotBlank String password
) {
}
