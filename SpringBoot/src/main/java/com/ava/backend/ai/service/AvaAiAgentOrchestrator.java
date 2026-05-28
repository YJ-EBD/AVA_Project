package com.ava.backend.ai.service;

import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

import org.springframework.stereotype.Service;

import com.ava.backend.ai.dto.AvaAiAgentStepResponse;
import com.ava.backend.ai.dto.AvaAiAgentTaskResponse;
import com.ava.backend.ai.entity.AvaAiAgentStepEntity;
import com.ava.backend.ai.entity.AvaAiAgentStepStatus;
import com.ava.backend.ai.entity.AvaAiAgentTaskEntity;
import com.ava.backend.ai.entity.AvaAiAgentTaskStatus;
import com.ava.backend.ai.entity.AvaAiConversationEntity;
import com.ava.backend.ai.entity.AvaAiMessageEntity;
import com.ava.backend.ai.repository.AvaAiAgentStepRepository;
import com.ava.backend.ai.repository.AvaAiAgentTaskRepository;
import com.ava.backend.ai.service.AvaAiToolRegistry.ToolExecution;
import com.ava.backend.ai.service.AvaAiToolRegistry.ToolRequest;
import com.ava.backend.ai.service.AvaAiWorkspaceService.WorkspaceActionResult;

@Service
public class AvaAiAgentOrchestrator {

	private static final int MAX_STATE_CHARS = 2_400;

	private final AvaAiAgentTaskRepository taskRepository;
	private final AvaAiAgentStepRepository stepRepository;
	private final AvaAiToolRegistry toolRegistry;

	public AvaAiAgentOrchestrator(
		AvaAiAgentTaskRepository taskRepository,
		AvaAiAgentStepRepository stepRepository,
		AvaAiToolRegistry toolRegistry
	) {
		this.taskRepository = taskRepository;
		this.stepRepository = stepRepository;
		this.toolRegistry = toolRegistry;
	}

	public AgentSession start(
		AvaAiConversationEntity conversation,
		AvaAiMessageEntity userMessage,
		String content
	) {
		AvaAiAgentPolicy.AgentFrame frame = AvaAiAgentPolicy.inspect(content);
		if (!frame.workRequest()) {
			return AgentSession.inactive(frame);
		}
		AvaAiAgentTaskEntity task = taskRepository.save(new AvaAiAgentTaskEntity(
			conversation.getId(),
			userMessage.getAccountId(),
			userMessage.getCompanyName(),
			userMessage.getId(),
			limit(content, 1_500),
			frame.mode(),
			riskLevel(frame)
		));
		AgentSession session = new AgentSession(task, frame);
		AvaAiAgentStepEntity intent = saveStep(
			session,
			"intent.analysis",
			AvaAiAgentStepStatus.DONE,
			"사용자 요청과 최근 대화 맥락을 작업 프레임으로 분류"
		);
		intent.markDone(
			"mode=" + frame.mode()
				+ ", toolRelevant=" + frame.toolRelevant()
				+ ", mutation=" + frame.mutationIntent()
				+ ", correction=" + frame.correctionIntent()
				+ ", continuation=" + frame.continuationIntent(),
			frame.requiresVerification() ? "검증이 필요한 작업으로 분류했습니다." : "직접 대화로 처리 가능한 요청입니다."
		);
		stepRepository.save(intent);
		recordResumeCheckpoint(session, userMessage);
		task.markRunning("tool.selection");
		taskRepository.save(task);
		return session;
	}

	public ToolExecution runAutomaticTool(AgentSession session, String content) {
		if (session == null || !session.active()) {
			return ToolExecution.notHandled();
		}
		ToolRequest request = toolRegistry.select(content).orElse(null);
		if (request == null) {
			AvaAiAgentStepEntity step = saveStep(
				session,
				"tool.selection",
				AvaAiAgentStepStatus.SKIPPED,
				"현재 요청에 즉시 실행 가능한 내장 운영 도구가 있는지 확인"
			);
			step.markSkipped(
				"자동 도구 매칭 없음",
				"LLM/작업공간/Notion 전용 경로로 이어서 처리합니다."
			);
			stepRepository.save(step);
			return ToolExecution.notHandled();
		}
		AvaAiAgentStepEntity step = saveStep(
			session,
			request.toolName(),
			AvaAiAgentStepStatus.RUNNING,
			request.description()
		);
		session.task().markRunning(request.toolName());
		taskRepository.save(session.task());

		ToolExecution execution = toolRegistry.execute(request);
		if (execution.waitingApproval()) {
			step.markWaitingApproval(execution.resultSummary(), execution.verificationSummary());
			session.task().markWaitingApproval(request.toolName(), execution.resultSummary());
		} else if (execution.success()) {
			step.markDone(execution.resultSummary(), execution.verificationSummary());
		} else {
			step.markFailed(execution.resultSummary(), execution.verificationSummary(), execution.errorMessage());
			execution = recoverFailedTool(session, request, execution);
		}
		stepRepository.save(step);
		taskRepository.save(session.task());
		return execution;
	}

	public List<AvaAiLlmClient.ToolDefinition> nativeToolDefinitions() {
		return toolRegistry.nativeToolDefinitions();
	}

	public ToolExecution executeNativeTool(AvaAiLlmClient.ToolCall call) {
		return toolRegistry.executeNativeTool(call);
	}

	private ToolExecution recoverFailedTool(
		AgentSession session,
		ToolRequest originalRequest,
		ToolExecution failedExecution
	) {
		ToolRequest recoveryRequest = recoveryRequest(originalRequest);
		if (recoveryRequest == null) {
			return failedExecution;
		}
		AvaAiAgentStepEntity recoveryStep = saveStep(
			session,
			"recovery." + recoveryRequest.toolName(),
			AvaAiAgentStepStatus.RUNNING,
			"실패한 도구 실행 뒤 안전한 읽기 전용 복구 검증 수행"
		);
		ToolExecution recovery = toolRegistry.execute(recoveryRequest);
		if (recovery.success()) {
			recoveryStep.markDone(recovery.resultSummary(), recovery.verificationSummary());
		} else {
			recoveryStep.markFailed(recovery.resultSummary(), recovery.verificationSummary(), recovery.errorMessage());
		}
		stepRepository.save(recoveryStep);
		String answer = failedExecution.answer();
		if (recovery.handled()) {
			answer = answer + "\n\n[복구 검증]\n" + recovery.answer();
		}
		return new ToolExecution(
			failedExecution.toolName(),
			failedExecution.handled(),
			false,
			recovery.success() || recovery.verified(),
			false,
			answer,
			failedExecution.resultSummary() + " / recovery=" + recovery.resultSummary(),
			failedExecution.verificationSummary() + " / recovery=" + recovery.verificationSummary(),
			failedExecution.errorMessage(),
			failedExecution.modelName()
		);
	}

	private ToolRequest recoveryRequest(ToolRequest originalRequest) {
		if (originalRequest == null || originalRequest.toolName() == null) {
			return null;
		}
		String toolName = originalRequest.toolName();
		if (toolName.equals("server.logs")) {
			return null;
		}
		if (toolName.startsWith("server.") || toolName.startsWith("build.")) {
			return new ToolRequest(
				"server.logs",
				"실패 원인 확인을 위한 최근 백엔드 로그 읽기",
				true
			);
		}
		return null;
	}

	public AvaAiAgentTaskResponse complete(
		AgentSession session,
		String answer,
		WorkspaceActionResult workspace,
		ToolExecution toolExecution
	) {
		if (session == null || !session.active()) {
			return null;
		}
		AvaAiAgentTaskEntity task = session.task();
		if (workspaceHasSignal(workspace)) {
			AvaAiAgentStepEntity step = saveStep(
				session,
				"workspace.inspect",
				AvaAiAgentStepStatus.DONE,
				"작업공간 결과를 확인하고 답변 근거에 반영"
			);
			step.markDone(
				workspace.status() == null || workspace.status().isBlank()
					? "items=" + workspace.items().size()
					: workspace.status(),
				workspace.handled() ? "작업공간 서비스가 요청을 처리했습니다." : "작업공간 컨텍스트를 프롬프트에 반영했습니다."
			);
			stepRepository.save(step);
		}

		task.markVerifying("verification");
		taskRepository.save(task);
		AvaAiAgentStepEntity verification = saveStep(
			session,
			"verification",
			AvaAiAgentStepStatus.RUNNING,
			"실행 결과와 답변 상태 검증"
		);
		String summary;
		String verificationSummary;
		if (toolExecution != null && toolExecution.handled()) {
			summary = toolExecution.resultSummary();
			verificationSummary = toolExecution.verificationSummary();
			if (toolExecution.waitingApproval()) {
				verification.markWaitingApproval(summary, verificationSummary);
				task.markWaitingApproval("verification", summary);
			} else if (toolExecution.success()) {
				verification.markDone(summary, verificationSummary);
				task.markDone("내장 도구 실행과 답변 생성을 완료했습니다.", verificationSummary);
			} else if (toolExecution.verified()) {
				verification.markDone(summary, verificationSummary);
				task.markRecovered(
					"원 작업은 실패했지만 안전한 복구 검증을 완료했습니다.",
					verificationSummary,
					toolExecution.errorMessage()
				);
			} else {
				verification.markFailed(summary, verificationSummary, toolExecution.errorMessage());
				task.markFailed("내장 도구 실행에 실패했습니다.", verificationSummary, toolExecution.errorMessage());
			}
		} else if (workspace != null && workspace.handled()) {
			summary = workspace.status();
			verificationSummary = "작업공간 서비스의 handled 결과를 확인했습니다.";
			verification.markDone(summary, verificationSummary);
			task.markDone("작업공간 요청 처리를 완료했습니다.", verificationSummary);
		} else if (session.frame().requiresVerification()) {
			summary = "직접 실행 가능한 내장 도구는 없었고, 대화/프롬프트 경로로 답변했습니다.";
			verificationSummary = "미검증 외부 작업은 완료로 주장하지 않도록 에이전트 계약을 프롬프트에 주입했습니다.";
			verification.markDone(summary, verificationSummary);
			task.markDone("대화형 작업 응답을 완료했습니다.", verificationSummary);
		} else {
			summary = "일반 대화 응답 생성";
			verificationSummary = "추가 도구 검증이 필요하지 않은 요청입니다.";
			verification.markSkipped(summary, verificationSummary);
			task.markSkipped(summary, verificationSummary);
		}
		stepRepository.save(verification);
		if (task.getStatus() == AvaAiAgentTaskStatus.RUNNING || task.getStatus() == AvaAiAgentTaskStatus.PLANNING) {
			task.markDone(limit(answer, 500), "답변 저장 완료");
		}
		taskRepository.save(task);
		return toResponse(task);
	}

	private void recordResumeCheckpoint(AgentSession session, AvaAiMessageEntity userMessage) {
		AvaAiAgentStepEntity checkpoint = saveStep(
			session,
			"state.checkpoint",
			AvaAiAgentStepStatus.DONE,
			"장기 작업 재개를 위한 대화/사용자 메시지 체크포인트 저장"
		);
		checkpoint.markDone(
			"conversation=" + session.task().getConversationId()
				+ ", userMessage=" + userMessage.getId()
				+ ", mode=" + session.frame().mode(),
			"후속 대화에서 최근 작업 목표, 상태, 검증 결과를 이어받을 수 있도록 저장했습니다."
		);
		stepRepository.save(checkpoint);
	}

	public void recordExternalToolExchange(
		AvaAiConversationEntity conversation,
		AvaAiMessageEntity userMessage,
		AvaAiMessageEntity assistantMessage,
		String toolName
	) {
		String normalizedTool = toolName == null || toolName.isBlank() ? "ava-tool" : limit(toolName, 120);
		AvaAiAgentPolicy.AgentFrame frame = AvaAiAgentPolicy.inspect(userMessage.getContent());
		AvaAiAgentTaskEntity task = taskRepository.save(new AvaAiAgentTaskEntity(
			conversation.getId(),
			userMessage.getAccountId(),
			userMessage.getCompanyName(),
			userMessage.getId(),
			limit(userMessage.getContent(), 1_500),
			frame.mode(),
			normalizedTool.contains("write") || normalizedTool.contains("upload") ? "medium" : "low"
		));
		AgentSession session = new AgentSession(task, frame);
		AvaAiAgentStepEntity step = saveStep(
			session,
			normalizedTool,
			AvaAiAgentStepStatus.DONE,
			"외부 도구/API 결과를 AVA AI 대화 기록에 연결"
		);
		step.markDone(
			limit(assistantMessage.getContent(), 900),
			"toolName=" + normalizedTool + ", assistantMessageId=" + assistantMessage.getId()
		);
		stepRepository.save(step);
		task.markDone("외부 도구 결과를 대화에 기록했습니다.", "도구 응답 메시지가 저장되었습니다.");
		taskRepository.save(task);
	}

	public void deleteConversationTasks(AvaAiConversationEntity conversation) {
		if (conversation == null) {
			return;
		}
		List<AvaAiAgentTaskEntity> tasks = taskRepository.findByConversationId(conversation.getId());
		if (tasks.isEmpty()) {
			return;
		}
		stepRepository.deleteByTaskIdIn(tasks.stream().map(AvaAiAgentTaskEntity::getId).toList());
		taskRepository.deleteByConversationId(conversation.getId());
	}

	public String recentState(UUID conversationId) {
		if (conversationId == null) {
			return "";
		}
		List<AvaAiAgentTaskEntity> tasks = taskRepository.findTop8ByConversationIdOrderByUpdatedAtDesc(conversationId);
		if (tasks.isEmpty()) {
			return "";
		}
		StringBuilder builder = new StringBuilder();
		builder.append("\n[RECENT AGENT TASKS]\n");
		builder.append("These are persisted AVA agent task states from this conversation. Use them for follow-up intent, corrections, and verification.\n");
		for (AvaAiAgentTaskEntity task : tasks.stream()
			.sorted(Comparator.comparing(AvaAiAgentTaskEntity::getUpdatedAt))
			.toList()) {
			builder.append("- ")
				.append(task.getUpdatedAt()).append(' ')
				.append(task.getStatus()).append(' ')
				.append(task.getMode()).append(" goal=")
				.append(limit(oneLine(task.getGoal()), 180));
			if (task.getSummary() != null && !task.getSummary().isBlank()) {
				builder.append(" summary=").append(limit(oneLine(task.getSummary()), 180));
			}
			if (task.getVerificationSummary() != null && !task.getVerificationSummary().isBlank()) {
				builder.append(" verified=").append(limit(oneLine(task.getVerificationSummary()), 180));
			}
			builder.append('\n');
			List<AvaAiAgentStepEntity> steps = stepRepository.findByTaskIdOrderByStepIndexAsc(task.getId());
			int start = Math.max(0, steps.size() - 3);
			for (AvaAiAgentStepEntity step : steps.subList(start, steps.size())) {
				builder.append("  step#")
					.append(step.getStepIndex()).append(' ')
					.append(step.getStatus()).append(' ')
					.append(step.getToolName());
				if (step.getResultSummary() != null && !step.getResultSummary().isBlank()) {
					builder.append(" result=").append(limit(oneLine(step.getResultSummary()), 140));
				}
				if (step.getErrorMessage() != null && !step.getErrorMessage().isBlank()) {
					builder.append(" error=").append(limit(oneLine(step.getErrorMessage()), 120));
				}
				builder.append('\n');
			}
		}
		return limit(builder.toString(), MAX_STATE_CHARS);
	}

	private AvaAiAgentStepEntity saveStep(
		AgentSession session,
		String toolName,
		AvaAiAgentStepStatus status,
		String description
	) {
		return stepRepository.save(new AvaAiAgentStepEntity(
			session.task().getId(),
			session.nextStepIndex(),
			toolName,
			status,
			description
		));
	}

	private boolean workspaceHasSignal(WorkspaceActionResult workspace) {
		return workspace != null
			&& (workspace.handled()
				|| (workspace.items() != null && !workspace.items().isEmpty())
				|| (workspace.status() != null && !workspace.status().isBlank()));
	}

	private String riskLevel(AvaAiAgentPolicy.AgentFrame frame) {
		if (frame.mutationIntent()) {
			return "medium";
		}
		if (frame.correctionIntent()) {
			return "medium";
		}
		if (frame.toolRelevant()) {
			return "low";
		}
		return "minimal";
	}

	private AvaAiAgentTaskResponse toResponse(AvaAiAgentTaskEntity task) {
		List<AvaAiAgentStepResponse> steps = stepRepository.findByTaskIdOrderByStepIndexAsc(task.getId())
			.stream()
			.map(this::toResponse)
			.toList();
		return new AvaAiAgentTaskResponse(
			task.getId(),
			task.getStatus().name().toLowerCase(Locale.ROOT),
			task.getMode(),
			task.getRiskLevel(),
			task.getGoal(),
			task.getCurrentStep(),
			task.getSummary(),
			task.getVerificationSummary(),
			task.getFailureReason(),
			steps,
			task.getCreatedAt(),
			task.getUpdatedAt()
		);
	}

	private AvaAiAgentStepResponse toResponse(AvaAiAgentStepEntity step) {
		return new AvaAiAgentStepResponse(
			step.getId(),
			step.getStepIndex(),
			step.getToolName(),
			step.getStatus().name().toLowerCase(Locale.ROOT),
			step.getDescription(),
			step.getResultSummary(),
			step.getVerificationSummary(),
			step.getErrorMessage(),
			step.getCreatedAt(),
			step.getUpdatedAt()
		);
	}

	private String oneLine(String value) {
		return value == null ? "" : value.replaceAll("\\s+", " ").strip();
	}

	private String limit(String value, int maxLength) {
		if (value == null) {
			return "";
		}
		if (value.length() <= maxLength) {
			return value;
		}
		return value.substring(0, Math.max(0, maxLength - 1)) + "…";
	}

	public static final class AgentSession {
		private final AvaAiAgentTaskEntity task;
		private final AvaAiAgentPolicy.AgentFrame frame;
		private int nextStepIndex;

		private AgentSession(AvaAiAgentTaskEntity task, AvaAiAgentPolicy.AgentFrame frame) {
			this.task = task;
			this.frame = frame;
			this.nextStepIndex = 1;
		}

		static AgentSession inactive(AvaAiAgentPolicy.AgentFrame frame) {
			return new AgentSession(null, frame);
		}

		boolean active() {
			return task != null;
		}

		AvaAiAgentTaskEntity task() {
			return task;
		}

		AvaAiAgentPolicy.AgentFrame frame() {
			return frame;
		}

		int nextStepIndex() {
			return nextStepIndex++;
		}
	}
}
