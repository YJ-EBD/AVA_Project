package com.ava.backend.user.dto;

public record CompanyBlockRequest(
	String targetUserId,
	String email
) {
}
