package com.ava.backend.ai.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(
	name = "ava_ai_conversations",
	uniqueConstraints = @UniqueConstraint(
		name = "uk_ava_ai_conversation_account_company",
		columnNames = {"account_id", "company_name"}
	),
	indexes = {
		@Index(name = "idx_ava_ai_conversation_company_updated", columnList = "company_name, updated_at")
	}
)
public class AvaAiConversationEntity {

	@Id
	private UUID id;

	@Column(name = "account_id", nullable = false)
	private UUID accountId;

	@Column(name = "company_name", nullable = false, length = 80)
	private String companyName;

	@Column(nullable = false, length = 120)
	private String title;

	@Column(nullable = false)
	private Instant createdAt;

	@Column(nullable = false)
	private Instant updatedAt;

	protected AvaAiConversationEntity() {
	}

	public AvaAiConversationEntity(UUID accountId, String companyName, String title) {
		this.id = UUID.randomUUID();
		this.accountId = accountId;
		this.companyName = companyName;
		this.title = title;
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

	public UUID getId() {
		return id;
	}

	public UUID getAccountId() {
		return accountId;
	}

	public String getCompanyName() {
		return companyName;
	}

	public String getTitle() {
		return title;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}

	public Instant getUpdatedAt() {
		return updatedAt;
	}

	public void setTitle(String title) {
		this.title = title;
	}

	public void setCompanyName(String companyName) {
		this.companyName = companyName;
	}
}
