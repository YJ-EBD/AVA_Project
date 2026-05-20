package com.ava.backend.admin.dto;

import com.ava.backend.user.entity.UserRole;

import jakarta.validation.constraints.Size;

public record AdminUserUpdateRequest(
	@Size(max = 80) String displayName,
	UserRole role,
	Boolean enabled,
	@Size(max = 80) String companyName,
	@Size(max = 80) String department,
	@Size(max = 80) String position
) {
}
