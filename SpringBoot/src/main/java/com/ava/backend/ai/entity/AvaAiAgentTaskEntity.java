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
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

@Entity
@Table(
	name = "ava_ai_agent_tasks",
	indexes = {
		@Index(name = "idx_ava_ai_agent_tasks_conversation_created", columnList = "conversation_id, created_at"),
		@Index(name = "idx_ava_ai_agent_tasks_account_updated", columnList = "account_id, updated_at"),
		@Index(name = "idx_ava_ai_agent_tasks_status_updated", columnList = "status, updated_at")
	}
)
public class AvaAiAgentTaskEntity {

	@Id
	private UUID id;

	@Column(name = "conversation_id", nullable = false)
	private UUID conversationId;

	@Column(name = "account_id", nullable = false)
	private UUID accountId;

	@Column(name = "company_name", nullable = false, length = 80)
	private String companyName;

	@Column(name = "user_message_id", nullable = false)
	private UUID userMessageId;

	@Column(nullable = false, columnDefinition = "text")
	private String goal;

	@Column(nullable = false, length = 80)
	private String mode;

	@Enumerated(EnumType.STRING)
	@Column(nullable = false, length = 30)
	private AvaAiAgentTaskStatus status;

	@Column(name = "risk_level", nullable = false, length = 30)
	private String riskLevel;

	@Column(name = "current_step", length = 160)
	private String currentStep;

	@Column(columnDefinition = "text")
	private String summary;

	@Column(name = "verification_summary", columnDefinition = "text")
	private String verificationSummary;

	@Column(name = "failure_reason", columnDefinition = "text")
	private String failureReason;

	@Column(nullable = false)
	private Instant createdAt;

	@Column(nullable = false)
	private Instant updatedAt;

	protected AvaAiAgentTaskEntity() {
	}

	public AvaAiAgentTaskEntity(
		UUID conversationId,
		UUID accountId,
		String companyName,
		UUID userMessageId,
		String goal,
		String mode,
		String riskLevel
	) {
		this.id = UUID.randomUUID();
		this.conversationId = conversationId;
		this.accountId = accountId;
		this.companyName = companyName;
		this.userMessageId = userMessageId;
		this.goal = goal;
		this.mode = mode;
		this.riskLevel = riskLevel;
		this.status = AvaAiAgentTaskStatus.PLANNING;
		this.currentStep = "intent.analysis";
		this.summary = "";
		this.verificationSummary = "";
		this.failureReason = "";
	}

	@PrePersist
	void prePersist() {
		Instant now = Instant.now();
		if (this.createdAt == null) {
			this.createdAt = now;
		}
		if (this.updatedAt == null) {
			this.updatedAt = now;
		}
	}

	@PreUpdate
	void preUpdate() {
		this.updatedAt = Instant.now();
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

	public UUID getUserMessageId() {
		return userMessageId;
	}

	public String getGoal() {
		return goal;
	}

	public String getMode() {
		return mode;
	}

	public AvaAiAgentTaskStatus getStatus() {
		return status;
	}

	public String getRiskLevel() {
		return riskLevel;
	}

	public String getCurrentStep() {
		return currentStep;
	}

	public String getSummary() {
		return summary;
	}

	public String getVerificationSummary() {
		return verificationSummary;
	}

	public String getFailureReason() {
		return failureReason;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}

	public Instant getUpdatedAt() {
		return updatedAt;
	}

	public void markRunning(String currentStep) {
		this.status = AvaAiAgentTaskStatus.RUNNING;
		this.currentStep = currentStep;
	}

	public void markWaitingApproval(String currentStep, String summary) {
		this.status = AvaAiAgentTaskStatus.WAITING_APPROVAL;
		this.currentStep = currentStep;
		this.summary = summary;
	}

	public void markVerifying(String currentStep) {
		this.status = AvaAiAgentTaskStatus.VERIFYING;
		this.currentStep = currentStep;
	}

	public void markDone(String summary, String verificationSummary) {
		this.status = AvaAiAgentTaskStatus.DONE;
		this.currentStep = "done";
		this.summary = summary;
		this.verificationSummary = verificationSummary;
		this.failureReason = "";
	}

	public void markRecovered(String summary, String verificationSummary, String failureReason) {
		this.status = AvaAiAgentTaskStatus.RECOVERED;
		this.currentStep = "recovered";
		this.summary = summary;
		this.verificationSummary = verificationSummary;
		this.failureReason = failureReason;
	}

	public void markSkipped(String summary, String verificationSummary) {
		this.status = AvaAiAgentTaskStatus.SKIPPED;
		this.currentStep = "skipped";
		this.summary = summary;
		this.verificationSummary = verificationSummary;
		this.failureReason = "";
	}

	public void markFailed(String summary, String verificationSummary, String failureReason) {
		this.status = AvaAiAgentTaskStatus.FAILED;
		this.currentStep = "failed";
		this.summary = summary;
		this.verificationSummary = verificationSummary;
		this.failureReason = failureReason;
	}
}
