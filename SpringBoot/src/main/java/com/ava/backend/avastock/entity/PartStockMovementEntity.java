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
@Table(name = "ava_stock_part_stock_movements")
public class PartStockMovementEntity {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "part_id", nullable = false)
	private PartEntity part;

	@ManyToOne(fetch = FetchType.LAZY)
	@JoinColumn(name = "part_qr_id")
	private PartQrCodeEntity partQr;

	@ManyToOne(fetch = FetchType.LAZY)
	@JoinColumn(name = "product_unit_id")
	private ProductUnitEntity productUnit;

	@ManyToOne(fetch = FetchType.LAZY)
	@JoinColumn(name = "service_case_id")
	private ServiceCaseEntity serviceCase;

	@ManyToOne(fetch = FetchType.LAZY)
	@JoinColumn(name = "operation_id")
	private ProductOperationEntity operation;

	@ManyToOne(fetch = FetchType.LAZY)
	@JoinColumn(name = "check_item_id")
	private OperationCheckItemEntity checkItem;

	@Column(nullable = false, length = 30)
	private String movementType;

	@Column(nullable = false)
	private int qtyDelta;

	@Column(columnDefinition = "text")
	private String memo;

	private UUID createdBy;

	@Column(nullable = false)
	private Instant createdAt;

	protected PartStockMovementEntity() {
	}

	public PartStockMovementEntity(PartEntity part, String movementType, int qtyDelta, String memo, UUID createdBy) {
		this.part = part;
		this.movementType = movementType;
		this.qtyDelta = qtyDelta;
		this.memo = memo;
		this.createdBy = createdBy;
	}

	public static PartStockMovementEntity forCheckItem(OperationCheckItemEntity checkItem, String movementType, int qtyDelta, String memo, UUID createdBy) {
		var movement = new PartStockMovementEntity(checkItem.getPart(), movementType, qtyDelta, memo, createdBy);
		movement.productUnit = checkItem.getOperation().getProductUnit();
		movement.serviceCase = checkItem.getOperation().getServiceCase();
		movement.operation = checkItem.getOperation();
		movement.checkItem = checkItem;
		return movement;
	}

	public void setPartQr(PartQrCodeEntity partQr) {
		this.partQr = partQr;
	}

	@PrePersist
	void prePersist() {
		createdAt = Instant.now();
	}

	public Long getId() {
		return id;
	}

	public PartEntity getPart() {
		return part;
	}

	public ProductUnitEntity getProductUnit() {
		return productUnit;
	}

	public ServiceCaseEntity getServiceCase() {
		return serviceCase;
	}

	public ProductOperationEntity getOperation() {
		return operation;
	}

	public OperationCheckItemEntity getCheckItem() {
		return checkItem;
	}

	public String getMovementType() {
		return movementType;
	}

	public int getQtyDelta() {
		return qtyDelta;
	}

	public String getMemo() {
		return memo;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}
}
