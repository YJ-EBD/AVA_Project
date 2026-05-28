package com.ava.backend.chat.dto;

public record ChatLinkPreviewResponse(
	String url,
	String title,
	String description,
	String imageUrl,
	String siteName
) {
}
