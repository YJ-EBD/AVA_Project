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
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(
	name = "ava_stock_shipment_items",
	uniqueConstraints = @UniqueConstraint(columnNames = {"shipment_id", "product_unit_id"})
)
public class ShipmentItemEntity {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "shipment_id", nullable = false)
	private ShipmentEntity shipment;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "product_unit_id", nullable = false)
	private ProductUnitEntity productUnit;

	@Column(nullable = false, length = 30)
	private String itemStatus = "INCLUDED";

	@Column(columnDefinition = "text")
	private String memo;

	@Column(nullable = false)
	private Instant createdAt;

	protected ShipmentItemEntity() {
	}

	public ShipmentItemEntity(ShipmentEntity shipment, ProductUnitEntity productUnit) {
		this.shipment = shipment;
		this.productUnit = productUnit;
	}

	@PrePersist
	void prePersist() {
		createdAt = Instant.now();
	}

	public Long getId() {
		return id;
	}

	public ShipmentEntity getShipment() {
		return shipment;
	}

	public ProductUnitEntity getProductUnit() {
		return productUnit;
	}

	public String getItemStatus() {
		return itemStatus;
	}

	public String getMemo() {
		return memo;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}
}
