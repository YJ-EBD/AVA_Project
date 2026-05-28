package com.ava.backend.ai.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.Test;

import com.ava.backend.ai.dto.AvaAiNotionPageResponse;
import com.fasterxml.jackson.databind.ObjectMapper;

class AvaAiNotionServiceTest {

	@Test
	void distinguishesFollowUpQuestionsFromWriteCommands() throws Exception {
		AvaAiNotionService service = service();

		assertFalse(isMutationCommand(service, "\uBC29\uAE08 \uCD94\uAC00\uD55C\uAC70 \uC5B4\uB514\uC5D0 \uCD94\uAC00\uD55C\uAC70\uC57C?"));
		assertFalse(isMutationCommand(service, "\uC624\uB298\uBD80\uD130 6\uC6D4 10\uC77C\uAE4C\uC9C0 \uB77C\uB294\uAC70\uC57C \uD504\uB85C\uC81D\uD2B8\uBA85\uC5D0 \uC791\uC131\uD558\uB77C\uB294\uAC8C \uC544\uB2C8\uACE0"));
		assertTrue(isMutationCommand(service, "\uB178\uC158\uC758 \uC5F0\uAD6C\uC18C \uD398\uC774\uC9C0\uC5D0 \uAC1C\uBC1C \uC9C4\uD589\uC0AC\uD56D\uC5D0 AVA_stock \uC608\uC815\uC73C\uB85C \uCD94\uAC00\uD574\uC918"));
		assertTrue(isMutationCommand(service, "노션 연구소 페이지 개발 진행사항에 재고앱 개발이라는 제목 내용 삭제해줘"));
	}

	@Test
	void extractsDateRangeAwayFromDatabaseTitle() throws Exception {
		AvaAiNotionService service = service();
		String command = "\uB178\uC158\uC758 \uC5F0\uAD6C\uC18C \uD398\uC774\uC9C0\uC5D0 \uAC1C\uBC1C \uC9C4\uD589\uC0AC\uD56D\uC5D0 \uD14C\uC2A4\uD2B8 2026\uB144 5\uC6D4 28\uC77C\uBD80\uD130 2026\uB144 6\uC6D4 10\uC77C\uAE4C\uC9C0 \uC608\uC815\uC73C\uB85C \uCD94\uAC00\uD574\uC918";

		assertEquals("\uD14C\uC2A4\uD2B8", mutationTitle(service, command));
		Object range = extractDateRange(service, command);
		assertEquals(LocalDate.of(2026, 5, 28), dateComponent(range, "startDate"));
		assertEquals(LocalDate.of(2026, 6, 10), dateComponent(range, "endDate"));
	}

	@Test
	void extractsQuotedTitleAndTodayRangeForDevelopmentStatusCommand() throws Exception {
		AvaAiNotionService service = service();
		LocalDate today = LocalDate.now();
		LocalDate juneTenth = relativeExpectedDate(today, 6, 10);
		String command = "노션의 연구소 페이지에서 개발 진행사항에 \"재고앱 개발\"제목으로 오늘부터 6월10일까지로 작성해줘 상태는 예정이야";

		assertTrue(isMutationCommand(service, command));
		assertEquals("재고앱 개발", mutationTitle(service, command));
		Object range = extractDateRange(service, command);
		assertEquals(today, dateComponent(range, "startDate"));
		assertEquals(juneTenth, dateComponent(range, "endDate"));
		Map<?, ?> payload = dateRangePayload(service, range);
		Map<?, ?> date = (Map<?, ?>) payload.get("date");
		assertEquals(today.toString(), date.get("start"));
		assertEquals(juneTenth.toString(), date.get("end"));
	}

	@Test
	void understandsDevelopmentStatusWriteCommandsAcrossNaturalLanguageVariants() throws Exception {
		AvaAiNotionService service = service();
		LocalDate today = LocalDate.now();
		LocalDate juneTenth = relativeExpectedDate(today, 6, 10);
		CommandCase[] cases = {
			new CommandCase(
				"노션의 연구소 페이지에서 개발 진행사항에 \"재고앱 개발\"제목으로 오늘부터 6월10일까지로 작성해줘 상태는 예정이야",
				"재고앱 개발",
				today,
				juneTenth,
				"예정"
			),
			new CommandCase(
				"개발 진행사항에 재고앱 개발 제목으로 오늘부터 6/10까지 상태는 예정으로 추가해줘",
				"재고앱 개발",
				today,
				juneTenth,
				"예정"
			),
			new CommandCase(
				"연구소 개발 진행사항에 title: 재고앱 개발 2026-05-28~2026-06-10 todo로 create",
				"재고앱 개발",
				LocalDate.of(2026, 5, 28),
				LocalDate.of(2026, 6, 10),
				"예정"
			),
			new CommandCase(
				"노션 연구소 페이지 개발 진행사항에 재고앱 개발이라는 제목으로 5월28일부터 6.10까지 상태는 예정으로 등록해줘",
				"재고앱 개발",
				LocalDate.of(2026, 5, 28),
				LocalDate.of(2026, 6, 10),
				"예정"
			),
			new CommandCase(
				"개발 진행사항에 재고앱 개발 추가해줘 상태는 예정, 기간 2026.05.28-2026.06.10",
				"재고앱 개발",
				LocalDate.of(2026, 5, 28),
				LocalDate.of(2026, 6, 10),
				"예정"
			)
		};

		for (CommandCase commandCase : cases) {
			assertTrue(isMutationCommand(service, commandCase.command()), commandCase.command());
			assertEquals(commandCase.title(), mutationTitle(service, commandCase.command()), commandCase.command());
			Object range = extractDateRange(service, commandCase.command());
			assertEquals(commandCase.startDate(), dateComponent(range, "startDate"), commandCase.command());
			assertEquals(commandCase.endDate(), dateComponent(range, "endDate"), commandCase.command());
			assertEquals(commandCase.status(), firstStatusCandidate(service, commandCase.command()), commandCase.command());
		}
	}

	@Test
	void understandsDevelopmentStatusDeleteCommandAsApprovedArchivePlan() throws Exception {
		AvaAiNotionService service = service();
		String command = "노션 연구소 페이지 개발 진행사항에 재고앱 개발이라는 제목 내용 삭제해줘";
		AvaAiNotionPageResponse target = notionTarget("database", "개발 진행사항");
		Object type = mutationType(service, command);
		String action = actionName(service, type, target);
		Object plan = mutationPlanForTest(service, command, "재고앱 개발", target, type, action);

		assertEquals("재고앱 개발", planComponent(plan, "title"));
		assertEquals("DELETE", planComponent(plan, "type").toString());
		assertEquals("데이터베이스 항목 삭제", planComponent(plan, "action"));
		String description = approvalDescription(service, command, plan);
		assertTrue(description.contains("제목: 재고앱 개발"));
		assertTrue(description.contains("삭제 방식: Notion 항목 보관 처리(archive)"));
	}

	@Test
	void matchesResearchChildDatabaseAliases() throws Exception {
		AvaAiNotionService service = service();

		assertTrue(databaseTitleMatches(
			service,
			"\uAC1C\uBC1C \uC9C4\uD589\uC0AC\uD56D",
			"\uB178\uC158 \uC5F0\uAD6C\uC18C \uD398\uC774\uC9C0\uC758 \uAC1C\uBC1C \uC9C4\uD589\uC0AC\uD56D\uC5D0 AVA_stock \uC608\uC815\uC73C\uB85C \uCD94\uAC00\uD574\uC918",
			"\uB178\uC158 \uC5F0\uAD6C\uC18C \uD398\uC774\uC9C0 \uAC1C\uBC1C \uC9C4\uD589\uC0AC\uD56D"
		));
		assertTrue(databaseTitleMatches(service, "\uAC1C\uBC1C \uC9C4\uD589\uC0AC\uD56D", "add AVA_stock to research lab development status", ""));
		assertFalse(databaseTitleMatches(
			service,
			"\uC778\uC99D \uC9C4\uD589 \uC0C1\uD669",
			"\uB178\uC158 \uC5F0\uAD6C\uC18C \uD398\uC774\uC9C0\uC758 \uAC1C\uBC1C \uC9C4\uD589\uC0AC\uD56D\uC5D0 AVA_stock \uC608\uC815\uC73C\uB85C \uCD94\uAC00\uD574\uC918",
			"\uB178\uC158 \uC5F0\uAD6C\uC18C \uD398\uC774\uC9C0 \uAC1C\uBC1C \uC9C4\uD589\uC0AC\uD56D"
		));
	}

	@Test
	void runsAtLeastOneMillionConversationRoutingChecks() throws Exception {
		AvaAiNotionService service = service();
		Method mutationMethod = privateMethod("isMutationCommand", String.class);
		String[] followUps = {
			"\uBC29\uAE08 \uCD94\uAC00\uD55C\uAC70 \uC5B4\uB514\uC5D0 \uCD94\uAC00\uD55C\uAC70\uC57C?",
			"\uC624\uB298\uBD80\uD130 6\uC6D4 10\uC77C\uAE4C\uC9C0 \uB77C\uB294\uAC70\uC57C \uD504\uB85C\uC81D\uD2B8\uBA85\uC5D0 \uC791\uC131\uD558\uB77C\uB294\uAC8C \uC544\uB2C8\uACE0",
			"\uADF8 \uB9D0\uC774 \uC544\uB2C8\uACE0 \uB0A0\uC9DC\uB85C \uC785\uB825\uD558\uB77C\uB294\uAC70\uC57C",
			"\uC65C \uD398\uC774\uC9C0\uB97C \uC0DD\uC131\uD588\uC5B4?",
			"where did the item I added go?"
		};
		String[] writeCommands = {
			"\uB178\uC158 \uAC1C\uBC1C \uC9C4\uD589\uC0AC\uD56D\uC5D0 AVA_stock \uC608\uC815\uC73C\uB85C \uCD94\uAC00\uD574\uC918",
			"\uAC1C\uBC1C \uC9C4\uD589\uC0AC\uD56D\uC5D0 \uD14C\uC2A4\uD2B8 \uC9C4\uD589 \uC911\uC73C\uB85C \uB4F1\uB85D\uD574\uC918",
			"add AVA_stock to Notion development status",
			"create a Notion item for AVA_stock",
			"\uC5F0\uAD6C\uC18C \uD398\uC774\uC9C0 \uAC1C\uBC1C \uC9C4\uD589\uC0AC\uD56D\uC5D0 \uD14C\uC2A4\uD2B8 \uC608\uC815\uC73C\uB85C \uC791\uC131\uD574\uC918"
		};

		int checks = 0;
		for (int index = 0; index < 500_000; index++) {
			String prompt = followUps[index % followUps.length] + " #" + index;
			assertFalse((boolean) mutationMethod.invoke(service, prompt), "Follow-up should not mutate: " + prompt);
			checks++;
		}
		for (int index = 0; index < 500_000; index++) {
			String prompt = writeCommands[index % writeCommands.length] + " #" + index;
			assertTrue((boolean) mutationMethod.invoke(service, prompt), "Explicit write should mutate: " + prompt);
			checks++;
		}
		assertTrue(isLastMutationQuestion(service, followUps[0]));
		assertEquals(1_000_000, checks);
	}

	private AvaAiNotionService service() {
		return new AvaAiNotionService(
			new ObjectMapper(),
			"notion-test-token",
			"2022-06-28",
			"2026-03-11",
			"2c0cc184-a41e-80bd-b384-ccf77802a170",
			"345cc184-a41e-8025-8e4c-d0b101e8de6b",
			5
		);
	}

	private boolean isMutationCommand(AvaAiNotionService service, String command) throws Exception {
		return (boolean) privateMethod("isMutationCommand", String.class).invoke(service, command);
	}

	private boolean isLastMutationQuestion(AvaAiNotionService service, String command) throws Exception {
		return (boolean) privateMethod("isLastMutationQuestion", String.class).invoke(service, command);
	}

	private String mutationTitle(AvaAiNotionService service, String command) throws Exception {
		Method method = privateMethod(
			"mutationTitle",
			String.class,
			String.class,
			String.class
		);
		return (String) method.invoke(
			service,
			command,
			"\uAC1C\uBC1C \uC9C4\uD589\uC0AC\uD56D",
			"\uB178\uC158\uC758 \uC5F0\uAD6C\uC18C \uD398\uC774\uC9C0 \uAC1C\uBC1C \uC9C4\uD589\uC0AC\uD56D"
		);
	}

	private Object mutationPlan(AvaAiNotionService service, String command) throws Exception {
		return privateMethod("mutationPlan", String.class, String.class, String.class)
			.invoke(service, command, "", "");
	}

	private Object mutationType(AvaAiNotionService service, String command) throws Exception {
		return privateMethod("mutationType", String.class).invoke(service, command);
	}

	private String actionName(AvaAiNotionService service, Object type, AvaAiNotionPageResponse target) throws Exception {
		Method method = privateMethod("actionName", type.getClass(), AvaAiNotionPageResponse.class);
		return (String) method.invoke(service, type, target);
	}

	private AvaAiNotionPageResponse notionTarget(String object, String title) {
		return new AvaAiNotionPageResponse(
			"notion-test-target",
			object,
			title,
			"",
			"https://www.notion.so/test",
			"",
			"",
			"",
			null,
			List.of(),
			List.of(),
			List.of()
		);
	}

	private Object mutationPlanForTest(
		AvaAiNotionService service,
		String command,
		String title,
		AvaAiNotionPageResponse target,
		Object type,
		String action
	) throws Exception {
		Object range = extractDateRange(service, command);
		Class<?> planClass = Class.forName("com.ava.backend.ai.service.AvaAiNotionService$NotionMutationPlan");
		Constructor<?> constructor = planClass.getDeclaredConstructor(
			String.class,
			range.getClass(),
			String.class,
			AvaAiNotionPageResponse.class,
			type.getClass(),
			String.class
		);
		constructor.setAccessible(true);
		return constructor.newInstance(
			title,
			range,
			"노션 연구소 페이지 개발 진행사항",
			target,
			type,
			action
		);
	}

	private Object planComponent(Object plan, String name) throws Exception {
		Method method = plan.getClass().getDeclaredMethod(name);
		method.setAccessible(true);
		return method.invoke(plan);
	}

	private String approvalDescription(AvaAiNotionService service, String command, Object plan) throws Exception {
		Method method = privateMethod("approvalDescription", String.class, plan.getClass());
		return (String) method.invoke(service, command, plan);
	}

	private Object extractDateRange(AvaAiNotionService service, String command) throws Exception {
		return privateMethod("extractDateRange", String.class).invoke(service, command);
	}

	private boolean databaseTitleMatches(
		AvaAiNotionService service,
		String databaseTitle,
		String command,
		String targetQuery
	) throws Exception {
		return (boolean) privateMethod("databaseTitleMatches", String.class, String.class, String.class)
			.invoke(service, databaseTitle, command, targetQuery);
	}

	private LocalDate dateComponent(Object range, String name) throws Exception {
		Method method = range.getClass().getDeclaredMethod(name);
		method.setAccessible(true);
		return (LocalDate) method.invoke(range);
	}

	private LocalDate relativeExpectedDate(LocalDate baseDate, int month, int day) {
		LocalDate date = LocalDate.of(baseDate.getYear(), month, day);
		return date.isBefore(baseDate.minusDays(1)) ? date.plusYears(1) : date;
	}

	@SuppressWarnings("unchecked")
	private Map<?, ?> dateRangePayload(AvaAiNotionService service, Object range) throws Exception {
		Method method = privateMethod("dateRangePayload", range.getClass());
		return (Map<?, ?>) method.invoke(service, range);
	}

	@SuppressWarnings("unchecked")
	private String firstStatusCandidate(AvaAiNotionService service, String command) throws Exception {
		Method method = privateMethod("statusCandidates", String.class);
		return ((java.util.List<String>) method.invoke(service, command)).getFirst();
	}

	private Method privateMethod(String name, Class<?>... parameterTypes) throws Exception {
		Method method = AvaAiNotionService.class.getDeclaredMethod(name, parameterTypes);
		method.setAccessible(true);
		return method;
	}

	private record CommandCase(
		String command,
		String title,
		LocalDate startDate,
		LocalDate endDate,
		String status
	) {
	}
}
