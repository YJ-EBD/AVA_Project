package com.ava.backend.avastock.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(name = "ava_stock_product_operations")
public class ProductOperationEntity {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "product_unit_id", nullable = false)
	private ProductUnitEntity productUnit;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "bom_version_id", nullable = false)
	private BomVersionEntity bomVersion;

	@ManyToOne(fetch = FetchType.LAZY)
	@JoinColumn(name = "service_case_id")
	private ServiceCaseEntity serviceCase;

	@Column(nullable = false, length = 30)
	private String operationType;

	@Column(nullable = false, length = 30)
	private String operationStatus = "DRAFT";

	@Column(nullable = false)
	private Instant startedAt = Instant.now();

	private Instant savedAt;

	private Instant completedAt;

	private UUID createdBy;

	private UUID completedBy;

	@Column(columnDefinition = "text")
	private String notes;

	protected ProductOperationEntity() {
	}

	public ProductOperationEntity(ProductUnitEntity productUnit, BomVersionEntity bomVersion, ServiceCaseEntity serviceCase, String operationType, UUID createdBy) {
		this.productUnit = productUnit;
		this.bomVersion = bomVersion;
		this.serviceCase = serviceCase;
		this.operationType = operationType;
		this.createdBy = createdBy;
	}

	@PrePersist
	void prePersist() {
		if (startedAt == null) {
			startedAt = Instant.now();
		}
	}

	public Long getId() {
		return id;
	}

	public ProductUnitEntity getProductUnit() {
		return productUnit;
	}

	public BomVersionEntity getBomVersion() {
		return bomVersion;
	}

	public ServiceCaseEntity getServiceCase() {
		return serviceCase;
	}

	public String getOperationType() {
		return operationType;
	}

	public String getOperationStatus() {
		return operationStatus;
	}

	public Instant getSavedAt() {
		return savedAt;
	}

	public Instant getCompletedAt() {
		return completedAt;
	}

	public String getNotes() {
		return notes;
	}

	public void markSaved(String notes) {
		this.operationStatus = "SAVED";
		this.savedAt = Instant.now();
		this.notes = notes;
	}

	public void markCompleted(UUID completedBy, String notes) {
		this.operationStatus = "COMPLETED";
		this.completedAt = Instant.now();
		this.completedBy = completedBy;
		this.notes = notes;
	}
}
