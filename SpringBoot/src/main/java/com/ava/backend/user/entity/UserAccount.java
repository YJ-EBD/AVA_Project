package com.ava.backend.user.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

@Entity
@Table(name = "user_accounts")
public class UserAccount {

	@Id
	private UUID id;

	@Column(nullable = false, unique = true, length = 160)
	private String email;

	@Column(nullable = false)
	private String passwordHash;

	@Column(nullable = false, length = 80)
	private String displayName;

	@Enumerated(EnumType.STRING)
	@Column(nullable = false, length = 20)
	private UserRole role = UserRole.USER;

	@Column(nullable = false)
	private boolean enabled = true;

	@Column(nullable = false)
	private Instant createdAt;

	@Column(nullable = false)
	private Instant updatedAt;

	protected UserAccount() {
	}

	public UserAccount(String email, String passwordHash, String displayName, UserRole role) {
		this.id = UUID.randomUUID();
		this.email = email;
		this.passwordHash = passwordHash;
		this.displayName = displayName;
		this.role = role;
	}

	@PrePersist
	void prePersist() {
		var now = Instant.now();
		this.createdAt = now;
		this.updatedAt = now;
	}

	@PreUpdate
	void preUpdate() {
		this.updatedAt = Instant.now();
	}

	public UUID getId() {
		return id;
	}

	public String getEmail() {
		return email;
	}

	public String getPasswordHash() {
		return passwordHash;
	}

	public String getDisplayName() {
		return displayName;
	}

	public UserRole getRole() {
		return role;
	}

	public boolean isEnabled() {
		return enabled;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}

	public void setPasswordHash(String passwordHash) {
		this.passwordHash = passwordHash;
	}

	public void setDisplayName(String displayName) {
		this.displayName = displayName;
	}

	public void setRole(UserRole role) {
		this.role = role;
	}

	public void setEnabled(boolean enabled) {
		this.enabled = enabled;
	}
}
