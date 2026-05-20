package com.ava.backend.azoom.entity;

import java.time.Instant;
import java.util.UUID;

import com.ava.backend.user.entity.UserAccount;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(
	name = "azoom_members",
	uniqueConstraints = @UniqueConstraint(columnNames = {"workspace_id", "account_id"}),
	indexes = @Index(name = "idx_azoom_members_workspace_role", columnList = "workspace_id,role")
)
public class AzoomMemberEntity {

	@Id
	private UUID id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "workspace_id", nullable = false)
	private AzoomWorkspaceEntity workspace;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "account_id", nullable = false)
	private UserAccount account;

	@Enumerated(EnumType.STRING)
	@Column(nullable = false, length = 20)
	private AzoomMemberRole role;

	@Column(nullable = false)
	private Instant joinedAt;

	protected AzoomMemberEntity() {
	}

	public AzoomMemberEntity(AzoomWorkspaceEntity workspace, UserAccount account, AzoomMemberRole role) {
		this.id = UUID.randomUUID();
		this.workspace = workspace;
		this.account = account;
		this.role = role;
	}

	@PrePersist
	void prePersist() {
		if (id == null) {
			id = UUID.randomUUID();
		}
		if (joinedAt == null) {
			joinedAt = Instant.now();
		}
	}

	public UserAccount getAccount() {
		return account;
	}

	public AzoomMemberRole getRole() {
		return role;
	}

	public void setRole(AzoomMemberRole role) {
		this.role = role;
	}
}
