package com.ava.backend.access.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(name = "permissions")
public class PermissionEntity {

	@Id
	private UUID id;

	@Column(nullable = false, unique = true, length = 80)
	private String code;

	@Column(nullable = false, length = 120)
	private String name;

	@Column(length = 400)
	private String description;

	@Column(nullable = false)
	private Instant createdAt;

	protected PermissionEntity() {
	}

	public PermissionEntity(String code, String name, String description) {
		this.id = UUID.randomUUID();
		this.code = code;
		this.name = name;
		this.description = description;
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

	public String getCode() {
		return code;
	}
}
