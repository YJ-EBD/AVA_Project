package com.ava.backend.avastock.entity;

import java.time.Instant;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(name = "ava_stock_destinations")
public class DestinationEntity {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@Column(nullable = false, unique = true, length = 150)
	private String destinationName;

	@Column(length = 80)
	private String country;

	@Column(length = 80)
	private String city;

	@Column(columnDefinition = "text")
	private String address;

	@Column(length = 100)
	private String contactName;

	@Column(length = 50)
	private String contactPhone;

	@Column(nullable = false)
	private boolean active = true;

	@Column(nullable = false)
	private Instant createdAt;

	protected DestinationEntity() {
	}

	public DestinationEntity(String destinationName) {
		this.destinationName = destinationName;
	}

	@PrePersist
	void prePersist() {
		createdAt = Instant.now();
	}

	public Long getId() {
		return id;
	}

	public String getDestinationName() {
		return destinationName;
	}
}
