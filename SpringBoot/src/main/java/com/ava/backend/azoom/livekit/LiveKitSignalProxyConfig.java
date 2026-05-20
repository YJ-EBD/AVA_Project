package com.ava.backend.azoom.livekit;

import java.util.Arrays;
import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

@Configuration
@EnableWebSocket
@ConditionalOnProperty(
	prefix = "ava.azoom.livekit.signal-proxy",
	name = "enabled",
	havingValue = "true",
	matchIfMissing = true
)
public class LiveKitSignalProxyConfig implements WebSocketConfigurer {

	private final LiveKitSignalProxyHandler handler;
	private final List<String> allowedOrigins;

	public LiveKitSignalProxyConfig(
		LiveKitSignalProxyHandler handler,
		@Value("${ava.web.allowed-origins:*}") String allowedOrigins
	) {
		this.handler = handler;
		this.allowedOrigins = parseAllowedOrigins(allowedOrigins);
	}

	@Override
	public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
		registry.addHandler(handler, "/rtc")
			.setAllowedOriginPatterns(allowedOrigins.toArray(String[]::new));
	}

	private static List<String> parseAllowedOrigins(String value) {
		List<String> origins = Arrays.stream(value.split(","))
			.map(String::trim)
			.filter(origin -> !origin.isBlank())
			.toList();
		return origins.isEmpty() ? List.of("*") : origins;
	}
}
