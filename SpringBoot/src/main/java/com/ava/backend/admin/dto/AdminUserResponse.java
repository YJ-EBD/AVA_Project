package com.ava.backend.admin.dto;

import java.time.Instant;
import java.util.UUID;

import com.ava.backend.user.entity.UserRole;

public record AdminUserResponse(
	UUID id,
	String email,
	String displayName,
	UserRole role,
	boolean enabled,
	String companyName,
	String department,
	String position,
	String status,
	Instant createdAt
) {
}
