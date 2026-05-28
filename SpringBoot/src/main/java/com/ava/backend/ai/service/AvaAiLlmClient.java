package com.ava.backend.ai.service;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

@Component
public class AvaAiLlmClient {

	private final ObjectMapper objectMapper;
	private final HttpClient httpClient;
	private final URI chatCompletionsUri;
	private final String model;
	private final int maxTokens;
	private final double temperature;
	private final Duration timeout;
	private final Duration unavailableRetryWindow;
	private final Duration unavailableRetryDelay = Duration.ofSeconds(3);

	public AvaAiLlmClient(
		ObjectMapper objectMapper,
		@Value("${ava.ai.llm-base-url:http://127.0.0.1:8088/v1}") String llmBaseUrl,
		@Value("${ava.ai.model:ava-qwen3.5-27b-q4km}") String model,
		@Value("${ava.ai.max-tokens:1024}") int maxTokens,
		@Value("${ava.ai.temperature:0.2}") double temperature,
		@Value("${ava.ai.timeout-seconds:180}") long timeoutSeconds,
		@Value("${ava.ai.unavailable-retry-seconds:90}") long unavailableRetrySeconds
	) {
		this.objectMapper = objectMapper;
		this.httpClient = HttpClient.newBuilder()
			.connectTimeout(Duration.ofSeconds(Math.min(timeoutSeconds, 30)))
			.build();
		this.chatCompletionsUri = URI.create(normalizeBaseUrl(llmBaseUrl) + "/chat/completions");
		this.model = model;
		this.maxTokens = maxTokens;
		this.temperature = temperature;
		this.timeout = Duration.ofSeconds(timeoutSeconds);
		this.unavailableRetryWindow = Duration.ofSeconds(Math.max(0, unavailableRetrySeconds));
	}

	public String model() {
		return model;
	}

	public String complete(List<PromptMessage> messages) {
		try {
			Map<String, Object> payload = Map.of(
				"model", model,
				"messages", messages.stream()
					.map(message -> Map.of("role", message.role(), "content", message.content()))
					.toList(),
				"temperature", temperature,
				"max_tokens", maxTokens,
				"stream", false
			);
			JsonNode message = sendChatPayload(payload).path("choices").path(0).path("message");
			String content = message.path("content").asText("");
			if (content.isBlank()) {
				throw new IllegalStateException("LLM server returned an empty answer.");
			}
			return stripThinkingBlock(content.strip());
		} catch (IOException exception) {
			throw new IllegalStateException("LLM server request failed.", exception);
		}
	}

	public String completeWithTools(
		List<PromptMessage> messages,
		List<ToolDefinition> tools,
		ToolExecutor executor,
		int maxToolRounds
	) {
		if (tools == null || tools.isEmpty() || executor == null) {
			return complete(messages);
		}
		try {
			List<Map<String, Object>> wireMessages = new ArrayList<>(messages.stream()
				.map(message -> {
					Map<String, Object> wire = new LinkedHashMap<>();
					wire.put("role", message.role());
					wire.put("content", message.content());
					return wire;
				})
				.toList());
			int rounds = Math.max(1, maxToolRounds);
			for (int round = 0; round <= rounds; round++) {
				Map<String, Object> payload = new LinkedHashMap<>();
				payload.put("model", model);
				payload.put("messages", wireMessages);
				payload.put("temperature", temperature);
				payload.put("max_tokens", maxTokens);
				payload.put("stream", false);
				payload.put("tools", tools.stream().map(this::wireTool).toList());
				payload.put("tool_choice", "auto");

				JsonNode message = sendChatPayload(payload).path("choices").path(0).path("message");
				JsonNode toolCalls = message.path("tool_calls");
				if (!toolCalls.isArray() || toolCalls.isEmpty()) {
					String content = message.path("content").asText("");
					if (content.isBlank()) {
						throw new IllegalStateException("LLM server returned an empty answer.");
					}
					return stripThinkingBlock(content.strip());
				}
				if (round == rounds) {
					throw new IllegalStateException("LLM tool-calling exceeded max rounds.");
				}
				Map<String, Object> assistant = new LinkedHashMap<>();
				assistant.put("role", "assistant");
				String content = message.path("content").asText("");
				assistant.put("content", content.isBlank() ? null : content);
				assistant.put("tool_calls", objectMapper.convertValue(toolCalls, Object.class));
				wireMessages.add(assistant);
				for (JsonNode callNode : toolCalls) {
					ToolCall call = toolCall(callNode);
					ToolResult result = executor.execute(call);
					Map<String, Object> toolMessage = new LinkedHashMap<>();
					toolMessage.put("role", "tool");
					toolMessage.put("tool_call_id", call.id());
					toolMessage.put("name", call.name());
					toolMessage.put("content", result == null ? "" : result.content());
					wireMessages.add(toolMessage);
				}
			}
			throw new IllegalStateException("LLM tool-calling did not produce a final answer.");
		} catch (IOException exception) {
			throw new IllegalStateException("LLM server request failed.", exception);
		}
	}

	private JsonNode sendChatPayload(Map<String, Object> payload) throws IOException {
		long retryUntil = System.nanoTime() + unavailableRetryWindow.toNanos();
		String body = objectMapper.writeValueAsString(payload);
		HttpRequest request = HttpRequest.newBuilder(chatCompletionsUri)
			.timeout(timeout)
			.header("Content-Type", "application/json; charset=utf-8")
			.POST(HttpRequest.BodyPublishers.ofString(body))
			.build();
		while (true) {
			try {
				HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
				if (response.statusCode() < 200 || response.statusCode() >= 300) {
					if (isTemporarilyUnavailable(response.statusCode(), response.body()) && pauseBeforeRetry(retryUntil)) {
						continue;
					}
					if (isToolCallingUnsupported(response.statusCode(), response.body())) {
						throw new ToolCallingUnsupportedException("LLM server does not support native tool calling: " + response.body());
					}
					throw new IllegalStateException("LLM server returned " + response.statusCode() + ": " + response.body());
				}
				return objectMapper.readTree(response.body());
			} catch (IOException exception) {
				try {
					if (pauseBeforeRetry(retryUntil)) {
						continue;
					}
				} catch (InterruptedException interrupted) {
					Thread.currentThread().interrupt();
					throw new IllegalStateException("LLM server request was interrupted.", interrupted);
				}
				throw exception;
			} catch (InterruptedException exception) {
				Thread.currentThread().interrupt();
				throw new IllegalStateException("LLM server request was interrupted.", exception);
			}
		}
	}

	private Map<String, Object> wireTool(ToolDefinition tool) {
		Map<String, Object> function = new LinkedHashMap<>();
		function.put("name", tool.name());
		function.put("description", tool.description());
		function.put("parameters", tool.parameters() == null ? Map.of("type", "object") : tool.parameters());
		return Map.of("type", "function", "function", function);
	}

	private ToolCall toolCall(JsonNode callNode) {
		JsonNode function = callNode.path("function");
		return new ToolCall(
			callNode.path("id").asText("tool-call-" + System.nanoTime()),
			function.path("name").asText(""),
			function.path("arguments").asText("{}")
		);
	}

	private boolean isTemporarilyUnavailable(int statusCode, String body) {
		if (statusCode == 503) {
			return true;
		}
		String normalized = body == null ? "" : body.toLowerCase(Locale.ROOT);
		return normalized.contains("loading model") || normalized.contains("unavailable");
	}

	private boolean isToolCallingUnsupported(int statusCode, String body) {
		if (statusCode != 400 && statusCode != 404 && statusCode != 422) {
			return false;
		}
		String normalized = body == null ? "" : body.toLowerCase(Locale.ROOT);
		return normalized.contains("tool")
			|| normalized.contains("function")
			|| normalized.contains("tool_choice")
			|| normalized.contains("tool_calls");
	}

	private boolean pauseBeforeRetry(long retryUntilNanos) throws InterruptedException {
		long remainingNanos = retryUntilNanos - System.nanoTime();
		if (remainingNanos <= 0) {
			return false;
		}
		long sleepMillis = Math.min(unavailableRetryDelay.toMillis(), Duration.ofNanos(remainingNanos).toMillis());
		Thread.sleep(Math.max(100, sleepMillis));
		return true;
	}

	private String stripThinkingBlock(String content) {
		String trimmed = content.strip();
		if (!trimmed.startsWith("<think>")) {
			return trimmed;
		}
		int end = trimmed.indexOf("</think>");
		if (end < 0) {
			return trimmed;
		}
		return trimmed.substring(end + "</think>".length()).strip();
	}

	private static String normalizeBaseUrl(String value) {
		String normalized = value == null || value.isBlank()
			? "http://127.0.0.1:8088/v1"
			: value.strip();
		while (normalized.endsWith("/")) {
			normalized = normalized.substring(0, normalized.length() - 1);
		}
		return normalized;
	}

	public record PromptMessage(String role, String content) {
	}

	public record ToolDefinition(String name, String description, Map<String, Object> parameters) {
	}

	public record ToolCall(String id, String name, String argumentsJson) {
	}

	public record ToolResult(boolean success, String content) {
	}

	@FunctionalInterface
	public interface ToolExecutor {
		ToolResult execute(ToolCall call);
	}

	public static class ToolCallingUnsupportedException extends RuntimeException {
		public ToolCallingUnsupportedException(String message) {
			super(message);
		}
	}
}
