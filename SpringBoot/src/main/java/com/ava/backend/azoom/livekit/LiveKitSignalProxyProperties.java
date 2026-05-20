package com.ava.backend.azoom.livekit;

import java.net.URI;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class LiveKitSignalProxyProperties {

	private final boolean enabled;
	private final URI upstreamWebSocketBase;

	public LiveKitSignalProxyProperties(
		@Value("${ava.azoom.livekit.signal-proxy.enabled:true}") boolean enabled,
		@Value("${ava.azoom.livekit.signal-proxy.upstream-url:}") String upstreamUrl,
		@Value("${ava.azoom.livekit.signal-port:${AVA_LIVEKIT_SIGNAL_PORT:7880}}") int signalPort
	) {
		this.enabled = enabled;
		String normalized = upstreamUrl == null ? "" : upstreamUrl.trim();
		if (normalized.isBlank()) {
			normalized = "ws://127.0.0.1:" + signalPort;
		}
		this.upstreamWebSocketBase = normalizeWebSocketBase(normalized);
	}

	public boolean enabled() {
		return enabled;
	}

	public URI upstreamWebSocketUri(URI downstreamUri) {
		String query = downstreamUri == null ? null : downstreamUri.getRawQuery();
		return appendPathAndQuery(upstreamWebSocketBase, "/rtc", query);
	}

	public URI upstreamValidateUri(URI downstreamUri) {
		String query = downstreamUri == null ? null : downstreamUri.getRawQuery();
		String scheme = upstreamWebSocketBase.getScheme().equalsIgnoreCase("wss") ? "https" : "http";
		URI httpBase = URI.create(upstreamWebSocketBase.toString().replaceFirst("^wss?", scheme));
		return appendPathAndQuery(httpBase, "/rtc/validate", query);
	}

	private static URI normalizeWebSocketBase(String value) {
		URI uri = URI.create(value);
		String scheme = uri.getScheme();
		if (scheme == null || (!scheme.equalsIgnoreCase("ws") && !scheme.equalsIgnoreCase("wss"))) {
			throw new IllegalArgumentException("LiveKit signal proxy upstream must use ws or wss.");
		}
		return uri;
	}

	private static URI appendPathAndQuery(URI base, String path, String query) {
		try {
			String basePath = base.getRawPath();
			if (basePath == null || basePath.isBlank() || basePath.equals("/")) {
				basePath = "";
			}
			String normalizedPath = basePath.endsWith("/")
				? basePath.substring(0, basePath.length() - 1) + path
				: basePath + path;
			return new URI(
				base.getScheme(),
				base.getRawUserInfo(),
				base.getHost(),
				base.getPort(),
				normalizedPath,
				query,
				null
			);
		} catch (Exception exception) {
			throw new IllegalArgumentException("Failed to build LiveKit upstream URI.", exception);
		}
	}
}
