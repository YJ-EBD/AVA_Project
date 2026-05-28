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
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(
	name = "ava_stock_operation_check_items",
	uniqueConstraints = @UniqueConstraint(columnNames = {"operation_id", "bom_item_id"})
)
public class OperationCheckItemEntity {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "operation_id", nullable = false)
	private ProductOperationEntity operation;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "bom_version_id", nullable = false)
	private BomVersionEntity bomVersion;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "bom_item_id", nullable = false)
	private BomItemEntity bomItem;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "part_id", nullable = false)
	private PartEntity part;

	@Column(nullable = false, length = 20)
	private String checkStatus = "PENDING";

	@Column(nullable = false)
	private int qtyUsed = 0;

	private Instant checkedAt;

	private UUID checkedBy;

	@Column(columnDefinition = "text")
	private String memo;

	protected OperationCheckItemEntity() {
	}

	public OperationCheckItemEntity(ProductOperationEntity operation, BomItemEntity bomItem) {
		this.operation = operation;
		this.bomVersion = operation.getBomVersion();
		this.bomItem = bomItem;
		this.part = bomItem.getPart();
	}

	public Long getId() {
		return id;
	}

	public ProductOperationEntity getOperation() {
		return operation;
	}

	public BomItemEntity getBomItem() {
		return bomItem;
	}

	public PartEntity getPart() {
		return part;
	}

	public String getCheckStatus() {
		return checkStatus;
	}

	public int getQtyUsed() {
		return qtyUsed;
	}

	public String getMemo() {
		return memo;
	}

	public void setState(String checkStatus, int qtyUsed, UUID checkedBy, String memo) {
		this.checkStatus = checkStatus;
		this.qtyUsed = qtyUsed;
		this.checkedBy = checkedBy;
		this.memo = memo;
		this.checkedAt = "USED".equals(checkStatus) ? Instant.now() : null;
	}
}
