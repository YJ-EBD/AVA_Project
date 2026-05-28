package com.ava.backend.chat.mapper;

import java.time.Instant;
import java.util.List;

import org.springframework.stereotype.Component;

import com.ava.backend.chat.dto.ChatAttachmentResponse;
import com.ava.backend.chat.dto.ChatMentionResponse;
import com.ava.backend.chat.dto.ChatMessageResponse;
import com.ava.backend.chat.dto.ChatNoticeResponse;
import com.ava.backend.chat.dto.ChatRoomResponse;
import com.ava.backend.chat.dto.ChatTalkDrawerItemResponse;
import com.ava.backend.chat.entity.ChatMessageEntity;
import com.ava.backend.chat.entity.ChatMessageDocument;
import com.ava.backend.chat.entity.ChatRoomEntity;
import com.ava.backend.chat.entity.ChatTalkDrawerItemEntity;
import com.ava.backend.user.dto.UserProfileResponse;

@Component
public class ChatMapper {

	public ChatRoomResponse toRoomResponse(ChatRoomEntity room, long participantCount) {
		return toRoomResponse(room, participantCount, List.of(), 0);
	}

	public ChatRoomResponse toRoomResponse(ChatRoomEntity room, long participantCount, List<UserProfileResponse> members) {
		return toRoomResponse(room, participantCount, members, false, null, 0);
	}

	public ChatRoomResponse toRoomResponse(
		ChatRoomEntity room,
		long participantCount,
		List<UserProfileResponse> members,
		int unreadCount
	) {
		return toRoomResponse(room, participantCount, members, false, null, unreadCount);
	}

	public ChatRoomResponse toRoomResponse(
		ChatRoomEntity room,
		long participantCount,
		List<UserProfileResponse> members,
		boolean pinned,
		Instant pinnedAt
	) {
		return toRoomResponse(room, participantCount, members, pinned, pinnedAt, 0);
	}

	public ChatRoomResponse toRoomResponse(
		ChatRoomEntity room,
		long participantCount,
		List<UserProfileResponse> members,
		boolean pinned,
		Instant pinnedAt,
		int unreadCount
	) {
		return toRoomResponse(room, participantCount, members, pinned, pinnedAt, unreadCount, false);
	}

	public ChatRoomResponse toRoomResponse(
		ChatRoomEntity room,
		long participantCount,
		List<UserProfileResponse> members,
		boolean pinned,
		Instant pinnedAt,
		int unreadCount,
		boolean mentioned
	) {
		return new ChatRoomResponse(
			room.getCode(),
			room.getTitle(),
			room.getType(),
			participantCount,
			pinned,
			pinned ? pinnedAt : null,
			normalizeRoomPreview(room.getLastMessage()),
			room.getLastMessageAt(),
			room.isLastMessageSpoiler(),
			room.getAvatarImageUrl(),
			toNoticeResponse(room),
			members,
			unreadCount,
			mentioned
		);
	}

	private String normalizeRoomPreview(String value) {
		if (value == null || value.isBlank()) {
			return value == null ? "" : value;
		}
		String trimmed = value.trim();
		if (trimmed.startsWith("[이미지]")) {
			return "[이미지]";
		}
		if (trimmed.startsWith("[동영상]")) {
			return "[동영상]";
		}
		return value;
	}

	private ChatNoticeResponse toNoticeResponse(ChatRoomEntity room) {
		if (!room.hasNotice()) {
			return null;
		}
		return new ChatNoticeResponse(
			room.getNoticeMessageId(),
			room.getNoticeSenderId(),
			room.getNoticeSenderName(),
			room.getNoticeContent(),
			room.getNoticeSentAt()
		);
	}

	public ChatMessageResponse toMessageResponse(ChatMessageDocument message) {
		return new ChatMessageResponse(
			message.getId(),
			message.getRoomCode(),
			message.getSenderId(),
			message.getSenderName(),
			"",
			"#7AA06A",
			"",
			message.getContent(),
			message.getSentAt(),
			0,
			message.isSystemMessage(),
			message.isSilentMessage(),
			message.isSpoilerMessage(),
			message.isDeletedForEveryone(),
			toAttachmentResponse(message),
			message.isDeletedForEveryone()
				? List.of()
				: toMentionResponses(message.getMentionUserIds(), message.getMentionDisplayNames())
		);
	}

	public ChatMessageResponse toMessageResponse(ChatMessageEntity message) {
		return toMessageResponse(message, 0);
	}

	public ChatMessageResponse toMessageResponse(ChatMessageEntity message, int unreadCount) {
		return new ChatMessageResponse(
			message.getId().toString(),
			message.getRoomCode(),
			message.getSenderId(),
			message.getSenderName(),
			"",
			"#7AA06A",
			"",
			message.getContent(),
			message.getSentAt(),
			unreadCount,
			message.isSystemMessage(),
			message.isSilentMessage(),
			message.isSpoilerMessage(),
			message.isDeletedForEveryone(),
			toAttachmentResponse(message),
			message.isDeletedForEveryone()
				? List.of()
				: toMentionResponses(message.getMentionUserIds(), message.getMentionDisplayNames())
		);
	}

	private List<ChatMentionResponse> toMentionResponses(List<java.util.UUID> userIds, List<String> displayNames) {
		if (userIds == null || userIds.isEmpty()) {
			return List.of();
		}
		return java.util.stream.IntStream.range(0, userIds.size())
			.mapToObj(index -> new ChatMentionResponse(
				userIds.get(index),
				displayNames != null && index < displayNames.size() ? displayNames.get(index) : ""
			))
			.toList();
	}

	private ChatAttachmentResponse toAttachmentResponse(ChatMessageDocument message) {
		if (!message.hasAttachment()) {
			return null;
		}
		return new ChatAttachmentResponse(
			message.getAttachmentId(),
			message.getAttachmentFileName(),
			message.getAttachmentContentType(),
			message.getAttachmentSize(),
			"/api/chat/rooms/" + message.getRoomCode() + "/attachments/" + message.getAttachmentId(),
			message.getAttachmentGroupId()
		);
	}

	private ChatAttachmentResponse toAttachmentResponse(ChatMessageEntity message) {
		if (!message.hasAttachment()) {
			return null;
		}
		return new ChatAttachmentResponse(
			message.getAttachmentId(),
			message.getAttachmentFileName(),
			message.getAttachmentContentType(),
			message.getAttachmentSize(),
			"/api/chat/rooms/" + message.getRoomCode() + "/attachments/" + message.getAttachmentId(),
			message.getAttachmentGroupId()
		);
	}

	public ChatTalkDrawerItemResponse toTalkDrawerItemResponse(ChatTalkDrawerItemEntity item) {
		return new ChatTalkDrawerItemResponse(
			item.getId(),
			item.getCompanyName(),
			item.getRoomCode(),
			item.getMessageId().toString(),
			item.getAttachmentId(),
			item.getAttachmentGroupId(),
			item.getFileName(),
			item.getContentType(),
			item.getFileSize(),
			item.getMediaType(),
			"/api/chat/rooms/" + item.getRoomCode() + "/attachments/" + item.getAttachmentId(),
			item.getChecksumSha256(),
			item.getUploadedByAccountId(),
			item.getUploadedByName(),
			item.getUploadedAt()
		);
	}
}
