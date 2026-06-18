package com.ava.backend.push.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(name = "mobile_push_events")
public class MobilePushEventEntity {

	@Id
	private UUID id;

	@Column(nullable = false)
	private UUID accountId;

	@Column(nullable = false, length = 60)
	private String type;

	@Column(nullable = false, length = 160)
	private String title;

	@Column(nullable = false, length = 1000)
	private String body;

	@Column(length = 120)
	private String roomId;

	@Column(length = 160)
	private String roomTitle;

	@Column(length = 160)
	private String senderName;

	@Column(length = 160)
	private String senderNickname;

	@Column(length = 32)
	private String avatarColor;

	@Column(length = 80)
	private String sourceType;

	@Column(length = 160)
	private String sourceId;

	@Column(columnDefinition = "text")
	private String dataJson;

	@Column(nullable = false)
	private Instant createdAt;

	protected MobilePushEventEntity() {
	}

	public MobilePushEventEntity(
		UUID accountId,
		String type,
		String title,
		String body,
		String roomId,
		String roomTitle,
		String senderName,
		String senderNickname,
		String avatarColor,
		String sourceType,
		String sourceId,
		String dataJson
	) {
		this.id = UUID.randomUUID();
		this.accountId = accountId;
		this.type = type;
		this.title = title;
		this.body = body;
		this.roomId = roomId;
		this.roomTitle = roomTitle;
		this.senderName = senderName;
		this.senderNickname = senderNickname;
		this.avatarColor = avatarColor;
		this.sourceType = sourceType;
		this.sourceId = sourceId;
		this.dataJson = dataJson;
		this.createdAt = Instant.now();
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

	public UUID getAccountId() {
		return accountId;
	}

	public String getType() {
		return type;
	}

	public String getTitle() {
		return title;
	}

	public String getBody() {
		return body;
	}

	public String getRoomId() {
		return roomId;
	}

	public String getRoomTitle() {
		return roomTitle;
	}

	public String getSenderName() {
		return senderName;
	}

	public String getSenderNickname() {
		return senderNickname;
	}

	public String getAvatarColor() {
		return avatarColor;
	}

	public String getSourceType() {
		return sourceType;
	}

	public String getSourceId() {
		return sourceId;
	}

	public String getDataJson() {
		return dataJson;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}
}
