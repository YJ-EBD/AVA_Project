package com.ava.backend.avastock.entity;

import java.time.Instant;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

@Entity
@Table(name = "ava_stock_parts")
public class PartEntity {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@Column(nullable = false, unique = true, length = 100)
	private String partCode;

	@Column(nullable = false, length = 150)
	private String partName;

	@Column(nullable = false, length = 20)
	private String unit = "EA";

	@Column(columnDefinition = "text")
	private String imageUrl;

	@Column(columnDefinition = "text")
	private String description;

	@Column(nullable = false)
	private boolean active = true;

	@Column(nullable = false)
	private Instant createdAt;

	@Column(nullable = false)
	private Instant updatedAt;

	protected PartEntity() {
	}

	public PartEntity(String partCode, String partName) {
		this.partCode = partCode;
		this.partName = partName;
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

	public String getPartCode() {
		return partCode;
	}

	public String getPartName() {
		return partName;
	}

	public String getUnit() {
		return unit;
	}

	public String getImageUrl() {
		return imageUrl;
	}

	public String getDescription() {
		return description;
	}

	public boolean isActive() {
		return active;
	}

	public void setPartName(String partName) {
		this.partName = partName;
	}

	public void setUnit(String unit) {
		this.unit = unit;
	}

	public void setImageUrl(String imageUrl) {
		this.imageUrl = imageUrl;
	}

	public void setDescription(String description) {
		this.description = description;
	}

	public void setActive(boolean active) {
		this.active = active;
	}
}
