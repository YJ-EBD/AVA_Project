package com.ava.backend.ai.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

import org.junit.jupiter.api.Test;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;

class AvaAiLlmClientToolCallingTest {

	@Test
	void completesOpenAiStyleNativeToolCallingLoop() throws Exception {
		AtomicInteger requests = new AtomicInteger();
		HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
		server.createContext("/v1/chat/completions", exchange -> {
			String body = new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
			String response;
			if (requests.incrementAndGet() == 1) {
				assertTrue(body.contains("\"tools\""));
				response = """
					{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_1","type":"function","function":{"name":"server_health","arguments":"{}"}}]}}]}
					""";
			} else {
				assertTrue(body.contains("\"role\":\"tool\""));
				assertTrue(body.contains("서버 헬스체크 완료"));
				response = """
					{"choices":[{"message":{"role":"assistant","content":"도구 결과 확인: 서버가 UP입니다."}}]}
					""";
			}
			byte[] bytes = response.getBytes(StandardCharsets.UTF_8);
			exchange.getResponseHeaders().add("Content-Type", "application/json; charset=utf-8");
			exchange.sendResponseHeaders(200, bytes.length);
			exchange.getResponseBody().write(bytes);
			exchange.close();
		});
		server.start();
		try {
			AvaAiLlmClient client = new AvaAiLlmClient(
				new ObjectMapper(),
				"http://127.0.0.1:" + server.getAddress().getPort() + "/v1",
				"test-model",
				256,
				0.0,
				10,
				0
			);
			String answer = client.completeWithTools(
				List.of(new AvaAiLlmClient.PromptMessage("user", "서버 상태 확인해줘")),
				List.of(new AvaAiLlmClient.ToolDefinition(
					"server_health",
					"Check server health",
					Map.of("type", "object", "properties", Map.of())
				)),
				call -> {
					assertEquals("server_health", call.name());
					return new AvaAiLlmClient.ToolResult(true, "서버 헬스체크 완료: UP");
				},
				2
			);

			assertEquals("도구 결과 확인: 서버가 UP입니다.", answer);
			assertEquals(2, requests.get());
		} finally {
			server.stop(0);
		}
	}
}
