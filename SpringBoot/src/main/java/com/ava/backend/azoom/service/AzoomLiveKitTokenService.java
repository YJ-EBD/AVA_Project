package com.ava.backend.azoom.service;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.Base64;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.azoom.dto.AzoomLiveKitTokenResponse;
import com.ava.backend.user.dto.UserProfileResponse;
import com.fasterxml.jackson.databind.ObjectMapper;

@Service
public class AzoomLiveKitTokenService {

	private static final String HMAC_ALGORITHM = "HmacSHA256";
	private static final int MAX_METADATA_AVATAR_URL_LENGTH = 512;
	private static final Base64.Encoder BASE64_URL_ENCODER = Base64.getUrlEncoder().withoutPadding();

	private final ObjectMapper objectMapper;
	private final String liveKitUrl;
	private final String apiKey;
	private final String apiSecret;
	private final long tokenMinutes;

	public AzoomLiveKitTokenService(
		ObjectMapper objectMapper,
		@Value("${ava.azoom.livekit.url:}") String liveKitUrl,
		@Value("${ava.azoom.livekit.api-key:}") String apiKey,
		@Value("${ava.azoom.livekit.api-secret:}") String apiSecret,
		@Value("${ava.azoom.livekit.token-minutes:120}") long tokenMinutes
	) {
		this.objectMapper = objectMapper;
		Map<String, String> localEnv = readLocalLiveKitEnv();
		this.liveKitUrl = firstNonBlank(liveKitUrl, localEnv.get("AVA_LIVEKIT_URL"));
		this.apiKey = firstNonBlank(apiKey, localEnv.get("AVA_LIVEKIT_API_KEY"));
		this.apiSecret = firstNonBlank(apiSecret, localEnv.get("AVA_LIVEKIT_API_SECRET"));
		this.tokenMinutes = tokenMinutes;
	}

	public boolean enabled() {
		return !liveKitUrl.isBlank() && !apiKey.isBlank() && !apiSecret.isBlank();
	}

	public String liveKitUrl() {
		return enabled() ? liveKitUrl : "";
	}

	public AzoomLiveKitTokenResponse token(String roomName, AuthPrincipal principal) {
		return token(roomName, principal, null);
	}

	public AzoomLiveKitTokenResponse token(String roomName, AuthPrincipal principal, UserProfileResponse profile) {
		if (!enabled()) {
			return AzoomLiveKitTokenResponse.disabled(roomName, "LiveKit media server is not configured.");
		}
		try {
			Instant now = Instant.now();
			Map<String, Object> header = Map.of("alg", "HS256", "typ", "JWT");
			Map<String, Object> videoGrant = new LinkedHashMap<>();
			videoGrant.put("roomJoin", true);
			videoGrant.put("room", roomName);
			videoGrant.put("canPublish", true);
			videoGrant.put("canSubscribe", true);
			videoGrant.put("canPublishData", true);
			videoGrant.put("canUpdateOwnMetadata", true);

			Map<String, Object> payload = new LinkedHashMap<>();
			String displayName = profile == null ? principal.displayName() : blankToDefault(profile.name(), principal.displayName());
			payload.put("iss", apiKey);
			payload.put("sub", principal.userId().toString());
			payload.put("name", displayName);
			payload.put("metadata", objectMapper.writeValueAsString(profileMetadata(profile, principal, displayName)));
			payload.put("nbf", now.minusSeconds(10).getEpochSecond());
			payload.put("exp", now.plusSeconds(Math.max(5, tokenMinutes) * 60).getEpochSecond());
			payload.put("video", videoGrant);

			String encodedHeader = encodeJson(header);
			String encodedPayload = encodeJson(payload);
			String signed = encodedHeader + "." + encodedPayload;
			return new AzoomLiveKitTokenResponse(
				true,
				liveKitUrl,
				signed + "." + sign(signed),
				roomName,
				""
			);
		} catch (Exception exception) {
			throw new IllegalStateException("Failed to create AZOOM media token.", exception);
		}
	}

	private String encodeJson(Object value) throws Exception {
		return BASE64_URL_ENCODER.encodeToString(objectMapper.writeValueAsBytes(value));
	}

	private String sign(String value) throws Exception {
		Mac mac = Mac.getInstance(HMAC_ALGORITHM);
		mac.init(new SecretKeySpec(apiSecret.getBytes(StandardCharsets.UTF_8), HMAC_ALGORITHM));
		return BASE64_URL_ENCODER.encodeToString(mac.doFinal(value.getBytes(StandardCharsets.UTF_8)));
	}

	private String normalize(String value) {
		return value == null ? "" : value.trim();
	}

	private String firstNonBlank(String primary, String fallback) {
		String normalized = normalize(primary);
		if (!normalized.isBlank()) {
			return normalized;
		}
		return normalize(fallback);
	}

	private Map<String, String> readLocalLiveKitEnv() {
		for (Path path : List.of(
			Path.of("LiveKit", "azoom-livekit.env"),
			Path.of("SpringBoot", "LiveKit", "azoom-livekit.env")
		)) {
			if (!Files.isRegularFile(path)) {
				continue;
			}
			try {
				Map<String, String> values = new HashMap<>();
				for (String line : Files.readAllLines(path, StandardCharsets.UTF_8)) {
					String trimmed = line.replace("\uFEFF", "").trim();
					if (trimmed.isBlank() || trimmed.startsWith("#")) {
						continue;
					}
					int index = trimmed.indexOf('=');
					if (index <= 0) {
						continue;
					}
					values.put(trimmed.substring(0, index).trim(), trimmed.substring(index + 1).trim());
				}
				if (!values.isEmpty()) {
					return values;
				}
			} catch (Exception ignored) {
				// Explicit application properties still remain the primary path.
			}
		}
		return Map.of();
	}

	private Map<String, Object> profileMetadata(
		UserProfileResponse profile,
		AuthPrincipal principal,
		String displayName
	) {
		Map<String, Object> metadata = new LinkedHashMap<>();
		metadata.put("userId", principal.userId().toString());
		metadata.put("email", principal.email());
		metadata.put("displayName", displayName);
		metadata.put("nickname", profile == null ? "" : blankToDefault(profile.nickname(), ""));
		metadata.put("avatarColor", profile == null ? "#7AA06A" : blankToDefault(profile.avatarColor(), "#7AA06A"));
		metadata.put("avatarImageUrl", profile == null ? "" : safeMetadataAvatarImageUrl(profile.avatarImageUrl()));
		return metadata;
	}

	private String blankToDefault(String value, String defaultValue) {
		return value == null || value.isBlank() ? defaultValue : value;
	}

	private String safeMetadataAvatarImageUrl(String value) {
		String normalized = normalize(value);
		if (
			normalized.isBlank()
				|| normalized.length() > MAX_METADATA_AVATAR_URL_LENGTH
				|| normalized.regionMatches(true, 0, "data:", 0, "data:".length())
		) {
			return "";
		}
		return normalized;
	}
}
