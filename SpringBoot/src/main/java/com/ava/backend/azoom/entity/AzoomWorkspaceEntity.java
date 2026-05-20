package com.ava.backend.azoom.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

@Entity
@Table(
	name = "azooms",
	indexes = @Index(name = "idx_azooms_company_slug", columnList = "company_slug")
)
public class AzoomWorkspaceEntity {

	@Id
	private UUID id;

	@Column(name = "company_name", nullable = false, length = 120)
	private String companyName;

	@Column(name = "company_slug", nullable = false, unique = true, length = 80)
	private String companySlug;

	@Column(nullable = false, length = 120)
	private String name;

	@Column(name = "created_by_account_id")
	private UUID createdByAccountId;

	@Column(nullable = false)
	private Instant createdAt;

	@Column(nullable = false)
	private Instant updatedAt;

	protected AzoomWorkspaceEntity() {
	}

	public AzoomWorkspaceEntity(String companyName, String companySlug, String name, UUID createdByAccountId) {
		this.id = UUID.randomUUID();
		this.companyName = companyName;
		this.companySlug = companySlug;
		this.name = name;
		this.createdByAccountId = createdByAccountId;
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

	public String getCompanyName() {
		return companyName;
	}

	public String getCompanySlug() {
		return companySlug;
	}

	public String getName() {
		return name;
	}
}
