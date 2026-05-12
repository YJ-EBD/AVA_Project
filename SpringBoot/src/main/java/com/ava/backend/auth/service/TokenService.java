package com.ava.backend.auth.service;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.ava.backend.user.entity.UserAccount;
import com.ava.backend.user.entity.UserRole;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

@Service
public class TokenService {

	private static final String HMAC_ALGORITHM = "HmacSHA256";
	private static final Base64.Encoder BASE64_URL_ENCODER = Base64.getUrlEncoder().withoutPadding();
	private static final Base64.Decoder BASE64_URL_DECODER = Base64.getUrlDecoder();

	private final ObjectMapper objectMapper;
	private final byte[] secret;
	private final long accessTokenMinutes;
	private final long refreshTokenDays;

	public TokenService(
		ObjectMapper objectMapper,
		@Value("${ava.auth.jwt-secret}") String secret,
		@Value("${ava.auth.access-token-minutes}") long accessTokenMinutes,
		@Value("${ava.auth.refresh-token-days}") long refreshTokenDays
	) {
		this.objectMapper = objectMapper;
		this.secret = secret.getBytes(StandardCharsets.UTF_8);
		this.accessTokenMinutes = accessTokenMinutes;
		this.refreshTokenDays = refreshTokenDays;
	}

	public TokenPair issue(UserAccount account, String sessionId) {
		Instant now = Instant.now();
		String accessToken = createToken(account, sessionId, "access", now.plusSeconds(accessTokenMinutes * 60));
		String refreshToken = createToken(account, sessionId, "refresh", now.plusSeconds(refreshTokenDays * 24 * 60 * 60));
		return new TokenPair(accessToken, refreshToken, accessTokenMinutes * 60);
	}

	public Optional<TokenClaims> parse(String token) {
		try {
			String[] parts = token.split("\\.");
			if (parts.length != 3) {
				return Optional.empty();
			}
			String signed = parts[0] + "." + parts[1];
			if (!constantTimeEquals(parts[2], sign(signed))) {
				return Optional.empty();
			}
			Map<String, Object> payload = objectMapper.readValue(
				BASE64_URL_DECODER.decode(parts[1]),
				new TypeReference<>() {
				}
			);
			long exp = ((Number) payload.get("exp")).longValue();
			if (Instant.now().getEpochSecond() >= exp) {
				return Optional.empty();
			}
			return Optional.of(new TokenClaims(
				UUID.fromString((String) payload.get("sub")),
				(String) payload.get("email"),
				(String) payload.get("name"),
				UserRole.valueOf((String) payload.get("role")),
				(String) payload.get("sid"),
				(String) payload.get("typ")
			));
		} catch (Exception ignored) {
			return Optional.empty();
		}
	}

	private String createToken(UserAccount account, String sessionId, String type, Instant expiresAt) {
		try {
			Map<String, Object> header = Map.of("alg", "HS256", "typ", "JWT");
			Map<String, Object> payload = new LinkedHashMap<>();
			payload.put("sub", account.getId().toString());
			payload.put("email", account.getEmail());
			payload.put("name", account.getDisplayName());
			payload.put("role", account.getRole().name());
			payload.put("sid", sessionId);
			payload.put("typ", type);
			payload.put("exp", expiresAt.getEpochSecond());
			String encodedHeader = encodeJson(header);
			String encodedPayload = encodeJson(payload);
			String signed = encodedHeader + "." + encodedPayload;
			return signed + "." + sign(signed);
		} catch (Exception exception) {
			throw new IllegalStateException("Failed to create token", exception);
		}
	}

	private String encodeJson(Object value) throws Exception {
		return BASE64_URL_ENCODER.encodeToString(objectMapper.writeValueAsBytes(value));
	}

	private String sign(String value) throws Exception {
		Mac mac = Mac.getInstance(HMAC_ALGORITHM);
		mac.init(new SecretKeySpec(secret, HMAC_ALGORITHM));
		return BASE64_URL_ENCODER.encodeToString(mac.doFinal(value.getBytes(StandardCharsets.UTF_8)));
	}

	private boolean constantTimeEquals(String a, String b) {
		return MessageDigestUtil.constantTimeEquals(a.getBytes(StandardCharsets.UTF_8), b.getBytes(StandardCharsets.UTF_8));
	}

	public record TokenPair(String accessToken, String refreshToken, long expiresInSeconds) {
	}

	public record TokenClaims(
		UUID userId,
		String email,
		String displayName,
		UserRole role,
		String sessionId,
		String type
	) {
		public boolean isAccessToken() {
			return "access".equals(type);
		}

		public boolean isRefreshToken() {
			return "refresh".equals(type);
		}
	}

	private static final class MessageDigestUtil {
		private MessageDigestUtil() {
		}

		static boolean constantTimeEquals(byte[] a, byte[] b) {
			if (a.length != b.length) {
				return false;
			}
			int result = 0;
			for (int i = 0; i < a.length; i++) {
				result |= a[i] ^ b[i];
			}
			return result == 0;
		}
	}
}
