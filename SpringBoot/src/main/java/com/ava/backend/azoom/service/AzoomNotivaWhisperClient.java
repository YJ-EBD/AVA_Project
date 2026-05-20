package com.ava.backend.azoom.service;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Path;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.fasterxml.jackson.databind.ObjectMapper;

@Component
public class AzoomNotivaWhisperClient {

	private final String baseUrl;
	private final ObjectMapper objectMapper;
	private final HttpClient httpClient;

	public AzoomNotivaWhisperClient(
		@Value("${ava.azoom.notiva.base-url:http://127.0.0.1:8091}") String baseUrl,
		ObjectMapper objectMapper
	) {
		this.baseUrl = trimTrailingSlash(baseUrl);
		this.objectMapper = objectMapper;
		this.httpClient = HttpClient.newBuilder()
			.connectTimeout(Duration.ofSeconds(15))
			.build();
	}

	public NotivaWhisperResponse transcribe(Path audioFile, String language, NotivaWhisperMode mode) throws IOException {
		if (!java.nio.file.Files.isRegularFile(audioFile)) {
			throw new IOException("Notiva AI audio file does not exist: " + audioFile);
		}
		byte[] audioBytes = java.nio.file.Files.readAllBytes(audioFile);
		if (audioBytes.length == 0) {
			throw new IOException("Notiva AI audio file is empty: " + audioFile);
		}
		NotivaWhisperMode resolvedMode = mode == null ? NotivaWhisperMode.BATCH : mode;
		HttpRequest request = HttpRequest.newBuilder(transcribeRawUri(language, resolvedMode))
			.version(HttpClient.Version.HTTP_1_1)
			.timeout(Duration.ofMinutes(10))
			.header("Content-Type", "application/octet-stream")
			.header("X-Notiva-Filename", audioFile.getFileName().toString())
			.header("X-Notiva-Mode", resolvedMode.apiValue())
			.POST(HttpRequest.BodyPublishers.ofByteArray(audioBytes))
			.build();
		HttpResponse<String> response;
		try {
			response = httpClient.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
		} catch (InterruptedException error) {
			Thread.currentThread().interrupt();
			throw new IOException("Notiva AI transcription request was interrupted.", error);
		}
		if (response.statusCode() < 200 || response.statusCode() >= 300) {
			throw new IOException("Notiva AI transcription failed with HTTP " + response.statusCode() + ": " + response.body());
		}
		if (response.body() == null || response.body().isBlank()) {
			return new NotivaWhisperResponse("", List.of(), "", 0.0);
		}
		return objectMapper.readValue(response.body(), NotivaWhisperResponse.class);
	}

	private URI transcribeRawUri(String language, NotivaWhisperMode mode) {
		String resolvedLanguage = language == null || language.isBlank() ? "ko" : language.trim();
		String encodedLanguage = URLEncoder.encode(resolvedLanguage, StandardCharsets.UTF_8);
		return URI.create(baseUrl + "/v1/notiva/transcribe-raw?language=" + encodedLanguage + "&mode=" + mode.apiValue());
	}

	private String trimTrailingSlash(String value) {
		String trimmed = value == null || value.isBlank() ? "http://127.0.0.1:8091" : value.trim();
		while (trimmed.endsWith("/")) {
			trimmed = trimmed.substring(0, trimmed.length() - 1);
		}
		return trimmed;
	}

	public record NotivaWhisperResponse(
		String text,
		List<NotivaWhisperSegment> segments,
		String language,
		double duration
	) {
		public List<NotivaWhisperSegment> segments() {
			return segments == null ? List.of() : segments;
		}
	}

	public record NotivaWhisperSegment(
		double start,
		double end,
		String text
	) {
	}

	public enum NotivaWhisperMode {
		REALTIME("realtime"),
		BATCH("batch");

		private final String apiValue;

		NotivaWhisperMode(String apiValue) {
			this.apiValue = apiValue;
		}

		public String apiValue() {
			return apiValue;
		}
	}
}
