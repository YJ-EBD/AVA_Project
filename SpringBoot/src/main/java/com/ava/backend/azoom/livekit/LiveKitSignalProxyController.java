package com.ava.backend.azoom.livekit;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import jakarta.servlet.http.HttpServletRequest;

@RestController
@ConditionalOnProperty(
	prefix = "ava.azoom.livekit.signal-proxy",
	name = "enabled",
	havingValue = "true",
	matchIfMissing = true
)
public class LiveKitSignalProxyController {

	private static final Duration VALIDATE_TIMEOUT = Duration.ofSeconds(10);

	private final LiveKitSignalProxyProperties properties;
	private final HttpClient httpClient;

	public LiveKitSignalProxyController(LiveKitSignalProxyProperties properties) {
		this.properties = properties;
		this.httpClient = HttpClient.newBuilder()
			.connectTimeout(VALIDATE_TIMEOUT)
			.build();
	}

	@GetMapping("/rtc/validate")
	public ResponseEntity<String> validate(HttpServletRequest servletRequest) throws Exception {
		URI downstreamUri = servletRequest.getRequestURI() == null
			? null
			: URI.create(servletRequest.getRequestURI() + query(servletRequest));
		HttpRequest.Builder builder = HttpRequest.newBuilder(properties.upstreamValidateUri(downstreamUri))
			.timeout(VALIDATE_TIMEOUT)
			.GET();
		String authorization = servletRequest.getHeader(HttpHeaders.AUTHORIZATION);
		if (authorization != null && !authorization.isBlank()) {
			builder.header(HttpHeaders.AUTHORIZATION, authorization);
		}
		HttpResponse<String> response = httpClient.send(
			builder.build(),
			HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8)
		);
		return ResponseEntity.status(response.statusCode()).body(response.body());
	}

	private static String query(HttpServletRequest request) {
		String query = request.getQueryString();
		return query == null || query.isBlank() ? "" : "?" + query;
	}
}
