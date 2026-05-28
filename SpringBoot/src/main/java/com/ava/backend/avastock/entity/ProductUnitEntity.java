package com.ava.backend.avastock.entity;

import java.time.Instant;

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

@Entity
@Table(name = "ava_stock_product_units")
public class ProductUnitEntity {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "model_id", nullable = false)
	private ProductModelEntity model;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "bom_version_id", nullable = false)
	private BomVersionEntity bomVersion;

	@ManyToOne(fetch = FetchType.LAZY)
	@JoinColumn(name = "receipt_id")
	private ProductReceiptEntity receipt;

	@Column(nullable = false, unique = true, length = 120)
	private String serialNo;

	@Column(nullable = false, unique = true, length = 255)
	private String qrValue;

	@Column(nullable = false, length = 30)
	private String currentStatus = "SEMI_RECEIVED";

	@Column(nullable = false)
	private Instant createdAt;

	@Column(nullable = false)
	private Instant updatedAt;

	protected ProductUnitEntity() {
	}

	public ProductUnitEntity(ProductModelEntity model, BomVersionEntity bomVersion, ProductReceiptEntity receipt, String serialNo, String qrValue) {
		this.model = model;
		this.bomVersion = bomVersion;
		this.receipt = receipt;
		this.serialNo = serialNo;
		this.qrValue = qrValue;
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

	public BomVersionEntity getBomVersion() {
		return bomVersion;
	}

	public ProductReceiptEntity getReceipt() {
		return receipt;
	}

	public String getSerialNo() {
		return serialNo;
	}

	public String getQrValue() {
		return qrValue;
	}

	public String getCurrentStatus() {
		return currentStatus;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}

	public void setCurrentStatus(String currentStatus) {
		this.currentStatus = currentStatus;
	}

	public void setSerialNo(String serialNo) {
		this.serialNo = serialNo;
	}
}
