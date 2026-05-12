package com.ava.backend.ai.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(
	name = "ava_ai_messages",
	indexes = {
		@Index(name = "idx_ava_ai_messages_conversation_created", columnList = "conversation_id, created_at"),
		@Index(name = "idx_ava_ai_messages_account_created", columnList = "account_id, created_at")
	}
)
public class AvaAiMessageEntity {

	@Id
	private UUID id;

	@Column(name = "conversation_id", nullable = false)
	private UUID conversationId;

	@Column(name = "account_id", nullable = false)
	private UUID accountId;

	@Column(name = "company_name", nullable = false, length = 80)
	private String companyName;

	@Enumerated(EnumType.STRING)
	@Column(nullable = false, length = 20)
	private AvaAiMessageRole role;

	@Column(nullable = false, columnDefinition = "text")
	private String content;

	@Column(length = 80)
	private String modelName;

	@Column(nullable = false)
	private Instant createdAt;

	protected AvaAiMessageEntity() {
	}

	public AvaAiMessageEntity(
		UUID conversationId,
		UUID accountId,
		String companyName,
		AvaAiMessageRole role,
		String content,
		String modelName
	) {
		this.id = UUID.randomUUID();
		this.conversationId = conversationId;
		this.accountId = accountId;
		this.companyName = companyName;
		this.role = role;
		this.content = content;
		this.modelName = modelName;
	}

	@PrePersist
	void prePersist() {
		this.createdAt = Instant.now();
	}

	public UUID getId() {
		return id;
	}

	public UUID getConversationId() {
		return conversationId;
	}

	public UUID getAccountId() {
		return accountId;
	}

	public String getCompanyName() {
		return companyName;
	}

	public AvaAiMessageRole getRole() {
		return role;
	}

	public String getContent() {
		return content;
	}

	public String getModelName() {
		return modelName;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}
}
