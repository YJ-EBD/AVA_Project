package com.ava.backend.auth.repository;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.auth.entity.AuthSessionEntity;

public interface AuthSessionRepository extends JpaRepository<AuthSessionEntity, UUID> {

	Optional<AuthSessionEntity> findByAccountIdAndSessionId(UUID accountId, String sessionId);

	List<AuthSessionEntity> findByAccountIdAndInvalidatedAtIsNullAndExpiresAtAfter(UUID accountId, Instant now);

	boolean existsByAccountIdAndInvalidatedAtIsNullAndExpiresAtAfter(UUID accountId, Instant now);
}
