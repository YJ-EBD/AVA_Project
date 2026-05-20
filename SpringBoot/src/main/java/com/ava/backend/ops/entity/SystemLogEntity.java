package com.ava.backend.ops.entity;

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
	name = "system_logs",
	indexes = {
		@Index(name = "idx_system_logs_created", columnList = "created_at"),
		@Index(name = "idx_system_logs_status_created", columnList = "status,created_at"),
		@Index(name = "idx_system_logs_account_created", columnList = "account_id,created_at")
	}
)
public class SystemLogEntity {

	@Id
	private UUID id;

	@Column(name = "request_id", nullable = false, length = 80)
	private String requestId;

	@Column(name = "account_id")
	private UUID accountId;

	@Column(name = "account_email", length = 160)
	private String accountEmail;

	@Column(nullable = false, length = 16)
	private String method;

	@Column(nullable = false, length = 600)
	private String path;

	@Column(name = "query_string", length = 1000)
	private String queryString;

	@Column(nullable = false)
	private int status;

	@Column(name = "duration_ms", nullable = false)
	private long durationMs;

	@Column(name = "ip_address", length = 80)
	private String ipAddress;

	@Column(name = "user_agent", length = 400)
	private String userAgent;

	@Column(name = "error_message", length = 800)
	private String errorMessage;

	@Column(name = "created_at", nullable = false)
	private Instant createdAt;

	protected SystemLogEntity() {
	}

	public SystemLogEntity(
		String requestId,
		UUID accountId,
		String accountEmail,
		String method,
		String path,
		String queryString,
		int status,
		long durationMs,
		String ipAddress,
		String userAgent,
		String errorMessage
	) {
		this.id = UUID.randomUUID();
		this.requestId = requestId;
		this.accountId = accountId;
		this.accountEmail = accountEmail;
		this.method = method;
		this.path = path;
		this.queryString = queryString;
		this.status = status;
		this.durationMs = durationMs;
		this.ipAddress = ipAddress;
		this.userAgent = userAgent;
		this.errorMessage = errorMessage;
	}

	@PrePersist
	void prePersist() {
		if (id == null) {
			id = UUID.randomUUID();
		}
		if (createdAt == null) {
			createdAt = Instant.now();
		}
	}

	public UUID getId() {
		return id;
	}

	public String getRequestId() {
		return requestId;
	}

	public UUID getAccountId() {
		return accountId;
	}

	public String getAccountEmail() {
		return accountEmail;
	}

	public String getMethod() {
		return method;
	}

	public String getPath() {
		return path;
	}

	public String getQueryString() {
		return queryString;
	}

	public int getStatus() {
		return status;
	}

	public long getDurationMs() {
		return durationMs;
	}

	public String getIpAddress() {
		return ipAddress;
	}

	public String getUserAgent() {
		return userAgent;
	}

	public String getErrorMessage() {
		return errorMessage;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}
}
