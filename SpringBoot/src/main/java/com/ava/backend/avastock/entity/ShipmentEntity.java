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
@Table(name = "ava_stock_shipments")
public class ShipmentEntity {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "destination_id", nullable = false)
	private DestinationEntity destination;

	@Column(nullable = false, length = 30)
	private String shipmentType = "OUTBOUND";

	@Column(nullable = false, length = 200)
	private String shippingMethod;

	@Column(nullable = false)
	private LocalDate shippingDate;

	@Column(nullable = false, length = 30)
	private String shipmentStatus = "IN_TRANSIT";

	@Column(length = 120)
	private String trackingNo;

	@Column(columnDefinition = "text")
	private String memo;

	private UUID createdBy;

	@Column(nullable = false)
	private Instant createdAt;

	protected ShipmentEntity() {
	}

	public ShipmentEntity(DestinationEntity destination, String shippingMethod, LocalDate shippingDate, String shipmentStatus, UUID createdBy) {
		this.destination = destination;
		this.shippingMethod = shippingMethod;
		this.shippingDate = shippingDate;
		this.shipmentStatus = shipmentStatus;
		this.createdBy = createdBy;
	}

	@PrePersist
	void prePersist() {
		createdAt = Instant.now();
	}

	public Long getId() {
		return id;
	}

	public DestinationEntity getDestination() {
		return destination;
	}

	public String getShippingMethod() {
		return shippingMethod;
	}

	public LocalDate getShippingDate() {
		return shippingDate;
	}

	public String getShipmentStatus() {
		return shipmentStatus;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}
}
