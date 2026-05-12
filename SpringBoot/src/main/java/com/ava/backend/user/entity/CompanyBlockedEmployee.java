package com.ava.backend.user.entity;

import java.time.Instant;
import java.util.UUID;

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
	name = "company_blocked_employees",
	uniqueConstraints = @UniqueConstraint(columnNames = {"company_name", "target_account_id"})
)
public class CompanyBlockedEmployee {

	@Id
	private UUID id;

	@Column(name = "company_name", nullable = false, length = 80)
	private String companyName;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "target_account_id", nullable = false)
	private UserAccount targetAccount;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "blocked_by_account_id", nullable = false)
	private UserAccount blockedBy;

	@Column(nullable = false)
	private Instant createdAt;

	protected CompanyBlockedEmployee() {
	}

	public CompanyBlockedEmployee(String companyName, UserAccount targetAccount, UserAccount blockedBy) {
		this.id = UUID.randomUUID();
		this.companyName = companyName;
		this.targetAccount = targetAccount;
		this.blockedBy = blockedBy;
	}

	@PrePersist
	void prePersist() {
		this.createdAt = Instant.now();
	}

	public UUID getId() {
		return id;
	}

	public String getCompanyName() {
		return companyName;
	}

	public UserAccount getTargetAccount() {
		return targetAccount;
	}
}
