package com.ava.backend.ai.entity;

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
	name = "ava_ai_knowledge_items",
	indexes = {
		@Index(name = "idx_ava_ai_knowledge_company_created", columnList = "company_name, created_at"),
		@Index(name = "idx_ava_ai_knowledge_source_user", columnList = "source_account_id")
	}
)
public class AvaAiKnowledgeItemEntity {

	@Id
	private UUID id;

	@Column(name = "company_name", nullable = false, length = 80)
	private String companyName;

	@Column(name = "source_conversation_id", nullable = false)
	private UUID sourceConversationId;

	@Column(name = "source_user_message_id", nullable = false)
	private UUID sourceUserMessageId;

	@Column(name = "source_assistant_message_id", nullable = false)
	private UUID sourceAssistantMessageId;

	@Column(name = "source_account_id", nullable = false)
	private UUID sourceAccountId;

	@Column(name = "source_user_name", nullable = false, length = 80)
	private String sourceUserName;

	@Column(nullable = false, columnDefinition = "text")
	private String question;

	@Column(nullable = false, columnDefinition = "text")
	private String answer;

	@Column(nullable = false, columnDefinition = "text")
	private String combinedText;

	@Column(nullable = false)
	private boolean enabled = true;

	@Column(name = "use_count")
	private Integer useCount = 0;

	@Column(name = "last_used_at")
	private Instant lastUsedAt;

	@Column(nullable = false)
	private Instant createdAt;

	protected AvaAiKnowledgeItemEntity() {
	}

	public AvaAiKnowledgeItemEntity(
		String companyName,
		UUID sourceConversationId,
		UUID sourceUserMessageId,
		UUID sourceAssistantMessageId,
		UUID sourceAccountId,
		String sourceUserName,
		String question,
		String answer
	) {
		this.id = UUID.randomUUID();
		this.companyName = companyName;
		this.sourceConversationId = sourceConversationId;
		this.sourceUserMessageId = sourceUserMessageId;
		this.sourceAssistantMessageId = sourceAssistantMessageId;
		this.sourceAccountId = sourceAccountId;
		this.sourceUserName = sourceUserName;
		this.question = question;
		this.answer = answer;
		this.combinedText = question + "\n" + answer;
	}

	@PrePersist
	void prePersist() {
		this.createdAt = Instant.now();
	}

	public UUID getId() {
		return id;
	}

	public String getCompanyName() {
		return companyName;
	}

	public UUID getSourceConversationId() {
		return sourceConversationId;
	}

	public UUID getSourceUserMessageId() {
		return sourceUserMessageId;
	}

	public UUID getSourceAssistantMessageId() {
		return sourceAssistantMessageId;
	}

	public UUID getSourceAccountId() {
		return sourceAccountId;
	}

	public String getSourceUserName() {
		return sourceUserName;
	}

	public String getQuestion() {
		return question;
	}

	public String getAnswer() {
		return answer;
	}

	public String getCombinedText() {
		return combinedText;
	}

	public boolean isEnabled() {
		return enabled;
	}

	public int getUseCount() {
		return useCount == null ? 0 : useCount;
	}

	public Instant getLastUsedAt() {
		return lastUsedAt;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}

	public void markUsed() {
		this.useCount = getUseCount() + 1;
		this.lastUsedAt = Instant.now();
	}
}
