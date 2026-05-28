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
	name = "ava_ai_agent_steps",
	indexes = {
		@Index(name = "idx_ava_ai_agent_steps_task_order", columnList = "task_id, step_index"),
		@Index(name = "idx_ava_ai_agent_steps_status_updated", columnList = "status, updated_at")
	}
)
public class AvaAiAgentStepEntity {

	@Id
	private UUID id;

	@Column(name = "task_id", nullable = false)
	private UUID taskId;

	@Column(name = "step_index", nullable = false)
	private int stepIndex;

	@Column(name = "tool_name", nullable = false, length = 120)
	private String toolName;

	@Enumerated(EnumType.STRING)
	@Column(nullable = false, length = 30)
	private AvaAiAgentStepStatus status;

	@Column(nullable = false, columnDefinition = "text")
	private String description;

	@Column(name = "result_summary", columnDefinition = "text")
	private String resultSummary;

	@Column(name = "verification_summary", columnDefinition = "text")
	private String verificationSummary;

	@Column(name = "error_message", columnDefinition = "text")
	private String errorMessage;

	@Column(nullable = false)
	private Instant createdAt;

	@Column(nullable = false)
	private Instant updatedAt;

	protected AvaAiAgentStepEntity() {
	}

	public AvaAiAgentStepEntity(
		UUID taskId,
		int stepIndex,
		String toolName,
		AvaAiAgentStepStatus status,
		String description
	) {
		this.id = UUID.randomUUID();
		this.taskId = taskId;
		this.stepIndex = stepIndex;
		this.toolName = toolName;
		this.status = status;
		this.description = description;
		this.resultSummary = "";
		this.verificationSummary = "";
		this.errorMessage = "";
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

	public UUID getTaskId() {
		return taskId;
	}

	public int getStepIndex() {
		return stepIndex;
	}

	public String getToolName() {
		return toolName;
	}

	public AvaAiAgentStepStatus getStatus() {
		return status;
	}

	public String getDescription() {
		return description;
	}

	public String getResultSummary() {
		return resultSummary;
	}

	public String getVerificationSummary() {
		return verificationSummary;
	}

	public String getErrorMessage() {
		return errorMessage;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}

	public Instant getUpdatedAt() {
		return updatedAt;
	}

	public void markRunning() {
		this.status = AvaAiAgentStepStatus.RUNNING;
	}

	public void markWaitingApproval(String resultSummary, String verificationSummary) {
		this.status = AvaAiAgentStepStatus.WAITING_APPROVAL;
		this.resultSummary = resultSummary;
		this.verificationSummary = verificationSummary;
		this.errorMessage = "";
	}

	public void markDone(String resultSummary, String verificationSummary) {
		this.status = AvaAiAgentStepStatus.DONE;
		this.resultSummary = resultSummary;
		this.verificationSummary = verificationSummary;
		this.errorMessage = "";
	}

	public void markSkipped(String resultSummary, String verificationSummary) {
		this.status = AvaAiAgentStepStatus.SKIPPED;
		this.resultSummary = resultSummary;
		this.verificationSummary = verificationSummary;
		this.errorMessage = "";
	}

	public void markFailed(String resultSummary, String verificationSummary, String errorMessage) {
		this.status = AvaAiAgentStepStatus.FAILED;
		this.resultSummary = resultSummary;
		this.verificationSummary = verificationSummary;
		this.errorMessage = errorMessage;
	}
}
