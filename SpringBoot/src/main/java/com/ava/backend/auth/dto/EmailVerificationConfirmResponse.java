package com.ava.backend.auth.dto;

public record EmailVerificationConfirmResponse(
	String email,
	boolean verified
) {
}
