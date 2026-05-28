package com.ava.backend.calendar;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

@Entity
@Table(name = "calendar_categories")
public class CalendarCategoryEntity {

	@Id
	private UUID id;

	@Column(nullable = false, length = 80)
	private String name;

	@Column(nullable = false, length = 30)
	private String color;

	@Column(length = 60)
	private String icon;

	@Enumerated(EnumType.STRING)
	@Column(nullable = false, length = 30)
	private CalendarCategoryScope scope = CalendarCategoryScope.USER;

	@Column(name = "owner_user_id")
	private UUID ownerUserId;

	@Column(name = "is_default", nullable = false)
	private boolean defaultCategory;

	@Column(name = "sort_order", nullable = false)
	private int sortOrder;

	@Column(name = "created_at", nullable = false)
	private Instant createdAt;

	@Column(name = "updated_at", nullable = false)
	private Instant updatedAt;

	protected CalendarCategoryEntity() {
	}

	public CalendarCategoryEntity(String name, String color, String icon, CalendarCategoryScope scope, UUID ownerUserId, boolean defaultCategory, int sortOrder) {
		this.id = UUID.randomUUID();
		this.name = name;
		this.color = color;
		this.icon = icon;
		this.scope = scope;
		this.ownerUserId = ownerUserId;
		this.defaultCategory = defaultCategory;
		this.sortOrder = sortOrder;
	}

	@PrePersist
	void prePersist() {
		Instant now = Instant.now();
		if (id == null) {
			id = UUID.randomUUID();
		}
		if (createdAt == null) {
			createdAt = now;
		}
		if (updatedAt == null) {
			updatedAt = now;
		}
	}

	@PreUpdate
	void preUpdate() {
		updatedAt = Instant.now();
	}

	public UUID getId() { return id; }
	public String getName() { return name; }
	public String getColor() { return color; }
	public String getIcon() { return icon; }
	public CalendarCategoryScope getScope() { return scope; }
	public UUID getOwnerUserId() { return ownerUserId; }
	public boolean isDefaultCategory() { return defaultCategory; }
	public int getSortOrder() { return sortOrder; }
	public Instant getCreatedAt() { return createdAt; }
	public Instant getUpdatedAt() { return updatedAt; }

	public void apply(CalendarDtos.CategoryRequest request, UUID ownerUserId) {
		this.name = request.name().trim();
		this.color = request.color() == null || request.color().isBlank() ? "#4F7CFF" : request.color().trim();
		this.icon = request.icon();
		this.scope = request.scope() == null ? CalendarCategoryScope.USER : request.scope();
		this.ownerUserId = this.scope == CalendarCategoryScope.USER ? ownerUserId : null;
		this.sortOrder = request.sortOrder() == null ? sortOrder : request.sortOrder();
	}
}
