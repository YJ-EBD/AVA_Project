package com.ava.backend.azoom.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(
	name = "azoom_channels",
	uniqueConstraints = @UniqueConstraint(columnNames = {"workspace_id", "channel_id"}),
	indexes = @Index(name = "idx_azoom_channels_workspace_type", columnList = "workspace_id,type,sort_order")
)
public class AzoomChannelEntity {

	@Id
	private UUID id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "workspace_id", nullable = false)
	private AzoomWorkspaceEntity workspace;

	@Column(name = "channel_id", nullable = false, length = 60)
	private String channelId;

	@Column(nullable = false, length = 120)
	private String name;

	@Enumerated(EnumType.STRING)
	@Column(nullable = false, length = 20)
	private AzoomChannelType type;

	@Enumerated(EnumType.STRING)
	@Column(name = "access_mode", length = 24)
	private AzoomChannelAccessMode accessMode = AzoomChannelAccessMode.ALL;

	@Column(name = "allowed_departments", columnDefinition = "text")
	private String allowedDepartments;

	@Column(name = "sort_order", nullable = false)
	private int sortOrder;

	@Column(nullable = false)
	private boolean archived;

	@Column(name = "created_by_account_id")
	private UUID createdByAccountId;

	@Column(nullable = false)
	private Instant createdAt;

	@Column(nullable = false)
	private Instant updatedAt;

	protected AzoomChannelEntity() {
	}

	public AzoomChannelEntity(
		AzoomWorkspaceEntity workspace,
		String channelId,
		String name,
		AzoomChannelType type,
		int sortOrder,
		UUID createdByAccountId
	) {
		this.id = UUID.randomUUID();
		this.workspace = workspace;
		this.channelId = channelId;
		this.name = name;
		this.type = type;
		this.sortOrder = sortOrder;
		this.createdByAccountId = createdByAccountId;
		this.archived = false;
	}

	@PrePersist
	void prePersist() {
		Instant now = Instant.now();
		if (id == null) {
			id = UUID.randomUUID();
		}
		if (createdAt == null) {
			createdAt = now;
		}
		if (updatedAt == null) {
			updatedAt = now;
		}
	}

	@PreUpdate
	void preUpdate() {
		this.updatedAt = Instant.now();
	}

	public UUID getId() {
		return id;
	}

	public AzoomWorkspaceEntity getWorkspace() {
		return workspace;
	}

	public String getChannelId() {
		return channelId;
	}

	public String getName() {
		return name;
	}

	public AzoomChannelType getType() {
		return type;
	}

	public AzoomChannelAccessMode getAccessMode() {
		return accessMode == null ? AzoomChannelAccessMode.ALL : accessMode;
	}

	public String getAllowedDepartments() {
		return allowedDepartments;
	}

	public int getSortOrder() {
		return sortOrder;
	}

	public boolean isArchived() {
		return archived;
	}

	public void rename(String name) {
		this.name = name;
	}

	public void setSortOrder(int sortOrder) {
		this.sortOrder = sortOrder;
	}

	public void setAccess(AzoomChannelAccessMode accessMode, String allowedDepartments) {
		this.accessMode = accessMode == null ? AzoomChannelAccessMode.ALL : accessMode;
		this.allowedDepartments = allowedDepartments;
	}

	public void archive() {
		this.archived = true;
	}
}
