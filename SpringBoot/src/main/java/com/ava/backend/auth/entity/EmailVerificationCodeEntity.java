package com.ava.backend.auth.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;

@Entity
@Table(
	name = "auth_email_verification_codes",
	indexes = {
		@Index(name = "idx_auth_email_verification_email_created", columnList = "email, created_at")
	}
)
public class EmailVerificationCodeEntity {

	@Id
	private UUID id;

	@Column(nullable = false, length = 160)
	private String email;

	@Column(nullable = false, length = 120)
	private String codeHash;

	@Column(nullable = false)
	private Instant createdAt;

	@Column(nullable = false)
	private Instant expiresAt;

	private Instant verifiedAt;

	private Instant consumedAt;

	@Column(nullable = false)
	private int attempts;

	protected EmailVerificationCodeEntity() {
	}

	public EmailVerificationCodeEntity(String email, String codeHash, Instant createdAt, Instant expiresAt) {
		this.id = UUID.randomUUID();
		this.email = email;
		this.codeHash = codeHash;
		this.createdAt = createdAt;
		this.expiresAt = expiresAt;
		this.attempts = 0;
	}

	public String getEmail() {
		return email;
	}

	public String getCodeHash() {
		return codeHash;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}

	public Instant getExpiresAt() {
		return expiresAt;
	}

	public Instant getVerifiedAt() {
		return verifiedAt;
	}

	public Instant getConsumedAt() {
		return consumedAt;
	}

	public int getAttempts() {
		return attempts;
	}

	public boolean isExpired(Instant now) {
		return !expiresAt.isAfter(now);
	}

	public boolean isConsumed() {
		return consumedAt != null;
	}

	public void markAttempt() {
		this.attempts++;
	}

	public void markVerified(Instant verifiedAt) {
		this.verifiedAt = verifiedAt;
	}

	public void markConsumed(Instant consumedAt) {
		this.consumedAt = consumedAt;
	}
}
