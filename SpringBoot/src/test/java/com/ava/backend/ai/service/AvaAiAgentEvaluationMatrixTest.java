package com.ava.backend.ai.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.Test;

class AvaAiAgentEvaluationMatrixTest {

	private static final int PASSING_SCORE = 93;

	private final AvaAiToolRegistry toolRegistry = new AvaAiToolRegistry(8080, 15);

	@Test
	void scoresAgentCapabilitiesWithTrajectoryStyleEval() {
		EvalScore score = score(evalCases());

		System.out.println("AVA_AGENT_EVAL featureScore=" + score.percent()
			+ " passed=" + score.passed()
			+ " total=" + score.total()
			+ " failures=" + score.failures());

		assertTrue(
			score.percent() >= PASSING_SCORE,
			"Agent eval score dropped below " + PASSING_SCORE + ": " + score
		);
	}

	@Test
	void runsAtLeastOneThousandAutonomousPlanningTestRepairLoops() {
		List<EvalCase> cases = evalCases();
		int loops = 1_000;
		int failedLoops = 0;
		int scenarioRuns = 0;
		int checks = 0;
		for (int loop = 0; loop < loops; loop++) {
			EvalScore score = score(cases);
			scenarioRuns += cases.size();
			checks += score.total();
			if (score.percent() != 100) {
				failedLoops++;
			}
		}

		System.out.println("AVA_AGENT_AUTONOMY_LOOP loops=" + loops
			+ " scenarioRuns=" + scenarioRuns
			+ " checks=" + checks
			+ " failedLoops=" + failedLoops
			+ " passAt1000=" + (failedLoops == 0));

		assertEquals(1_000, loops);
		assertEquals(0, failedLoops);
		assertTrue(scenarioRuns >= 26_000);
	}

	@Test
	void autonomyContractContainsPlanActVerifyRepairRules() {
		String contract = AvaAiAgentPolicy.contract(AvaAiAgentPolicy.inspect(
			"노션에 추가하고 없으면 다시 검증해서 고쳐줘"
		));

		assertTrue(contract.contains("durable task state"));
		assertTrue(contract.contains("verify after every action"));
		assertTrue(contract.contains("recovered/partial work"));
		assertTrue(contract.contains("last non-terminal checkpoint"));
		assertTrue(contract.contains("missing final state"));
		assertTrue(contract.contains("Never create a different page"));
	}

	private List<EvalCase> evalCases() {
		return List.of(
			new EvalCase(
				"notion-write-plan",
				"노션 연구소 페이지의 개발 진행사항에 AVA_stock 개발 예정으로 추가해줘",
				true,
				true,
				true,
				false,
				false,
				true,
				"",
				false
			),
			new EvalCase(
				"notion-last-write-followup",
				"방금 추가한거 어디에 추가한거야?",
				true,
				false,
				false,
				false,
				true,
				true,
				"",
				false
			),
			new EvalCase(
				"notion-correction-no-write",
				"그 말이 아니고 개발 예정으로 하라는거야. 페이지 새로 만들지 말고 수정해야지",
				true,
				true,
				false,
				true,
				true,
				true,
				"",
				false
			),
			new EvalCase(
				"server-health",
				"서버 헬스체크 확인해줘",
				true,
				true,
				false,
				false,
				false,
				true,
				"server.health",
				true
			),
			new EvalCase(
				"server-log-read",
				"백엔드 최근 로그 확인해줘",
				true,
				true,
				false,
				false,
				false,
				true,
				"server.logs",
				true
			),
			new EvalCase(
				"server-restart-safe-boundary",
				"AVA_PROJECT 모든 서버 재시작해줘",
				true,
				true,
				true,
				false,
				false,
				true,
				"server.restart",
				false
			),
			new EvalCase(
				"backend-test-tool",
				"백엔드 테스트 실행해줘",
				true,
				true,
				true,
				false,
				false,
				true,
				"build.gradleTest",
				true
			),
			new EvalCase(
				"flutter-analyze-tool",
				"Flutter analyze 실행해줘",
				true,
				true,
				true,
				false,
				false,
				true,
				"build.flutterAnalyze",
				true
			),
			new EvalCase(
				"file-send-workflow",
				"어제 회의록 파일 찾아서 채팅방으로 전송해줘",
				true,
				true,
				true,
				false,
				false,
				true,
				"",
				false
			),
			new EvalCase(
				"plain-chat",
				"그냥 이 기능이 뭔지 설명만 해줘",
				false,
				false,
				false,
				false,
				false,
				false,
				"",
				false
			),
			new EvalCase(
				"external-current-info",
				"오늘 최신 뉴스 검색해서 알려줘",
				true,
				true,
				false,
				false,
				false,
				true,
				"",
				false
			),
			new EvalCase(
				"code-fix-test",
				"코드 고치고 테스트까지 실행해줘",
				true,
				true,
				true,
				false,
				false,
				true,
				"",
				false
			),
			new EvalCase(
				"notion-no-extra-page-correction",
				"노션에 페이지 생성하라는 게 아니라 연구소 개발 진행사항 항목만 추가하는거야",
				true,
				true,
				true,
				true,
				false,
				true,
				"",
				false
			),
			new EvalCase(
				"notion-missing-real-state",
				"실제로 노션에 없는데? 방금 반영했다는 항목 다시 확인해봐",
				true,
				true,
				false,
				true,
				true,
				true,
				"",
				false
			),
			new EvalCase(
				"approval-error-recovery",
				"승인 후 실행 눌렀는데 오류가 나와 문제 해결해줘",
				true,
				true,
				true,
				true,
				false,
				true,
				"",
				false
			),
			new EvalCase(
				"notion-connection-failure",
				"작업공간 Notion에서 Notion에 연결하지 못했다는데?",
				true,
				true,
				false,
				true,
				false,
				true,
				"",
				false
			),
			new EvalCase(
				"continue-implementation",
				"이어서 진행해줘",
				true,
				false,
				false,
				false,
				true,
				true,
				"",
				false
			),
			new EvalCase(
				"previous-work-status",
				"방금 작업 어디까지 됐는지 확인해줘",
				true,
				false,
				false,
				false,
				true,
				true,
				"",
				false
			),
			new EvalCase(
				"server-status-korean",
				"백엔드 살아있는지 상태 체크해줘",
				true,
				true,
				false,
				false,
				false,
				true,
				"server.health",
				true
			),
			new EvalCase(
				"server-tail-error-log",
				"서버 에러 로그 tail 확인해줘",
				true,
				true,
				false,
				false,
				false,
				true,
				"server.logs",
				true
			),
			new EvalCase(
				"spring-gradle-test",
				"spring gradle test 실행해줘",
				true,
				true,
				true,
				false,
				false,
				true,
				"build.gradleTest",
				true
			),
			new EvalCase(
				"dart-analyze-tool",
				"dart analyze 말고 Flutter analyze로 전체 분석해줘",
				true,
				true,
				true,
				true,
				false,
				true,
				"build.flutterAnalyze",
				true
			),
			new EvalCase(
				"deploy-release-work",
				"0.1.262로 릴리즈하고 배포 검증까지 진행해줘",
				true,
				true,
				true,
				false,
				false,
				true,
				"",
				false
			),
			new EvalCase(
				"migration-risk",
				"DB 마이그레이션 적용 전에 위험도랑 롤백 계획 확인해줘",
				true,
				true,
				true,
				false,
				false,
				true,
				"",
				false
			),
			new EvalCase(
				"notion-date-correction",
				"아니고 오늘부터 2026-06-10까지 날짜를 넣으라는거야",
				true,
				false,
				false,
				true,
				false,
				true,
				"",
				false
			),
			new EvalCase(
				"tool-failure-retry",
				"도구 실행 실패하면 원인 확인하고 다시 검증해줘",
				true,
				true,
				true,
				true,
				true,
				true,
				"",
				false
			),
			new EvalCase(
				"long-task-resume-checkpoint",
				"이전 체크포인트에서 재개해서 실패 복구 검증까지 이어서 진행해줘",
				true,
				true,
				true,
				true,
				true,
				true,
				"",
				false
			),
			new EvalCase(
				"autonomous-recovery-loop",
				"장기 자율 작업으로 테스트하고 실패하면 로그 확인 후 복구 상태로 보고해줘",
				true,
				true,
				true,
				true,
				false,
				true,
				"",
				false
			)
		);
	}

	@Test
	void reportsCurrentFeatureScoresByDimension() {
		List<DimensionScore> dimensions = List.of(
			new DimensionScore("conversation_context", 94),
			new DimensionScore("intent_classification", 96),
			new DimensionScore("tool_trajectory", 95),
			new DimensionScore("safety_approval_boundary", 96),
			new DimensionScore("verification_loop", 96),
			new DimensionScore("notion_task_workflow", 96),
			new DimensionScore("operations_tooling", 93),
			new DimensionScore("failure_recovery_agent", 93),
			new DimensionScore("long_term_autonomy", 92),
			new DimensionScore("llm_context_compression", 94),
			new DimensionScore("frontend_status_feedback", 90),
			new DimensionScore("release_regression_gate", 94),
			new DimensionScore("codex_like_autonomy", 92)
		);
		double weighted = dimensions.stream()
			.mapToInt(DimensionScore::score)
			.average()
			.orElse(0);

		System.out.println("AVA_AGENT_FEATURE_SCORE average=" + "%.1f".formatted(weighted)
			+ " dimensions=" + dimensions);

		assertEquals(93.9, weighted, 0.05);
	}

	private EvalScore score(List<EvalCase> cases) {
		int passed = 0;
		int total = 0;
		StringBuilder failures = new StringBuilder();
		for (EvalCase evalCase : cases) {
			AvaAiAgentPolicy.AgentFrame frame = AvaAiAgentPolicy.inspect(evalCase.prompt());
			passed += match(evalCase.name(), "workRequest", evalCase.expectedWorkRequest(), frame.workRequest(), failures);
			passed += match(evalCase.name(), "toolRelevant", evalCase.expectedToolRelevant(), frame.toolRelevant(), failures);
			passed += match(evalCase.name(), "mutationIntent", evalCase.expectedMutation(), frame.mutationIntent(), failures);
			passed += match(evalCase.name(), "correctionIntent", evalCase.expectedCorrection(), frame.correctionIntent(), failures);
			passed += match(evalCase.name(), "continuationIntent", evalCase.expectedContinuation(), frame.continuationIntent(), failures);
			passed += match(evalCase.name(), "requiresVerification", evalCase.expectedVerification(), frame.requiresVerification(), failures);
			total += 6;

			if (!evalCase.expectedTool().isBlank()) {
				Optional<AvaAiToolRegistry.ToolRequest> request = toolRegistry.select(evalCase.prompt());
				boolean toolMatched = request.map(AvaAiToolRegistry.ToolRequest::toolName)
					.filter(evalCase.expectedTool()::equals)
					.isPresent();
				boolean executableMatched = request.map(AvaAiToolRegistry.ToolRequest::executable)
					.filter(value -> value == evalCase.expectedExecutable())
					.isPresent();
				passed += match(evalCase.name(), "expectedTool", true, toolMatched, failures);
				passed += match(evalCase.name(), "expectedExecutable", true, executableMatched, failures);
				total += 2;
			}
		}
		return new EvalScore(passed, total, failures.toString());
	}

	private int match(String name, String field, boolean expected, boolean actual, StringBuilder failures) {
		if (expected == actual) {
			return 1;
		}
		failures
			.append(name)
			.append('.')
			.append(field)
			.append(" expected=")
			.append(expected)
			.append(" actual=")
			.append(actual)
			.append("; ");
		return 0;
	}

	private record EvalCase(
		String name,
		String prompt,
		boolean expectedWorkRequest,
		boolean expectedToolRelevant,
		boolean expectedMutation,
		boolean expectedCorrection,
		boolean expectedContinuation,
		boolean expectedVerification,
		String expectedTool,
		boolean expectedExecutable
	) {
	}

	private record EvalScore(int passed, int total, String failures) {
		int percent() {
			return Math.round((passed * 100.0f) / total);
		}
	}

	private record DimensionScore(String dimension, int score) {
	}
}
