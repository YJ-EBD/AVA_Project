package com.ava.backend.auth.dto;

public record EmailVerificationResponse(
	String email,
	long expiresInSeconds
) {
}
