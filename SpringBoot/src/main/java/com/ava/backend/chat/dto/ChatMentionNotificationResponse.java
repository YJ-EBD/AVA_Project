package com.ava.backend.chat.dto;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.ava.backend.user.dto.UserProfileResponse;

public record ChatMentionNotificationResponse(
	UUID id,
	String roomCode,
	String roomTitle,
	int participantCount,
	List<UserProfileResponse> roomMembers,
	UUID messageId,
	UUID senderId,
	String senderName,
	String senderNickname,
	String senderAvatarColor,
	String senderAvatarImageUrl,
	String mentionDisplayName,
	String content,
	Instant sentAt,
	Instant checkedAt,
	boolean checked
) {
}
