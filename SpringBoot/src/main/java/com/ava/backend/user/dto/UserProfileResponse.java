package com.ava.backend.user.dto;

import java.time.LocalDate;
import java.util.UUID;

import com.ava.backend.user.entity.UserRole;

public record UserProfileResponse(
	UUID id,
	String email,
	String name,
	String displayName,
	String nickname,
	String phoneNumber,
	String contactEmail,
	String gender,
	UserRole role,
	String companyName,
	String position,
	String department,
	LocalDate birthDate,
	String status,
	String avatarColor,
	String statusMessage,
	String avatarImageUrl,
	String profileBackgroundColor,
	String profileBackgroundImageUrl,
	boolean blocked
) {
}
