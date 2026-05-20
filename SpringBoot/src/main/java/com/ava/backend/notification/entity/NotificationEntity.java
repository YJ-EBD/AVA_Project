package com.ava.backend.notification.entity;

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
	name = "notifications",
	indexes = {
		@Index(name = "idx_notifications_account_created", columnList = "account_id,created_at"),
		@Index(name = "idx_notifications_account_read", columnList = "account_id,read_at")
	}
)
public class NotificationEntity {

	@Id
	private UUID id;

	@Column(name = "account_id", nullable = false)
	private UUID accountId;

	@Column(nullable = false, length = 60)
	private String type;

	@Column(nullable = false, length = 160)
	private String title;

	@Column(nullable = false, length = 1000)
	private String body;

	@Column(name = "source_type", length = 80)
	private String sourceType;

	@Column(name = "source_id", length = 160)
	private String sourceId;

	@Column(name = "created_at", nullable = false)
	private Instant createdAt;

	@Column(name = "read_at")
	private Instant readAt;

	protected NotificationEntity() {
	}

	public NotificationEntity(
		UUID accountId,
		String type,
		String title,
		String body,
		String sourceType,
		String sourceId
	) {
		this.id = UUID.randomUUID();
		this.accountId = accountId;
		this.type = type;
		this.title = title;
		this.body = body;
		this.sourceType = sourceType;
		this.sourceId = sourceId;
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

	public String getSourceType() {
		return sourceType;
	}

	public String getSourceId() {
		return sourceId;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}

	public Instant getReadAt() {
		return readAt;
	}

	public void markRead() {
		if (readAt == null) {
			readAt = Instant.now();
		}
	}
}
