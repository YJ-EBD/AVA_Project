package com.ava.backend.config;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

@Component
public class ProductionReadinessValidator implements ApplicationRunner {

	private static final String DEFAULT_JWT_SECRET = "ava-local-development-secret-change-me-please-2026";

	private final Environment environment;
	private final String runtimeEnvironment;
	private final boolean failFast;
	private final String jwtSecret;
	private final String allowedOrigins;
	private final String postgresUrl;
	private final String postgresPassword;
	private final String ddlAuto;
	private final String updateDirectory;
	private final String windowsUpdateFileName;
	private final String androidUpdateFileName;
	private final String macosUpdateFileName;
	private final String iosUpdateFileName;
	private final boolean requireLiveKit;
	private final String liveKitUrl;
	private final String liveKitApiKey;
	private final String liveKitApiSecret;

	public ProductionReadinessValidator(
		Environment environment,
		@Value("${ava.runtime.environment:local}") String runtimeEnvironment,
		@Value("${ava.runtime.production-fail-fast:true}") boolean failFast,
		@Value("${ava.auth.jwt-secret}") String jwtSecret,
		@Value("${ava.web.allowed-origins:*}") String allowedOrigins,
		@Value("${spring.datasource.url}") String postgresUrl,
		@Value("${spring.datasource.password}") String postgresPassword,
		@Value("${spring.jpa.hibernate.ddl-auto:}") String ddlAuto,
		@Value("${ava.app-update.directory:AppUpdates}") String updateDirectory,
		@Value("${ava.app-update.windows.file-name:}") String windowsUpdateFileName,
		@Value("${ava.app-update.android.file-name:}") String androidUpdateFileName,
		@Value("${ava.app-update.macos.file-name:}") String macosUpdateFileName,
		@Value("${ava.app-update.ios.file-name:}") String iosUpdateFileName,
		@Value("${ava.azoom.require-livekit-in-production:false}") boolean requireLiveKit,
		@Value("${ava.azoom.livekit.url:}") String liveKitUrl,
		@Value("${ava.azoom.livekit.api-key:}") String liveKitApiKey,
		@Value("${ava.azoom.livekit.api-secret:}") String liveKitApiSecret
	) {
		this.environment = environment;
		this.runtimeEnvironment = runtimeEnvironment;
		this.failFast = failFast;
		this.jwtSecret = jwtSecret;
		this.allowedOrigins = allowedOrigins;
		this.postgresUrl = postgresUrl;
		this.postgresPassword = postgresPassword;
		this.ddlAuto = ddlAuto;
		this.updateDirectory = updateDirectory;
		this.windowsUpdateFileName = windowsUpdateFileName;
		this.androidUpdateFileName = androidUpdateFileName;
		this.macosUpdateFileName = macosUpdateFileName;
		this.iosUpdateFileName = iosUpdateFileName;
		this.requireLiveKit = requireLiveKit;
		this.liveKitUrl = liveKitUrl;
		this.liveKitApiKey = liveKitApiKey;
		this.liveKitApiSecret = liveKitApiSecret;
	}

	@Override
	public void run(ApplicationArguments args) {
		if (!isProductionLike()) {
			return;
		}
		List<String> problems = validate();
		if (!problems.isEmpty() && failFast) {
			throw new IllegalStateException("AVA production readiness failed: " + String.join("; ", problems));
		}
	}

	public List<String> validate() {
		List<String> problems = new ArrayList<>();
		if (isBlank(jwtSecret) || DEFAULT_JWT_SECRET.equals(jwtSecret) || jwtSecret.length() < 48) {
			problems.add("AVA_JWT_SECRET must be changed and at least 48 characters.");
		}
		if (isBlank(allowedOrigins) || "*".equals(allowedOrigins.trim())) {
			problems.add("AVA_ALLOWED_ORIGINS must not be wildcard in production.");
		}
		if (postgresUrl.contains("localhost") || postgresUrl.contains("127.0.0.1")) {
			problems.add("AVA_POSTGRES_URL should point to the production database endpoint.");
		}
		if ("ava_password".equals(postgresPassword)) {
			problems.add("AVA_POSTGRES_PASSWORD must be changed.");
		}
		String normalizedDdlAuto = ddlAuto == null ? "" : ddlAuto.trim().toLowerCase();
		if ("update".equals(normalizedDdlAuto)
			|| "create".equals(normalizedDdlAuto)
			|| "create-drop".equals(normalizedDdlAuto)) {
			problems.add("spring.jpa.hibernate.ddl-auto must be validate or none in production.");
		}
		if (!isBlank(windowsUpdateFileName) && !Files.exists(Path.of(updateDirectory, windowsUpdateFileName))) {
			problems.add("Windows update package is missing: " + windowsUpdateFileName);
		}
		if (!isBlank(androidUpdateFileName) && !Files.exists(Path.of(updateDirectory, androidUpdateFileName))) {
			problems.add("Android update package is missing: " + androidUpdateFileName);
		}
		if (!isBlank(macosUpdateFileName) && !Files.exists(Path.of(updateDirectory, macosUpdateFileName))) {
			problems.add("macOS update package is missing: " + macosUpdateFileName);
		}
		if (!isBlank(iosUpdateFileName) && !Files.exists(Path.of(updateDirectory, iosUpdateFileName))) {
			problems.add("iOS update package is missing: " + iosUpdateFileName);
		}
		if (requireLiveKit && (isBlank(liveKitUrl) || isBlank(liveKitApiKey) || isBlank(liveKitApiSecret))) {
			problems.add("LiveKit URL/API key/API secret are required for production AZOOM media.");
		}
		return problems;
	}

	public boolean isProductionLikeEnvironment() {
		if ("production".equalsIgnoreCase(runtimeEnvironment) || "prod".equalsIgnoreCase(runtimeEnvironment)) {
			return true;
		}
		return Arrays.stream(environment.getActiveProfiles())
			.anyMatch(profile -> "prod".equalsIgnoreCase(profile) || "production".equalsIgnoreCase(profile));
	}

	private boolean isProductionLike() {
		return isProductionLikeEnvironment();
	}

	private boolean isBlank(String value) {
		return value == null || value.isBlank();
	}
}
