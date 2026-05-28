package com.ava.backend.avastock.entity;

import java.time.Instant;
import java.time.LocalDate;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(
	name = "ava_stock_bom_versions",
	uniqueConstraints = @UniqueConstraint(columnNames = {"model_id", "version_no"})
)
public class BomVersionEntity {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "model_id", nullable = false)
	private ProductModelEntity model;

	@Column(nullable = false)
	private int versionNo;

	@Column(length = 100)
	private String versionName;

	@Column(nullable = false)
	private boolean currentVersion;

	@Column(nullable = false)
	private LocalDate effectiveFrom = LocalDate.now();

	private LocalDate effectiveTo;

	@Column(nullable = false)
	private boolean active = true;

	@Column(nullable = false)
	private Instant createdAt;

	@Column(nullable = false)
	private Instant updatedAt;

	protected BomVersionEntity() {
	}

	public BomVersionEntity(ProductModelEntity model, int versionNo, String versionName, boolean currentVersion) {
		this.model = model;
		this.versionNo = versionNo;
		this.versionName = versionName;
		this.currentVersion = currentVersion;
	}

	@PrePersist
	void prePersist() {
		var now = Instant.now();
		createdAt = now;
		updatedAt = now;
	}

	@PreUpdate
	void preUpdate() {
		updatedAt = Instant.now();
	}

	public Long getId() {
		return id;
	}

	public ProductModelEntity getModel() {
		return model;
	}

	public int getVersionNo() {
		return versionNo;
	}

	public String getVersionName() {
		return versionName;
	}

	public boolean isCurrentVersion() {
		return currentVersion;
	}

	public LocalDate getEffectiveFrom() {
		return effectiveFrom;
	}

	public LocalDate getEffectiveTo() {
		return effectiveTo;
	}

	public boolean isActive() {
		return active;
	}

	public void setCurrentVersion(boolean currentVersion) {
		this.currentVersion = currentVersion;
	}

	public void setVersionName(String versionName) {
		this.versionName = versionName;
	}

	public void setActive(boolean active) {
		this.active = active;
	}
}
