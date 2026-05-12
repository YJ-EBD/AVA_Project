package com.ava.backend.auth.dto;

import com.ava.backend.user.dto.UserProfileResponse;

public record AuthResponse(
	String accessToken,
	String refreshToken,
	String tokenType,
	long expiresInSeconds,
	boolean replacedPreviousLogin,
	UserProfileResponse user
) {
}
