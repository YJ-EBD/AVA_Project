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
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(
	name = "ava_stock_bom_items",
	uniqueConstraints = {
		@UniqueConstraint(columnNames = {"bom_version_id", "part_id"}),
		@UniqueConstraint(columnNames = {"bom_version_id", "sort_order"})
	}
)
public class BomItemEntity {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "bom_version_id", nullable = false)
	private BomVersionEntity bomVersion;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "model_id", nullable = false)
	private ProductModelEntity model;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "part_id", nullable = false)
	private PartEntity part;

	@Column(length = 150)
	private String itemLabel;

	@Column(nullable = false)
	private int defaultQty = 1;

	@Column(nullable = false)
	private int sortOrder = 1;

	@Column(nullable = false)
	private boolean requiredFlag = false;

	@Column(nullable = false)
	private boolean active = true;

	@Column(nullable = false)
	private Instant createdAt;

	@Column(nullable = false)
	private Instant updatedAt;

	protected BomItemEntity() {
	}

	public BomItemEntity(BomVersionEntity bomVersion, ProductModelEntity model, PartEntity part, int sortOrder) {
		this.bomVersion = bomVersion;
		this.model = model;
		this.part = part;
		this.sortOrder = sortOrder;
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

	public BomVersionEntity getBomVersion() {
		return bomVersion;
	}

	public ProductModelEntity getModel() {
		return model;
	}

	public PartEntity getPart() {
		return part;
	}

	public String getItemLabel() {
		return itemLabel;
	}

	public int getDefaultQty() {
		return defaultQty;
	}

	public int getSortOrder() {
		return sortOrder;
	}

	public boolean isRequiredFlag() {
		return requiredFlag;
	}

	public boolean isActive() {
		return active;
	}

	public void setItemLabel(String itemLabel) {
		this.itemLabel = itemLabel;
	}

	public void setDefaultQty(int defaultQty) {
		this.defaultQty = defaultQty;
	}

	public void setSortOrder(int sortOrder) {
		this.sortOrder = sortOrder;
	}

	public void setRequiredFlag(boolean requiredFlag) {
		this.requiredFlag = requiredFlag;
	}

	public void setActive(boolean active) {
		this.active = active;
	}
}
