package com.ava.backend.ai.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

class AvaAiToolRegistryTest {

	private final AvaAiToolRegistry registry = new AvaAiToolRegistry(8080, 15);

	@Test
	void selectsSafeServerHealthTool() {
		AvaAiToolRegistry.ToolRequest request = registry.select("서버 헬스체크 확인해줘")
			.orElseThrow();

		assertEquals("server.health", request.toolName());
		assertTrue(request.executable());
	}

	@Test
	void classifiesRestartAsExternalOperation() {
		AvaAiToolRegistry.ToolRequest request = registry.select("AVA_PROJECT 모든 서버 재시작해줘")
			.orElseThrow();

		assertEquals("server.restart", request.toolName());
		assertFalse(request.executable());

		AvaAiToolRegistry.ToolExecution execution = registry.execute(request);
		assertTrue(execution.handled());
		assertTrue(execution.waitingApproval());
		assertFalse(execution.success());
	}

	@Test
	void selectsBuildToolsOnlyForExplicitRequests() {
		assertEquals(
			"build.gradleTest",
			registry.select("백엔드 테스트 실행해줘").orElseThrow().toolName()
		);
		assertEquals(
			"build.flutterAnalyze",
			registry.select("Flutter analyze 실행해줘").orElseThrow().toolName()
		);
		assertTrue(registry.select("그냥 설명만 해줘").isEmpty());
	}
}
