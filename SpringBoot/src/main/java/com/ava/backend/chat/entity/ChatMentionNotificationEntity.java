package com.ava.backend.chat.entity;

import java.time.Instant;
import java.util.UUID;

import com.ava.backend.user.entity.UserAccount;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(
	name = "chat_mention_notifications",
	uniqueConstraints = @UniqueConstraint(columnNames = {"message_id", "mentioned_account_id"}),
	indexes = {
		@Index(name = "idx_chat_mentions_account_checked_created", columnList = "mentioned_account_id,checked_at,created_at"),
		@Index(name = "idx_chat_mentions_account_created", columnList = "mentioned_account_id,created_at")
	}
)
public class ChatMentionNotificationEntity {

	@Id
	private UUID id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "message_id", nullable = false)
	private ChatMessageEntity message;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "mentioned_account_id", nullable = false)
	private UserAccount mentionedAccount;

	@Column(name = "room_code", nullable = false, length = 80)
	private String roomCode;

	@Column(name = "mention_display_name", nullable = false, length = 120)
	private String mentionDisplayName;

	@Column(name = "created_at", nullable = false)
	private Instant createdAt;

	@Column(name = "checked_at")
	private Instant checkedAt;

	protected ChatMentionNotificationEntity() {
	}

	public ChatMentionNotificationEntity(
		ChatMessageEntity message,
		UserAccount mentionedAccount,
		String mentionDisplayName
	) {
		this.id = UUID.randomUUID();
		this.message = message;
		this.mentionedAccount = mentionedAccount;
		this.roomCode = message.getRoomCode();
		this.mentionDisplayName = mentionDisplayName;
		this.createdAt = message.getSentAt() == null ? Instant.now() : message.getSentAt();
	}

	@PrePersist
	void prePersist() {
		if (id == null) {
			id = UUID.randomUUID();
		}
		if (createdAt == null) {
			createdAt = Instant.now();
		}
	}

	public UUID getId() {
		return id;
	}

	public ChatMessageEntity getMessage() {
		return message;
	}

	public UserAccount getMentionedAccount() {
		return mentionedAccount;
	}

	public String getRoomCode() {
		return roomCode;
	}

	public String getMentionDisplayName() {
		return mentionDisplayName;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}

	public Instant getCheckedAt() {
		return checkedAt;
	}

	public boolean isChecked() {
		return checkedAt != null;
	}

	public void markChecked() {
		if (checkedAt == null) {
			checkedAt = Instant.now();
		}
	}
}
