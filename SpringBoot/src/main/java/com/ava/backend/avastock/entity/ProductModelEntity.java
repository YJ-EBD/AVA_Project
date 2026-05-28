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
@Table(name = "ava_stock_product_models")
public class ProductModelEntity {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@Column(nullable = false, unique = true, length = 60)
	private String modelCode;

	@Column(nullable = false, length = 150)
	private String modelName;

	@Column(columnDefinition = "text")
	private String description;

	@Column(columnDefinition = "text")
	private String imageUrl;

	@Column(nullable = false)
	private boolean active = true;

	@Column(nullable = false)
	private Instant createdAt;

	@Column(nullable = false)
	private Instant updatedAt;

	protected ProductModelEntity() {
	}

	public ProductModelEntity(String modelCode, String modelName) {
		this.modelCode = modelCode;
		this.modelName = modelName;
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

	public String getModelCode() {
		return modelCode;
	}

	public String getModelName() {
		return modelName;
	}

	public String getDescription() {
		return description;
	}

	public String getImageUrl() {
		return imageUrl;
	}

	public boolean isActive() {
		return active;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}

	public Instant getUpdatedAt() {
		return updatedAt;
	}

	public void setModelName(String modelName) {
		this.modelName = modelName;
	}

	public void setDescription(String description) {
		this.description = description;
	}

	public void setImageUrl(String imageUrl) {
		this.imageUrl = imageUrl;
	}

	public void setActive(boolean active) {
		this.active = active;
	}
}
