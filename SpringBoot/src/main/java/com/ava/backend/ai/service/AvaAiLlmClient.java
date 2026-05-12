package com.ava.backend.ai.service;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.List;
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

	public AvaAiLlmClient(
		ObjectMapper objectMapper,
		@Value("${ava.ai.llm-base-url:http://127.0.0.1:8088/v1}") String llmBaseUrl,
		@Value("${ava.ai.model:ava-qwen3.5-27b-q4km}") String model,
		@Value("${ava.ai.max-tokens:1024}") int maxTokens,
		@Value("${ava.ai.temperature:0.2}") double temperature,
		@Value("${ava.ai.timeout-seconds:180}") long timeoutSeconds
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
			HttpRequest request = HttpRequest.newBuilder(chatCompletionsUri)
				.timeout(timeout)
				.header("Content-Type", "application/json; charset=utf-8")
				.POST(HttpRequest.BodyPublishers.ofString(objectMapper.writeValueAsString(payload)))
				.build();

			HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
			if (response.statusCode() < 200 || response.statusCode() >= 300) {
				throw new IllegalStateException("LLM server returned " + response.statusCode() + ": " + response.body());
			}
			JsonNode root = objectMapper.readTree(response.body());
			String content = root.path("choices").path(0).path("message").path("content").asText("");
			if (content.isBlank()) {
				throw new IllegalStateException("LLM server returned an empty answer.");
			}
			return stripThinkingBlock(content.strip());
		} catch (IOException exception) {
			throw new IllegalStateException("LLM server request failed.", exception);
		} catch (InterruptedException exception) {
			Thread.currentThread().interrupt();
			throw new IllegalStateException("LLM server request was interrupted.", exception);
		}
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
}
