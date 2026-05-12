package com.ava.backend.auth.security;

import java.security.Principal;
import java.util.UUID;

import com.ava.backend.user.entity.UserRole;

public record AuthPrincipal(
	UUID userId,
	String email,
	String displayName,
	UserRole role,
	String sessionId
) implements Principal {

	@Override
	public String getName() {
		return email;
	}
}
