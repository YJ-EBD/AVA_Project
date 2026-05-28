package com.ava.backend.avastock.entity;

import java.time.Instant;
import java.time.LocalDate;
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
@Table(name = "ava_stock_service_cases")
public class ServiceCaseEntity {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "product_unit_id", nullable = false)
	private ProductUnitEntity productUnit;

	@Column(nullable = false, unique = true, length = 120)
	private String serviceNo;

	@Column(nullable = false, length = 30)
	private String serviceStatus = "OPEN";

	@Column(columnDefinition = "text")
	private String issueSummary;

	@Column(nullable = false)
	private LocalDate receivedDate = LocalDate.now();

	@Column(nullable = false)
	private Instant startedAt = Instant.now();

	private Instant savedAt;

	private Instant completedAt;

	private UUID createdBy;

	@Column(nullable = false)
	private Instant createdAt;

	protected ServiceCaseEntity() {
	}

	public ServiceCaseEntity(ProductUnitEntity productUnit, String serviceNo, String issueSummary, UUID createdBy) {
		this.productUnit = productUnit;
		this.serviceNo = serviceNo;
		this.issueSummary = issueSummary;
		this.createdBy = createdBy;
	}

	@PrePersist
	void prePersist() {
		createdAt = Instant.now();
	}

	public Long getId() {
		return id;
	}

	public ProductUnitEntity getProductUnit() {
		return productUnit;
	}

	public String getServiceNo() {
		return serviceNo;
	}

	public String getServiceStatus() {
		return serviceStatus;
	}

	public String getIssueSummary() {
		return issueSummary;
	}

	public Instant getStartedAt() {
		return startedAt;
	}

	public Instant getSavedAt() {
		return savedAt;
	}

	public Instant getCompletedAt() {
		return completedAt;
	}

	public void markSaved() {
		this.serviceStatus = "SAVED";
		this.savedAt = Instant.now();
	}

	public void markCompleted() {
		this.serviceStatus = "COMPLETED";
		this.completedAt = Instant.now();
	}
}
