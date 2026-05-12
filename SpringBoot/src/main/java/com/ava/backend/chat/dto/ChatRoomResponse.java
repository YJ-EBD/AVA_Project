package com.ava.backend.chat.dto;

import java.time.Instant;
import java.util.List;

import com.ava.backend.chat.entity.ChatRoomType;
import com.ava.backend.user.dto.UserProfileResponse;

public record ChatRoomResponse(
	String code,
	String title,
	ChatRoomType type,
	long participantCount,
	boolean pinned,
	Instant pinnedAt,
	String lastMessage,
	Instant lastMessageAt,
	boolean lastMessageSpoiler,
	String avatarImageUrl,
	ChatNoticeResponse notice,
	List<UserProfileResponse> members
) {
}
