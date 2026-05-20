package com.ava.backend.azoom.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(
	name = "azoom_chat_messages",
	indexes = @Index(
		name = "idx_azoom_chat_messages_company_channel_sent_at",
		columnList = "company_slug,channel_id,sent_at"
	)
)
public class AzoomChatMessageEntity {

	@Id
	private UUID id;

	@Column(name = "company_name", nullable = false, length = 120)
	private String companyName;

	@Column(name = "company_slug", nullable = false, length = 80)
	private String companySlug;

	@Column(name = "channel_id", nullable = false, length = 40)
	private String channelId;

	@Column(name = "channel_name", nullable = false, length = 120)
	private String channelName;

	@Column(name = "room_code", nullable = false, length = 120)
	private String roomCode;

	@Column(name = "sender_id", nullable = false)
	private UUID senderId;

	@Column(name = "sender_name", nullable = false, length = 120)
	private String senderName;

	@Column(nullable = false, length = 2000)
	private String content;

	@Column(name = "sent_at", nullable = false)
	private Instant sentAt;

	@Column(name = "silent_message", nullable = false)
	private boolean silentMessage;

	@Column(name = "spoiler_message", nullable = false)
	private boolean spoilerMessage;

	protected AzoomChatMessageEntity() {
	}

	public AzoomChatMessageEntity(
		String companyName,
		String companySlug,
		String channelId,
		String channelName,
		String roomCode,
		UUID senderId,
		String senderName,
		String content,
		boolean silentMessage,
		boolean spoilerMessage
	) {
		this.id = UUID.randomUUID();
		this.companyName = companyName;
		this.companySlug = companySlug;
		this.channelId = channelId;
		this.channelName = channelName;
		this.roomCode = roomCode;
		this.senderId = senderId;
		this.senderName = senderName;
		this.content = content;
		this.sentAt = Instant.now();
		this.silentMessage = silentMessage;
		this.spoilerMessage = spoilerMessage;
	}

	@PrePersist
	void prePersist() {
		if (id == null) {
			id = UUID.randomUUID();
		}
		if (sentAt == null) {
			sentAt = Instant.now();
		}
	}

	public UUID getId() {
		return id;
	}

	public String getCompanyName() {
		return companyName;
	}

	public String getCompanySlug() {
		return companySlug;
	}

	public String getChannelId() {
		return channelId;
	}

	public String getChannelName() {
		return channelName;
	}

	public String getRoomCode() {
		return roomCode;
	}

	public UUID getSenderId() {
		return senderId;
	}

	public String getSenderName() {
		return senderName;
	}

	public String getContent() {
		return content;
	}

	public Instant getSentAt() {
		return sentAt;
	}

	public boolean isSilentMessage() {
		return silentMessage;
	}

	public boolean isSpoilerMessage() {
		return spoilerMessage;
	}
}
