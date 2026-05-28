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
@Table(name = "ava_stock_product_status_history")
public class ProductStatusHistoryEntity {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "product_unit_id", nullable = false)
	private ProductUnitEntity productUnit;

	@Column(length = 30)
	private String fromStatus;

	@Column(nullable = false, length = 30)
	private String toStatus;

	@Column(length = 150)
	private String reason;

	@Column(length = 40)
	private String refType;

	private Long refId;

	private UUID changedBy;

	@Column(nullable = false)
	private Instant changedAt;

	protected ProductStatusHistoryEntity() {
	}

	public ProductStatusHistoryEntity(ProductUnitEntity productUnit, String fromStatus, String toStatus, String reason, String refType, Long refId, UUID changedBy) {
		this.productUnit = productUnit;
		this.fromStatus = fromStatus;
		this.toStatus = toStatus;
		this.reason = reason;
		this.refType = refType;
		this.refId = refId;
		this.changedBy = changedBy;
	}

	@PrePersist
	void prePersist() {
		changedAt = Instant.now();
	}
}
