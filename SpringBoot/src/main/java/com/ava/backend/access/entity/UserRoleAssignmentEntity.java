package com.ava.backend.access.entity;

import java.time.Instant;
import java.util.UUID;

import com.ava.backend.user.entity.UserAccount;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(
	name = "user_roles",
	uniqueConstraints = @UniqueConstraint(columnNames = {"account_id", "role_code"})
)
public class UserRoleAssignmentEntity {

	@Id
	private UUID id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "account_id", nullable = false)
	private UserAccount account;

	@Column(name = "role_code", nullable = false, length = 40)
	private String roleCode;

	@Column(nullable = false)
	private Instant assignedAt;

	@Column(name = "assigned_by_account_id")
	private UUID assignedByAccountId;

	protected UserRoleAssignmentEntity() {
	}

	public UserRoleAssignmentEntity(UserAccount account, String roleCode, UUID assignedByAccountId) {
		this.id = UUID.randomUUID();
		this.account = account;
		this.roleCode = roleCode;
		this.assignedByAccountId = assignedByAccountId;
	}

	@PrePersist
	void prePersist() {
		if (id == null) {
			id = UUID.randomUUID();
		}
		if (assignedAt == null) {
			assignedAt = Instant.now();
		}
	}
}
