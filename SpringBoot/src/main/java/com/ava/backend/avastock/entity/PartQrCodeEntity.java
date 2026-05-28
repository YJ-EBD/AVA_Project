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

@Entity
@Table(name = "ava_stock_part_qr_codes")
public class PartQrCodeEntity {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "part_id", nullable = false)
	private PartEntity part;

	@Column(nullable = false, unique = true, length = 255)
	private String qrValue;

	@Column(length = 150)
	private String label;

	@Column(length = 80)
	private String locationCode;

	@Column(nullable = false)
	private boolean active = true;

	@Column(nullable = false)
	private Instant createdAt;

	protected PartQrCodeEntity() {
	}

	public PartQrCodeEntity(PartEntity part, String qrValue, String label) {
		this.part = part;
		this.qrValue = qrValue;
		this.label = label;
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

	public String getQrValue() {
		return qrValue;
	}

	public String getLabel() {
		return label;
	}

	public String getLocationCode() {
		return locationCode;
	}

	public boolean isActive() {
		return active;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}

	public void setLocationCode(String locationCode) {
		this.locationCode = locationCode;
	}

	public void setActive(boolean active) {
		this.active = active;
	}
}
