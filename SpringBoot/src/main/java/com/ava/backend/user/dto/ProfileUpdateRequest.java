package com.ava.backend.user.dto;

public record ProfileUpdateRequest(
	String nickname,
	String statusMessage,
	String avatarImageUrl,
	String profileBackgroundColor,
	String profileBackgroundImageUrl
) {
}
