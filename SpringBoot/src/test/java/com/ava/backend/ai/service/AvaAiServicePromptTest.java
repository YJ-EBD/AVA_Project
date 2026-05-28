package com.ava.backend.ai.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.lang.reflect.Method;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.Test;

import com.ava.backend.ai.entity.AvaAiConversationEntity;
import com.ava.backend.ai.entity.AvaAiKnowledgeItemEntity;
import com.ava.backend.ai.entity.AvaAiMessageEntity;
import com.ava.backend.ai.entity.AvaAiMessageRole;
import com.ava.backend.ai.repository.AvaAiMessageRepository;
import com.ava.backend.ai.service.AvaAiToolRegistry.ToolExecution;
import com.ava.backend.ai.service.AvaAiWorkspaceService.WorkspaceActionResult;

class AvaAiServicePromptTest {

	@Test
	void systemPromptCarriesAgentContractAndRecentToolState() throws Exception {
		AvaAiService service = new AvaAiService(
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			5,
			48
		);
		UUID conversationId = UUID.randomUUID();
		UUID accountId = UUID.randomUUID();
		AvaAiMessageEntity toolMessage = new AvaAiMessageEntity(
			conversationId,
			accountId,
			"ABAS",
			AvaAiMessageRole.ASSISTANT,
			"Notion에 반영했습니다. 대상: 개발 진행사항, 제목: AVA_stock, 상태: 예정",
			"direct-api/write-approved"
		);
		toolMessage.setCreatedAt(Instant.parse("2026-05-28T01:00:00Z"));

		Method method = AvaAiService.class.getDeclaredMethod(
			"systemPrompt",
			String.class,
			List.class,
			List.class,
			String.class,
			String.class,
			String.class,
			List.class
		);
		method.setAccessible(true);

		String prompt = (String) method.invoke(
			service,
			"ABAS",
			List.of(),
			List.of(),
			"",
			"\n[RECENT AGENT TASKS]\n- 2026-05-28T01:00:00Z DONE tool-read-verify goal=서버 헬스체크 verified=UP 확인\n",
			"방금 추가한거 어디에 추가한거야?",
			List.of(toolMessage)
		);

		assertTrue(prompt.contains("[AGENT WORK CONTRACT]"));
		assertTrue(prompt.contains("[RECENT AGENT TASKS]"));
		assertTrue(prompt.contains("[RECENT TOOL STATE]"));
		assertTrue(prompt.contains("direct-api/write-approved"));
		assertTrue(prompt.contains("AVA_stock"));
		assertTrue(prompt.contains("서버 헬스체크"));
		assertTrue(prompt.contains("verified tool/API outcomes"));
		assertTrue(prompt.contains("실행 없이 미래 동작을 약속하는 응답은 금지"));
	}

	@Test
	void deferredPromiseOnlyWorkAnswerIsBlockedBeforeSaving() throws Exception {
		AvaAiService service = new AvaAiService(
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			5,
			48
		);
		Method method = AvaAiService.class.getDeclaredMethod(
			"enforceActionableWorkAnswer",
			String.class,
			String.class,
			WorkspaceActionResult.class,
			ToolExecution.class
		);
		method.setAccessible(true);

		String answer = (String) method.invoke(
			service,
			"노션 연구소 페이지 개발 진행사항에 재고앱 개발이라는 제목 내용 삭제해줘",
			"삭제 작업을 다시 시도합니다. 현재 노션 API를 통해 '재고앱 개발' 항목을 조회하고 삭제 명령을 실행하겠습니다. 잠시만 기다려 주세요.",
			new WorkspaceActionResult(List.of(), "", "", false),
			ToolExecution.notHandled()
		);

		assertTrue(answer.contains("실행 결과 없이 기다리라는 응답을 차단했습니다."));
		assertTrue(answer.contains("실제 작업은 수행하지 않았습니다."));
		assertTrue(answer.contains("tool-plan-act-verify"));
		assertTrue(!answer.contains("잠시만 기다려 주세요"));
	}

	@Test
	void verifiedWorkAnswerIsNotBlocked() throws Exception {
		AvaAiService service = new AvaAiService(
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			5,
			48
		);
		Method method = AvaAiService.class.getDeclaredMethod(
			"enforceActionableWorkAnswer",
			String.class,
			String.class,
			WorkspaceActionResult.class,
			ToolExecution.class
		);
		method.setAccessible(true);

		String original = "서버 헬스체크 완료: Spring Boot actuator가 `UP`입니다. (HTTP 200)";
		String answer = (String) method.invoke(
			service,
			"서버 상태 확인해줘",
			original,
			new WorkspaceActionResult(List.of(), "", "", false),
			ToolExecution.notHandled()
		);

		assertEquals(original, answer);
	}

	@Test
	@SuppressWarnings("unchecked")
	void buildPromptCompressesLargeDirectContextUnderSafeBudget() throws Exception {
		AvaAiMessageRepository messageRepository = mock(AvaAiMessageRepository.class);
		AvaAiService service = new AvaAiService(
			null,
			messageRepository,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			5,
			48
		);
		UUID accountId = UUID.randomUUID();
		AvaAiConversationEntity conversation = new AvaAiConversationEntity(accountId, "ABAS", "AVA AI");
		AvaAiMessageEntity current = message(
			conversation.getId(),
			accountId,
			AvaAiMessageRole.USER,
			"방금 작업 이어서 상태를 정리하고 다음 조치를 알려줘",
			null,
			Instant.parse("2026-05-28T02:00:00Z")
		);
		List<AvaAiMessageEntity> recent = new ArrayList<>();
		for (int index = 0; index < 36; index++) {
			AvaAiMessageRole role = index % 2 == 0 ? AvaAiMessageRole.USER : AvaAiMessageRole.ASSISTANT;
			String modelName = role == AvaAiMessageRole.ASSISTANT && index % 5 == 0
				? "direct-api/write-approved"
				: null;
			recent.add(message(
				conversation.getId(),
				accountId,
				role,
				("긴 한국어 대화 히스토리와 검증 상태를 압축해야 합니다. " + index + " ").repeat(90),
				modelName,
				Instant.parse("2026-05-28T01:00:00Z").plusSeconds(index)
			));
		}
		recent.add(current);
		when(messageRepository.findTop200ByConversationIdOrderByCreatedAtDesc(conversation.getId()))
			.thenReturn(recent.stream()
				.sorted(Comparator.comparing(AvaAiMessageEntity::getCreatedAt).reversed())
				.toList());

		Method buildPrompt = AvaAiService.class.getDeclaredMethod(
			"buildPrompt",
			AvaAiConversationEntity.class,
			AvaAiMessageEntity.class,
			List.class,
			List.class,
			String.class,
			String.class
		);
		buildPrompt.setAccessible(true);
		Method estimatedPromptTokens = AvaAiService.class.getDeclaredMethod("estimatedPromptTokens", List.class);
		estimatedPromptTokens.setAccessible(true);

		List<com.ava.backend.ai.service.AvaAiLlmClient.PromptMessage> prompt =
			(List<com.ava.backend.ai.service.AvaAiLlmClient.PromptMessage>) buildPrompt.invoke(
				service,
				conversation,
				current,
				List.<AvaAiKnowledgeItemEntity>of(),
				List.of(),
				("작업공간 결과도 길게 들어올 수 있습니다. ").repeat(120),
				("\n[RECENT AGENT TASKS]\n- DONE 검증 요약과 복구 체크포인트 ".repeat(160))
			);
		int tokenEstimate = (int) estimatedPromptTokens.invoke(service, prompt);

		assertTrue(tokenEstimate <= 2_650, "Compressed prompt estimate was " + tokenEstimate);
		assertTrue(prompt.get(prompt.size() - 1).content().contains("방금 작업 이어서"));
		assertTrue(prompt.get(0).content().contains("[AGENT WORK CONTRACT"));
	}

	@Test
	void contextOverflowFallsBackToEmergencyPrompt() throws Exception {
		AvaAiLlmClient llmClient = mock(AvaAiLlmClient.class);
		when(llmClient.complete(any()))
			.thenThrow(new IllegalStateException("LLM server returned 400: request exceeds the available context size"))
			.thenReturn("압축 프롬프트로 응답했습니다.");
		AvaAiService service = new AvaAiService(
			null,
			null,
			null,
			null,
			null,
			llmClient,
			null,
			null,
			null,
			null,
			null,
			null,
			5,
			48
		);
		AvaAiMessageEntity current = message(
			UUID.randomUUID(),
			UUID.randomUUID(),
			AvaAiMessageRole.USER,
			"이어서 현재 상태를 정리해줘",
			null,
			Instant.parse("2026-05-28T03:00:00Z")
		);
		Method method = AvaAiService.class.getDeclaredMethod(
			"completeWithContextFallback",
			List.class,
			AvaAiMessageEntity.class,
			List.class,
			String.class,
			String.class
		);
		method.setAccessible(true);

		String answer = (String) method.invoke(
			service,
			List.of(new AvaAiLlmClient.PromptMessage("system", "긴 프롬프트")),
			current,
			List.of(),
			"작업공간 컨텍스트",
			"[RECENT AGENT TASKS] DONE"
		);

		assertEquals("압축 프롬프트로 응답했습니다.", answer);
	}

	private AvaAiMessageEntity message(
		UUID conversationId,
		UUID accountId,
		AvaAiMessageRole role,
		String content,
		String modelName,
		Instant createdAt
	) {
		AvaAiMessageEntity message = new AvaAiMessageEntity(
			conversationId,
			accountId,
			"ABAS",
			role,
			content,
			modelName
		);
		message.setCreatedAt(createdAt);
		return message;
	}
}
