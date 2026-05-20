package com.ava.backend.azoom.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.Base64;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.Test;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.user.dto.UserProfileResponse;
import com.ava.backend.user.entity.UserRole;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

class AzoomLiveKitTokenServiceTest {

	private final ObjectMapper objectMapper = new ObjectMapper();

	@Test
	void omitsDataAvatarFromLiveKitJwtMetadata() throws Exception {
		AzoomLiveKitTokenService service = new AzoomLiveKitTokenService(
			objectMapper,
			"ws://112.166.136.198:7880",
			"ava-azoom",
			"secret",
			120
		);
		String largeDataAvatar = "data:image/png;base64," + "A".repeat(40_000);
		AuthPrincipal principal = new AuthPrincipal(
			UUID.randomUUID(),
			"user@example.test",
			"Tester",
			UserRole.USER,
			"session"
		);
		UserProfileResponse profile = new UserProfileResponse(
			principal.userId(),
			principal.email(),
			"Tester",
			"Tester",
			"Tester",
			"",
			"tester@example.test",
			"선택 안 함",
			UserRole.USER,
			"AVA",
			"",
			"",
			LocalDate.of(1990, 1, 1),
			"online",
			"#7AA06A",
			"",
			largeDataAvatar,
			"",
			"",
			false
		);

		String token = service.token("azoom-ava-voice-all-staff", principal, profile).token();

		Map<String, Object> payload = decodePayload(token);
		Map<String, Object> metadata = objectMapper.readValue(
			String.valueOf(payload.get("metadata")),
			new TypeReference<>() {
			}
		);
		assertEquals("", metadata.get("avatarImageUrl"));
		assertTrue(token.length() < 4_000);
	}

	private Map<String, Object> decodePayload(String token) throws Exception {
		String[] parts = token.split("\\.");
		String payloadJson = new String(Base64.getUrlDecoder().decode(parts[1]), StandardCharsets.UTF_8);
		return objectMapper.readValue(
			payloadJson,
			new TypeReference<>() {
			}
		);
	}
}
