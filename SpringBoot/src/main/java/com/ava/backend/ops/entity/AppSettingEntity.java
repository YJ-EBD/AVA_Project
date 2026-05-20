package com.ava.backend.ops.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

@Entity
@Table(name = "app_settings")
public class AppSettingEntity {

	@Id
	@Column(name = "setting_key", length = 120)
	private String key;

	@Column(name = "setting_value", nullable = false, columnDefinition = "text")
	private String value;

	@Column(length = 400)
	private String description;

	@Column(name = "updated_by_account_id")
	private UUID updatedByAccountId;

	@Column(name = "created_at", nullable = false)
	private Instant createdAt;

	@Column(name = "updated_at", nullable = false)
	private Instant updatedAt;

	protected AppSettingEntity() {
	}

	public AppSettingEntity(String key, String value, String description, UUID updatedByAccountId) {
		this.key = key;
		this.value = value;
		this.description = description;
		this.updatedByAccountId = updatedByAccountId;
	}

	@PrePersist
	void prePersist() {
		Instant now = Instant.now();
		this.createdAt = now;
		this.updatedAt = now;
	}

	@PreUpdate
	void preUpdate() {
		this.updatedAt = Instant.now();
	}

	public String getKey() {
		return key;
	}

	public String getValue() {
		return value;
	}

	public String getDescription() {
		return description;
	}

	public UUID getUpdatedByAccountId() {
		return updatedByAccountId;
	}

	public Instant getUpdatedAt() {
		return updatedAt;
	}

	public void update(String value, String description, UUID updatedByAccountId) {
		this.value = value;
		this.description = description;
		this.updatedByAccountId = updatedByAccountId;
	}
}
