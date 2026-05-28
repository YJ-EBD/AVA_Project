package com.ava.backend.avastock.entity;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(name = "ava_stock_product_receipts")
public class ProductReceiptEntity {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@Column(length = 150)
	private String supplierName;

	@Column(nullable = false)
	private LocalDate receivedDate = LocalDate.now();

	@Column(columnDefinition = "text")
	private String memo;

	private UUID createdBy;

	@Column(nullable = false)
	private Instant createdAt;

	protected ProductReceiptEntity() {
	}

	public ProductReceiptEntity(String supplierName, String memo, UUID createdBy) {
		this.supplierName = supplierName;
		this.memo = memo;
		this.createdBy = createdBy;
	}

	@PrePersist
	void prePersist() {
		createdAt = Instant.now();
	}

	public Long getId() {
		return id;
	}
}
