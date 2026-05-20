package com.ava.backend.ops.entity;

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
	name = "audit_logs",
	indexes = {
		@Index(name = "idx_audit_logs_actor_created", columnList = "actor_account_id,created_at"),
		@Index(name = "idx_audit_logs_resource", columnList = "resource_type,resource_id")
	}
)
public class AuditLogEntity {

	@Id
	private UUID id;

	@Column(name = "actor_account_id")
	private UUID actorAccountId;

	@Column(name = "actor_email", length = 160)
	private String actorEmail;

	@Column(nullable = false, length = 80)
	private String action;

	@Column(name = "resource_type", nullable = false, length = 80)
	private String resourceType;

	@Column(name = "resource_id", length = 160)
	private String resourceId;

	@Column(name = "ip_address", length = 80)
	private String ipAddress;

	@Column(name = "user_agent", length = 400)
	private String userAgent;

	@Column(columnDefinition = "text")
	private String metadata;

	@Column(name = "created_at", nullable = false)
	private Instant createdAt;

	protected AuditLogEntity() {
	}

	public AuditLogEntity(
		UUID actorAccountId,
		String actorEmail,
		String action,
		String resourceType,
		String resourceId,
		String ipAddress,
		String userAgent,
		String metadata
	) {
		this.id = UUID.randomUUID();
		this.actorAccountId = actorAccountId;
		this.actorEmail = actorEmail;
		this.action = action;
		this.resourceType = resourceType;
		this.resourceId = resourceId;
		this.ipAddress = ipAddress;
		this.userAgent = userAgent;
		this.metadata = metadata;
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

	public UUID getActorAccountId() {
		return actorAccountId;
	}

	public String getActorEmail() {
		return actorEmail;
	}

	public String getAction() {
		return action;
	}

	public String getResourceType() {
		return resourceType;
	}

	public String getResourceId() {
		return resourceId;
	}

	public String getIpAddress() {
		return ipAddress;
	}

	public String getUserAgent() {
		return userAgent;
	}

	public String getMetadata() {
		return metadata;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}
}
