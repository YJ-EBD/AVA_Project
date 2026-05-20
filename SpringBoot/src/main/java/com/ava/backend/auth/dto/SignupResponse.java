package com.ava.backend.auth.dto;

import com.ava.backend.user.dto.UserProfileResponse;

public record SignupResponse(
	UserProfileResponse user,
	boolean pendingApproval,
	String message
) {
}
