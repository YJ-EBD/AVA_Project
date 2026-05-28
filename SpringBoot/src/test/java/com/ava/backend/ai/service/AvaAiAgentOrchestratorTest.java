package com.ava.backend.ai.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.Test;

import com.ava.backend.ai.dto.AvaAiAgentTaskResponse;
import com.ava.backend.ai.entity.AvaAiAgentStepEntity;
import com.ava.backend.ai.entity.AvaAiAgentStepStatus;
import com.ava.backend.ai.entity.AvaAiAgentTaskEntity;
import com.ava.backend.ai.entity.AvaAiAgentTaskStatus;
import com.ava.backend.ai.entity.AvaAiConversationEntity;
import com.ava.backend.ai.entity.AvaAiMessageEntity;
import com.ava.backend.ai.entity.AvaAiMessageRole;
import com.ava.backend.ai.repository.AvaAiAgentStepRepository;
import com.ava.backend.ai.repository.AvaAiAgentTaskRepository;

class AvaAiAgentOrchestratorTest {

	@Test
	void failedToolRunsReadOnlyRecoveryVerification() {
		AvaAiAgentTaskRepository taskRepository = mock(AvaAiAgentTaskRepository.class);
		AvaAiAgentStepRepository stepRepository = mock(AvaAiAgentStepRepository.class);
		List<AvaAiAgentStepEntity> savedSteps = new ArrayList<>();
		when(taskRepository.save(any(AvaAiAgentTaskEntity.class))).thenAnswer(invocation -> invocation.getArgument(0));
		when(stepRepository.save(any(AvaAiAgentStepEntity.class))).thenAnswer(invocation -> {
			AvaAiAgentStepEntity step = invocation.getArgument(0);
			savedSteps.add(step);
			return step;
		});

		AvaAiAgentOrchestrator orchestrator = new AvaAiAgentOrchestrator(
			taskRepository,
			stepRepository,
			new FailingThenRecoveringToolRegistry()
		);
		UUID accountId = UUID.randomUUID();
		AvaAiConversationEntity conversation = new AvaAiConversationEntity(accountId, "ABBA-S", "test");
		AvaAiMessageEntity userMessage = new AvaAiMessageEntity(
			conversation.getId(),
			accountId,
			"ABBA-S",
			AvaAiMessageRole.USER,
			"백엔드 테스트 실행해줘",
			null
		);

		AvaAiAgentOrchestrator.AgentSession session = orchestrator.start(
			conversation,
			userMessage,
			userMessage.getContent()
		);
		AvaAiToolRegistry.ToolExecution execution = orchestrator.runAutomaticTool(
			session,
			userMessage.getContent()
		);

		assertTrue(execution.handled());
		assertTrue(execution.verified());
		assertTrue(execution.answer().contains("[복구 검증]"));
		assertTrue(savedSteps.stream().anyMatch(step -> step.getToolName().equals("recovery.server.logs")));
		assertEquals(
			AvaAiAgentStepStatus.DONE,
			savedSteps.stream()
				.filter(step -> step.getToolName().equals("recovery.server.logs"))
				.reduce((first, second) -> second)
				.orElseThrow()
				.getStatus()
		);
		verify(taskRepository, atLeastOnce()).save(any(AvaAiAgentTaskEntity.class));
	}

	@Test
	void recoveredToolFailureCompletesTaskAsRecoveredInsteadOfPlainFailed() {
		AvaAiAgentTaskRepository taskRepository = mock(AvaAiAgentTaskRepository.class);
		AvaAiAgentStepRepository stepRepository = mock(AvaAiAgentStepRepository.class);
		List<AvaAiAgentTaskEntity> savedTasks = new ArrayList<>();
		List<AvaAiAgentStepEntity> savedSteps = new ArrayList<>();
		when(taskRepository.save(any(AvaAiAgentTaskEntity.class))).thenAnswer(invocation -> {
			AvaAiAgentTaskEntity task = invocation.getArgument(0);
			savedTasks.add(task);
			return task;
		});
		when(stepRepository.save(any(AvaAiAgentStepEntity.class))).thenAnswer(invocation -> {
			AvaAiAgentStepEntity step = invocation.getArgument(0);
			savedSteps.add(step);
			return step;
		});
		when(stepRepository.findByTaskIdOrderByStepIndexAsc(any())).thenAnswer(invocation -> savedSteps.stream()
			.filter(step -> step.getTaskId().equals(invocation.getArgument(0)))
			.distinct()
			.toList());

		AvaAiAgentOrchestrator orchestrator = new AvaAiAgentOrchestrator(
			taskRepository,
			stepRepository,
			new FailingThenRecoveringToolRegistry()
		);
		UUID accountId = UUID.randomUUID();
		AvaAiConversationEntity conversation = new AvaAiConversationEntity(accountId, "ABBA-S", "test");
		AvaAiMessageEntity userMessage = new AvaAiMessageEntity(
			conversation.getId(),
			accountId,
			"ABBA-S",
			AvaAiMessageRole.USER,
			"백엔드 테스트 실행해줘",
			null
		);

		AvaAiAgentOrchestrator.AgentSession session = orchestrator.start(
			conversation,
			userMessage,
			userMessage.getContent()
		);
		AvaAiToolRegistry.ToolExecution execution = orchestrator.runAutomaticTool(
			session,
			userMessage.getContent()
		);
		AvaAiAgentTaskResponse response = orchestrator.complete(
			session,
			execution.answer(),
			null,
			execution
		);

		assertEquals("recovered", response.status());
		assertEquals(AvaAiAgentTaskStatus.RECOVERED, savedTasks.get(savedTasks.size() - 1).getStatus());
		assertTrue(response.failureReason().contains("test failed"));
		assertTrue(response.verificationSummary().contains("recovery=read-only recovery verified"));
	}

	@Test
	void startRecordsDurableResumeCheckpointForLongAutonomousWork() {
		AvaAiAgentTaskRepository taskRepository = mock(AvaAiAgentTaskRepository.class);
		AvaAiAgentStepRepository stepRepository = mock(AvaAiAgentStepRepository.class);
		List<AvaAiAgentStepEntity> savedSteps = new ArrayList<>();
		when(taskRepository.save(any(AvaAiAgentTaskEntity.class))).thenAnswer(invocation -> invocation.getArgument(0));
		when(stepRepository.save(any(AvaAiAgentStepEntity.class))).thenAnswer(invocation -> {
			AvaAiAgentStepEntity step = invocation.getArgument(0);
			savedSteps.add(step);
			return step;
		});

		AvaAiAgentOrchestrator orchestrator = new AvaAiAgentOrchestrator(
			taskRepository,
			stepRepository,
			new FailingThenRecoveringToolRegistry()
		);
		UUID accountId = UUID.randomUUID();
		AvaAiConversationEntity conversation = new AvaAiConversationEntity(accountId, "ABBA-S", "test");
		AvaAiMessageEntity userMessage = new AvaAiMessageEntity(
			conversation.getId(),
			accountId,
			"ABBA-S",
			AvaAiMessageRole.USER,
			"이어서 백엔드 테스트하고 실패하면 원인 확인까지 진행해줘",
			null
		);

		orchestrator.start(conversation, userMessage, userMessage.getContent());

		assertTrue(savedSteps.stream().anyMatch(step -> step.getToolName().equals("state.checkpoint")));
		assertTrue(savedSteps.stream()
			.filter(step -> step.getToolName().equals("state.checkpoint"))
			.anyMatch(step -> step.getResultSummary().contains("userMessage=" + userMessage.getId())));
	}

	private static final class FailingThenRecoveringToolRegistry extends AvaAiToolRegistry {

		FailingThenRecoveringToolRegistry() {
			super(8080, 15);
		}

		@Override
		public java.util.Optional<ToolRequest> select(String content) {
			return java.util.Optional.of(new ToolRequest(
				"build.gradleTest",
				"백엔드 테스트 실행",
				true
			));
		}

		@Override
		public ToolExecution execute(ToolRequest request) {
			if (request.toolName().equals("server.logs")) {
				return new ToolExecution(
					"server.logs",
					true,
					true,
					true,
					false,
					"최근 로그를 확인했습니다.",
					"log read ok",
					"read-only recovery verified",
					"",
					"ava-agent/server.logs"
				);
			}
			return new ToolExecution(
				request.toolName(),
				true,
				false,
				false,
				false,
				"백엔드 테스트 실패",
				"gradle test exitCode=1",
				"프로세스 종료 코드가 0이 아닙니다.",
				"test failed",
				"ava-agent/build.gradleTest"
			);
		}
	}
}
