package com.ava.backend.auth.service;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.RedisConnectionFailureException;
import org.springframework.stereotype.Service;

@Service
public class LoginSessionService {

	private final StringRedisTemplate redisTemplate;
	private final Duration sessionTtl;
	private final Duration rememberSessionTtl;
	private final Map<UUID, InMemorySession> fallbackSessions = new ConcurrentHashMap<>();

	public LoginSessionService(
		StringRedisTemplate redisTemplate,
		@Value("${ava.auth.session-hours}") long sessionHours,
		@Value("${ava.auth.session-remember-days}") long sessionRememberDays
	) {
		this.redisTemplate = redisTemplate;
		this.sessionTtl = Duration.ofHours(sessionHours);
		this.rememberSessionTtl = Duration.ofDays(sessionRememberDays);
	}

	public SessionRegistration register(UUID userId, boolean rememberLogin) {
		String sessionId = UUID.randomUUID().toString();
		try {
			String key = key(userId);
			String previous = redisTemplate.opsForValue().get(key);
			redisTemplate.opsForValue().set(key, sessionId, rememberLogin ? rememberSessionTtl : sessionTtl);
			return new SessionRegistration(sessionId, previous != null && !previous.equals(sessionId));
		} catch (RedisConnectionFailureException exception) {
			return registerFallback(userId, sessionId, rememberLogin);
		}
	}

	public boolean isCurrentSession(UUID userId, String sessionId) {
		try {
			return sessionId != null && sessionId.equals(redisTemplate.opsForValue().get(key(userId)));
		} catch (RedisConnectionFailureException exception) {
			InMemorySession session = fallbackSessions.get(userId);
			if (session == null || session.expiresAt().isBefore(Instant.now())) {
				fallbackSessions.remove(userId);
				return false;
			}
			return sessionId != null && sessionId.equals(session.sessionId());
		}
	}

	public void invalidate(UUID userId) {
		try {
			redisTemplate.delete(key(userId));
		} catch (RedisConnectionFailureException exception) {
			fallbackSessions.remove(userId);
		}
	}

	private String key(UUID userId) {
		return "ava:auth:session:" + userId;
	}

	public record SessionRegistration(String sessionId, boolean replacedPreviousLogin) {
	}

	private SessionRegistration registerFallback(UUID userId, String sessionId, boolean rememberLogin) {
		InMemorySession previous = fallbackSessions.put(
			userId,
			new InMemorySession(sessionId, Instant.now().plus(rememberLogin ? rememberSessionTtl : sessionTtl))
		);
		return new SessionRegistration(sessionId, previous != null && !previous.sessionId().equals(sessionId));
	}

	private record InMemorySession(String sessionId, Instant expiresAt) {
	}
}
