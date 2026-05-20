package com.ava.backend.ai.service;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.time.Duration;
import java.util.Locale;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

@Component
public class AvaAiLocalLlmServerManager implements ApplicationRunner {

	private static final Logger log = LoggerFactory.getLogger(AvaAiLocalLlmServerManager.class);

	private final boolean autoStart;
	private final URI llmBaseUri;
	private final Path scriptPath;

	public AvaAiLocalLlmServerManager(
		@Value("${ava.ai.local-server.auto-start:true}") boolean autoStart,
		@Value("${ava.ai.llm-base-url:http://127.0.0.1:8088/v1}") String llmBaseUrl,
		@Value("${ava.ai.local-server.script-path:../LLM_Server/start_server.ps1}") String scriptPath
	) {
		this.autoStart = autoStart;
		this.llmBaseUri = URI.create(normalizeBaseUrl(llmBaseUrl));
		this.scriptPath = resolveScriptPath(scriptPath);
	}

	@Override
	public void run(ApplicationArguments args) {
		if (!autoStart || !isLocalHost(llmBaseUri.getHost())) {
			return;
		}
		if (isReachable()) {
			log.info("AVA AI local LLM server is already listening at {}.", llmBaseUri);
			return;
		}
		if (!Files.isRegularFile(scriptPath)) {
			log.warn("AVA AI local LLM auto-start skipped. Script not found: {}", scriptPath);
			return;
		}

		Thread starter = new Thread(this::startLocalServer, "ava-ai-llm-starter");
		starter.setDaemon(true);
		starter.start();
	}

	private void startLocalServer() {
		try {
			Path serverDirectory = scriptPath.getParent();
			Path stdout = serverDirectory.resolve("llm-server-autostart-stdout.log");
			Path stderr = serverDirectory.resolve("llm-server-autostart-stderr.log");
			ProcessBuilder builder = new ProcessBuilder(
				"powershell.exe",
				"-NoProfile",
				"-ExecutionPolicy",
				"Bypass",
				"-File",
				scriptPath.toString()
			);
			builder.directory(serverDirectory.toFile());
			builder.redirectOutput(stdout.toFile());
			builder.redirectError(stderr.toFile());
			builder.start();
			log.info("Started AVA AI local LLM server via {}.", scriptPath);
		} catch (IOException exception) {
			log.warn("Failed to start AVA AI local LLM server.", exception);
		}
	}

	private boolean isReachable() {
		int port = llmBaseUri.getPort() > 0 ? llmBaseUri.getPort() : defaultPort(llmBaseUri.getScheme());
		try (Socket socket = new Socket()) {
			socket.connect(new InetSocketAddress(llmBaseUri.getHost(), port), (int) Duration.ofMillis(700).toMillis());
			return true;
		} catch (IOException exception) {
			return false;
		}
	}

	private boolean isLocalHost(String host) {
		if (host == null || host.isBlank()) {
			return false;
		}
		String normalized = host.toLowerCase(Locale.ROOT);
		return normalized.equals("localhost") || normalized.equals("127.0.0.1") || normalized.equals("::1");
	}

	private int defaultPort(String scheme) {
		return "https".equalsIgnoreCase(scheme) ? 443 : 80;
	}

	private String normalizeBaseUrl(String value) {
		String normalized = value == null || value.isBlank()
			? "http://127.0.0.1:8088/v1"
			: value.strip();
		while (normalized.endsWith("/")) {
			normalized = normalized.substring(0, normalized.length() - 1);
		}
		return normalized;
	}

	private Path resolveScriptPath(String value) {
		String configured = value == null || value.isBlank()
			? "../LLM_Server/start_server.ps1"
			: value.strip();
		Path configuredPath = Path.of(configured);
		if (configuredPath.isAbsolute()) {
			return configuredPath.normalize();
		}

		Path workingDirectory = Path.of("").toAbsolutePath().normalize();
		List<Path> candidates = new ArrayList<>();
		candidates.add(workingDirectory.resolve(configuredPath));
		if (workingDirectory.getParent() != null) {
			candidates.add(workingDirectory.getParent().resolve(configuredPath));
		}
		candidates.add(workingDirectory.resolve("LLM_Server").resolve("start_server.ps1"));
		if (workingDirectory.getParent() != null) {
			candidates.add(workingDirectory.getParent().resolve("LLM_Server").resolve("start_server.ps1"));
		}

		return candidates.stream()
			.map(Path::normalize)
			.filter(Files::isRegularFile)
			.findFirst()
			.orElseGet(() -> workingDirectory.resolve(configuredPath).normalize());
	}
}
