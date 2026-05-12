package com.ava.backend.chat.entity;

import java.time.Instant;
import java.util.UUID;

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
	name = "chat_message_read_receipts",
	uniqueConstraints = @UniqueConstraint(columnNames = {"message_id", "account_id"}),
	indexes = {
		@Index(name = "idx_chat_read_receipts_room", columnList = "room_code"),
		@Index(name = "idx_chat_read_receipts_account", columnList = "account_id")
	}
)
public class ChatMessageReadReceiptEntity {

	@Id
	private UUID id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "message_id", nullable = false)
	private ChatMessageEntity message;

	@Column(name = "room_code", nullable = false, length = 80)
	private String roomCode;

	@Column(name = "account_id", nullable = false)
	private UUID accountId;

	@Column(name = "read_at", nullable = false)
	private Instant readAt;

	protected ChatMessageReadReceiptEntity() {
	}

	public ChatMessageReadReceiptEntity(ChatMessageEntity message, UUID accountId) {
		this.id = UUID.randomUUID();
		this.message = message;
		this.roomCode = message.getRoomCode();
		this.accountId = accountId;
		this.readAt = Instant.now();
	}

	@PrePersist
	void prePersist() {
		if (id == null) {
			id = UUID.randomUUID();
		}
		if (readAt == null) {
			readAt = Instant.now();
		}
	}

	public UUID getId() {
		return id;
	}

	public ChatMessageEntity getMessage() {
		return message;
	}

	public UUID getAccountId() {
		return accountId;
	}

	public Instant getReadAt() {
		return readAt;
	}
}
