package com.ava.backend.user.dto;

public record CompanyEmployeeRequest(
	String targetUserId,
	String email,
	String name,
	String phoneNumber
) {
}
