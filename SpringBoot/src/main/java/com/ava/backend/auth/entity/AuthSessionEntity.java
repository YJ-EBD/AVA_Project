package com.ava.backend.auth.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(
	name = "sessions",
	indexes = {
		@Index(name = "idx_sessions_account_active", columnList = "account_id,expires_at,invalidated_at"),
		@Index(name = "idx_sessions_session_id", columnList = "session_id")
	}
)
public class AuthSessionEntity {

	@Id
	private UUID id;

	@Column(name = "account_id", nullable = false)
	private UUID accountId;

	@Column(name = "session_id", nullable = false, unique = true, length = 80)
	private String sessionId;

	@Column(name = "remember_login", nullable = false)
	private boolean rememberLogin;

	@Column(name = "expires_at", nullable = false)
	private Instant expiresAt;

	@Column(name = "created_at", nullable = false)
	private Instant createdAt;

	@Column(name = "last_seen_at", nullable = false)
	private Instant lastSeenAt;

	@Column(name = "invalidated_at")
	private Instant invalidatedAt;

	protected AuthSessionEntity() {
	}

	public AuthSessionEntity(UUID accountId, String sessionId, boolean rememberLogin, Instant expiresAt) {
		this.id = UUID.randomUUID();
		this.accountId = accountId;
		this.sessionId = sessionId;
		this.rememberLogin = rememberLogin;
		this.expiresAt = expiresAt;
	}

	@PrePersist
	void prePersist() {
		Instant now = Instant.now();
		if (id == null) {
			id = UUID.randomUUID();
		}
		if (createdAt == null) {
			createdAt = now;
		}
		if (lastSeenAt == null) {
			lastSeenAt = now;
		}
	}

	public UUID getId() {
		return id;
	}

	public UUID getAccountId() {
		return accountId;
	}

	public String getSessionId() {
		return sessionId;
	}

	public Instant getExpiresAt() {
		return expiresAt;
	}

	public Instant getInvalidatedAt() {
		return invalidatedAt;
	}

	public boolean isActive(Instant now) {
		return invalidatedAt == null && expiresAt.isAfter(now);
	}

	public void markSeen() {
		this.lastSeenAt = Instant.now();
	}

	public void invalidate() {
		if (invalidatedAt == null) {
			invalidatedAt = Instant.now();
		}
	}
}
