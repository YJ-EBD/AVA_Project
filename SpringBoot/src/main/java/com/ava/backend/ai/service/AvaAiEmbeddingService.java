package com.ava.backend.ai.service;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

@Service
public class AvaAiEmbeddingService {

	private static final int MAX_EMBEDDING_TEXT_CHARS = 6_000;

	private final ObjectMapper objectMapper;
	private final HttpClient httpClient;
	private final URI embeddingsUri;
	private final String remoteModel;
	private final int dimensions;
	private final boolean remoteEnabled;
	private final Duration timeout;

	public AvaAiEmbeddingService(
		ObjectMapper objectMapper,
		@Value("${ava.ai.llm-base-url:http://127.0.0.1:8088/v1}") String llmBaseUrl,
		@Value("${ava.ai.embedding-model:}") String embeddingModel,
		@Value("${ava.ai.embedding-dimensions:384}") int dimensions,
		@Value("${ava.ai.embedding-remote-enabled:true}") boolean remoteEnabled,
		@Value("${ava.ai.embedding-timeout-seconds:30}") long timeoutSeconds
	) {
		this.objectMapper = objectMapper;
		this.httpClient = HttpClient.newBuilder()
			.connectTimeout(Duration.ofSeconds(Math.min(timeoutSeconds, 10)))
			.build();
		this.embeddingsUri = URI.create(normalizeBaseUrl(llmBaseUrl) + "/embeddings");
		this.remoteModel = embeddingModel == null ? "" : embeddingModel.strip();
		this.dimensions = Math.max(64, dimensions);
		this.remoteEnabled = remoteEnabled;
		this.timeout = Duration.ofSeconds(Math.max(5, timeoutSeconds));
	}

	public String modelKey() {
		return remoteAvailable() ? remoteModel : "local-hash-v1-" + dimensions;
	}

	public float[] embed(String value) {
		String text = value == null ? "" : value.strip();
		if (text.length() > MAX_EMBEDDING_TEXT_CHARS) {
			text = text.substring(0, MAX_EMBEDDING_TEXT_CHARS);
		}
		if (remoteAvailable()) {
			try {
				float[] remote = remoteEmbedding(text);
				if (remote.length > 0) {
					return normalize(remote);
				}
			} catch (RuntimeException ignored) {
				// Fall back to deterministic local vectors when the local LLM server lacks /embeddings.
			}
		}
		return hashEmbedding(text);
	}

	public String encode(float[] vector) {
		if (vector == null || vector.length == 0) {
			return "";
		}
		byte[] bytes = new byte[vector.length * 4];
		for (int index = 0; index < vector.length; index++) {
			int bits = Float.floatToIntBits(vector[index]);
			int offset = index * 4;
			bytes[offset] = (byte) (bits >>> 24);
			bytes[offset + 1] = (byte) (bits >>> 16);
			bytes[offset + 2] = (byte) (bits >>> 8);
			bytes[offset + 3] = (byte) bits;
		}
		return Base64.getEncoder().encodeToString(bytes);
	}

	public float[] decode(String encoded) {
		if (encoded == null || encoded.isBlank()) {
			return new float[0];
		}
		byte[] bytes = Base64.getDecoder().decode(encoded);
		if (bytes.length % 4 != 0) {
			return new float[0];
		}
		float[] vector = new float[bytes.length / 4];
		for (int index = 0; index < vector.length; index++) {
			int offset = index * 4;
			int bits = ((bytes[offset] & 0xff) << 24)
				| ((bytes[offset + 1] & 0xff) << 16)
				| ((bytes[offset + 2] & 0xff) << 8)
				| (bytes[offset + 3] & 0xff);
			vector[index] = Float.intBitsToFloat(bits);
		}
		return vector;
	}

	public double cosine(float[] left, float[] right) {
		if (left == null || right == null || left.length == 0 || right.length == 0) {
			return 0;
		}
		int size = Math.min(left.length, right.length);
		double dot = 0;
		double leftNorm = 0;
		double rightNorm = 0;
		for (int index = 0; index < size; index++) {
			dot += left[index] * right[index];
			leftNorm += left[index] * left[index];
			rightNorm += right[index] * right[index];
		}
		if (leftNorm == 0 || rightNorm == 0) {
			return 0;
		}
		return dot / (Math.sqrt(leftNorm) * Math.sqrt(rightNorm));
	}

	private boolean remoteAvailable() {
		return remoteEnabled && !remoteModel.isBlank();
	}

	private float[] remoteEmbedding(String text) {
		try {
			Map<String, Object> payload = Map.of(
				"model", remoteModel,
				"input", text
			);
			HttpRequest request = HttpRequest.newBuilder(embeddingsUri)
				.timeout(timeout)
				.header("Content-Type", "application/json; charset=utf-8")
				.POST(HttpRequest.BodyPublishers.ofString(objectMapper.writeValueAsString(payload)))
				.build();
			HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
			if (response.statusCode() < 200 || response.statusCode() >= 300) {
				throw new IllegalStateException("Embedding server returned " + response.statusCode());
			}
			JsonNode embedding = objectMapper.readTree(response.body()).path("data").path(0).path("embedding");
			if (!embedding.isArray()) {
				return new float[0];
			}
			List<Float> values = new ArrayList<>();
			for (JsonNode value : embedding) {
				values.add((float) value.asDouble());
			}
			float[] vector = new float[values.size()];
			for (int index = 0; index < values.size(); index++) {
				vector[index] = values.get(index);
			}
			return vector;
		} catch (IOException exception) {
			throw new IllegalStateException("Embedding request failed.", exception);
		} catch (InterruptedException exception) {
			Thread.currentThread().interrupt();
			throw new IllegalStateException("Embedding request was interrupted.", exception);
		}
	}

	private float[] hashEmbedding(String text) {
		float[] vector = new float[dimensions];
		String normalized = text == null ? "" : text.toLowerCase(Locale.ROOT);
		for (String token : tokens(normalized)) {
			addToken(vector, token, 1.0f);
		}
		for (int index = 0; index + 2 < normalized.length(); index++) {
			String gram = normalized.substring(index, index + 3);
			if (!gram.isBlank()) {
				addToken(vector, gram, 0.35f);
			}
		}
		return normalize(vector);
	}

	private List<String> tokens(String text) {
		String[] parts = text.split("[^\\p{IsAlphabetic}\\p{IsDigit}]+");
		List<String> tokens = new ArrayList<>();
		for (String part : parts) {
			if (part.length() >= 2) {
				tokens.add(part);
			}
		}
		return tokens;
	}

	private void addToken(float[] vector, String token, float weight) {
		int hash = token.hashCode();
		int index = Math.floorMod(hash, vector.length);
		vector[index] += (hash & 1) == 0 ? weight : -weight;
	}

	private float[] normalize(float[] vector) {
		double norm = 0;
		for (float value : vector) {
			norm += value * value;
		}
		if (norm == 0) {
			return vector;
		}
		double scale = 1.0 / Math.sqrt(norm);
		for (int index = 0; index < vector.length; index++) {
			vector[index] = (float) (vector[index] * scale);
		}
		return vector;
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
}
