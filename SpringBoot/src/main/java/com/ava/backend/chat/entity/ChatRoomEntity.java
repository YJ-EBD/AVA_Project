package com.ava.backend.chat.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(name = "chat_rooms")
public class ChatRoomEntity {

	@Id
	private UUID id;

	@Column(nullable = false, unique = true, length = 80)
	private String code;

	@Column(nullable = false, length = 120)
	private String title;

	@Enumerated(EnumType.STRING)
	@Column(nullable = false, length = 20)
	private ChatRoomType type;

	@Column(nullable = false)
	private boolean pinnedDefault;

	private Instant pinnedAt;

	@Column(nullable = false, length = 240)
	private String lastMessage;

	@Column(nullable = false, columnDefinition = "boolean default false")
	private boolean lastMessageSpoiler;

	@Column(columnDefinition = "text")
	private String avatarImageUrl;

	private UUID createdByAccountId;

	@Column(nullable = false)
	private Instant lastMessageAt;

	@Column(length = 80)
	private String noticeMessageId;

	@Column(length = 80)
	private String noticeSenderId;

	@Column(length = 120)
	private String noticeSenderName;

	@Column(length = 2000)
	private String noticeContent;

	private Instant noticeSentAt;

	@Column(nullable = false)
	private Instant createdAt;

	protected ChatRoomEntity() {
	}

	public ChatRoomEntity(String code, String title, ChatRoomType type, boolean pinnedDefault, String lastMessage) {
		this.id = UUID.randomUUID();
		this.code = code;
		this.title = title;
		this.type = type;
		this.pinnedDefault = pinnedDefault;
		this.pinnedAt = pinnedDefault ? Instant.now() : null;
		this.lastMessage = lastMessage;
		this.lastMessageSpoiler = false;
		this.lastMessageAt = Instant.now();
	}

	@PrePersist
	void prePersist() {
		this.createdAt = Instant.now();
	}

	public UUID getId() {
		return id;
	}

	public String getCode() {
		return code;
	}

	public String getTitle() {
		return title;
	}

	public ChatRoomType getType() {
		return type;
	}

	public boolean isPinnedDefault() {
		return pinnedDefault;
	}

	public Instant getPinnedAt() {
		if (pinnedAt == null && pinnedDefault) {
			return createdAt == null ? lastMessageAt : createdAt;
		}
		return pinnedAt;
	}

	public void setPinnedDefault(boolean pinnedDefault) {
		this.pinnedDefault = pinnedDefault;
		this.pinnedAt = pinnedDefault ? Instant.now() : null;
	}

	public String getLastMessage() {
		return lastMessage;
	}

	public boolean isLastMessageSpoiler() {
		return lastMessageSpoiler;
	}

	public String getAvatarImageUrl() {
		return avatarImageUrl;
	}

	public void setAvatarImageUrl(String avatarImageUrl) {
		this.avatarImageUrl = avatarImageUrl;
	}

	public UUID getCreatedByAccountId() {
		return createdByAccountId;
	}

	public void setCreatedByAccountId(UUID createdByAccountId) {
		this.createdByAccountId = createdByAccountId;
	}

	public Instant getLastMessageAt() {
		return lastMessageAt;
	}

	public String getNoticeMessageId() {
		return noticeMessageId;
	}

	public String getNoticeSenderId() {
		return noticeSenderId;
	}

	public String getNoticeSenderName() {
		return noticeSenderName;
	}

	public String getNoticeContent() {
		return noticeContent;
	}

	public Instant getNoticeSentAt() {
		return noticeSentAt;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}

	public boolean hasNotice() {
		return noticeContent != null && !noticeContent.isBlank();
	}

	public void updateLastMessage(String lastMessage) {
		updateLastMessage(lastMessage, false);
	}

	public void updateLastMessage(String lastMessage, boolean spoiler) {
		this.lastMessage = lastMessage;
		this.lastMessageSpoiler = spoiler;
		this.lastMessageAt = Instant.now();
	}

	public void updateNotice(
		String messageId,
		String senderId,
		String senderName,
		String content,
		Instant sentAt
	) {
		this.noticeMessageId = messageId;
		this.noticeSenderId = senderId;
		this.noticeSenderName = senderName;
		this.noticeContent = content;
		this.noticeSentAt = sentAt == null ? Instant.now() : sentAt;
	}
}
