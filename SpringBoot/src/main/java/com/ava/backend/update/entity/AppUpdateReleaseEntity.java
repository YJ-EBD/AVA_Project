package com.ava.backend.update.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(
	name = "app_update_releases",
	uniqueConstraints = @UniqueConstraint(name = "uk_app_update_release_platform_version", columnNames = {"platform", "version"}),
	indexes = {
		@Index(name = "idx_app_update_release_platform", columnList = "platform"),
		@Index(name = "idx_app_update_release_created_at", columnList = "created_at")
	}
)
public class AppUpdateReleaseEntity {

	@Id
	@GeneratedValue(strategy = GenerationType.UUID)
	private UUID id;

	@Column(nullable = false, length = 32)
	private String platform;

	@Column(nullable = false, length = 40)
	private String version;

	@Column(name = "file_name", nullable = false, length = 260)
	private String fileName;

	@Column(nullable = false)
	private boolean required;

	@Column(name = "release_notes", nullable = false, columnDefinition = "text")
	private String releaseNotes;

	@Column(length = 80)
	private String sha256;

	@Column(name = "size_bytes", nullable = false)
	private long sizeBytes;

	@Column(name = "package_available", nullable = false)
	private boolean packageAvailable;

	@Column(name = "created_at", nullable = false)
	private Instant createdAt;

	@Column(name = "updated_at", nullable = false)
	private Instant updatedAt;

	protected AppUpdateReleaseEntity() {
	}

	public AppUpdateReleaseEntity(String platform, String version) {
		this.platform = platform;
		this.version = version;
	}

	@PrePersist
	void prePersist() {
		Instant now = Instant.now();
		this.createdAt = now;
		this.updatedAt = now;
	}

	@PreUpdate
	void preUpdate() {
		this.updatedAt = Instant.now();
	}

	public void update(
		String fileName,
		boolean required,
		String releaseNotes,
		String sha256,
		long sizeBytes,
		boolean packageAvailable
	) {
		this.fileName = fileName == null ? "" : fileName;
		this.required = required;
		this.releaseNotes = releaseNotes == null ? "" : releaseNotes;
		this.sha256 = sha256 == null ? "" : sha256;
		this.sizeBytes = sizeBytes;
		this.packageAvailable = packageAvailable;
	}

	public String getPlatform() {
		return platform;
	}

	public String getVersion() {
		return version;
	}

	public String getFileName() {
		return fileName;
	}

	public boolean isRequired() {
		return required;
	}

	public String getReleaseNotes() {
		return releaseNotes;
	}

	public String getSha256() {
		return sha256;
	}

	public long getSizeBytes() {
		return sizeBytes;
	}

	public boolean isPackageAvailable() {
		return packageAvailable;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}

	public Instant getUpdatedAt() {
		return updatedAt;
	}
}
