package com.ava.backend.auth.service;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.RedisConnectionFailureException;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.ava.backend.auth.entity.AuthSessionEntity;
import com.ava.backend.auth.repository.AuthSessionRepository;

@Service
public class LoginSessionService {

	private final StringRedisTemplate redisTemplate;
	private final AuthSessionRepository sessionRepository;
	private final Duration sessionTtl;
	private final Duration rememberSessionTtl;
	private final Map<UUID, InMemorySession> fallbackSessions = new ConcurrentHashMap<>();

	public LoginSessionService(
		StringRedisTemplate redisTemplate,
		AuthSessionRepository sessionRepository,
		@Value("${ava.auth.session-hours}") long sessionHours,
		@Value("${ava.auth.session-remember-days}") long sessionRememberDays
	) {
		this.redisTemplate = redisTemplate;
		this.sessionRepository = sessionRepository;
		this.sessionTtl = Duration.ofHours(sessionHours);
		this.rememberSessionTtl = Duration.ofDays(sessionRememberDays);
	}

	@Transactional
	public SessionRegistration register(UUID userId, boolean rememberLogin) {
		String sessionId = UUID.randomUUID().toString();
		Instant now = Instant.now();
		boolean hadActiveSession = sessionRepository.existsByAccountIdAndInvalidatedAtIsNullAndExpiresAtAfter(userId, now)
			|| hasRedisOrFallbackSession(userId);
		sessionRepository
			.findByAccountIdAndInvalidatedAtIsNullAndExpiresAtAfter(userId, now)
			.forEach(AuthSessionEntity::invalidate);
		Instant expiresAt = now.plus(rememberLogin ? rememberSessionTtl : sessionTtl);
		sessionRepository.save(new AuthSessionEntity(userId, sessionId, rememberLogin, expiresAt));
		writeRedisOrFallback(userId, sessionId, rememberLogin, expiresAt);
		return new SessionRegistration(sessionId, hadActiveSession);
	}

	@Transactional
	public boolean isCurrentSession(UUID userId, String sessionId) {
		if (sessionId == null || sessionId.isBlank()) {
			return false;
		}
		if (isCurrentRedisOrFallbackSession(userId, sessionId)) {
			markSessionSeen(userId, sessionId);
			return true;
		}
		Instant now = Instant.now();
		return sessionRepository.findByAccountIdAndSessionId(userId, sessionId)
			.filter(session -> session.isActive(now))
			.map(session -> {
				session.markSeen();
				writeRedisOrFallback(userId, sessionId, false, session.getExpiresAt());
				return true;
			})
			.orElse(false);
	}

	@Transactional(readOnly = true)
	public boolean hasActiveSession(UUID userId) {
		return sessionRepository.existsByAccountIdAndInvalidatedAtIsNullAndExpiresAtAfter(userId, Instant.now())
			|| hasRedisOrFallbackSession(userId);
	}

	@Transactional
	public void invalidate(UUID userId) {
		try {
			redisTemplate.delete(key(userId));
		} catch (RedisConnectionFailureException exception) {
			// Redis is optional for local development; the DB session remains authoritative.
		}
		fallbackSessions.remove(userId);
		sessionRepository
			.findByAccountIdAndInvalidatedAtIsNullAndExpiresAtAfter(userId, Instant.now())
			.forEach(AuthSessionEntity::invalidate);
	}

	private void markSessionSeen(UUID userId, String sessionId) {
		sessionRepository.findByAccountIdAndSessionId(userId, sessionId).ifPresent(AuthSessionEntity::markSeen);
	}

	private boolean hasRedisOrFallbackSession(UUID userId) {
		try {
			String sessionId = redisTemplate.opsForValue().get(key(userId));
			return sessionId != null && !sessionId.isBlank();
		} catch (RedisConnectionFailureException exception) {
			InMemorySession session = fallbackSessions.get(userId);
			if (session == null || session.expiresAt().isBefore(Instant.now())) {
				fallbackSessions.remove(userId);
				return false;
			}
			return true;
		}
	}

	private boolean isCurrentRedisOrFallbackSession(UUID userId, String sessionId) {
		try {
			return sessionId.equals(redisTemplate.opsForValue().get(key(userId)));
		} catch (RedisConnectionFailureException exception) {
			InMemorySession session = fallbackSessions.get(userId);
			if (session == null || session.expiresAt().isBefore(Instant.now())) {
				fallbackSessions.remove(userId);
				return false;
			}
			return sessionId.equals(session.sessionId());
		}
	}

	private void writeRedisOrFallback(UUID userId, String sessionId, boolean rememberLogin, Instant expiresAt) {
		try {
			redisTemplate.opsForValue().set(key(userId), sessionId, rememberLogin ? rememberSessionTtl : sessionTtl);
		} catch (RedisConnectionFailureException exception) {
			fallbackSessions.put(userId, new InMemorySession(sessionId, expiresAt));
		}
	}

	private String key(UUID userId) {
		return "ava:auth:session:" + userId;
	}

	public record SessionRegistration(String sessionId, boolean replacedPreviousLogin) {
	}

	private record InMemorySession(String sessionId, Instant expiresAt) {
	}
}
