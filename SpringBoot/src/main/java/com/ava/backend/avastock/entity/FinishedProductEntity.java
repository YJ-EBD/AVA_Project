package com.ava.backend.avastock.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(name = "ava_stock_finished_products")
public class FinishedProductEntity {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@OneToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "product_unit_id", nullable = false, unique = true)
	private ProductUnitEntity productUnit;

	@OneToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "manufacturing_operation_id", nullable = false, unique = true)
	private ProductOperationEntity manufacturingOperation;

	private Instant finishedAt;

	private UUID finishedBy;

	protected FinishedProductEntity() {
	}

	public FinishedProductEntity(ProductUnitEntity productUnit, ProductOperationEntity manufacturingOperation, UUID finishedBy) {
		this.productUnit = productUnit;
		this.manufacturingOperation = manufacturingOperation;
		this.finishedBy = finishedBy;
	}

	@PrePersist
	void prePersist() {
		finishedAt = Instant.now();
	}
}
