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
@Table(name = "calendar_events")
public class CalendarEventEntity {

	@Id
	private UUID id;

	@Column(nullable = false, length = 200)
	private String title;

	@Column(columnDefinition = "text")
	private String description;

	@Column(name = "start_at", nullable = false)
	private Instant startAt;

	@Column(name = "end_at", nullable = false)
	private Instant endAt;

	@Column(name = "all_day", nullable = false)
	private boolean allDay;

	@Column(length = 240)
	private String location;

	@Column(name = "category_id")
	private UUID categoryId;

	@Column(length = 30)
	private String color;

	@Enumerated(EnumType.STRING)
	@Column(nullable = false, length = 30)
	private CalendarEventStatus status = CalendarEventStatus.SCHEDULED;

	@Enumerated(EnumType.STRING)
	@Column(name = "meeting_status", nullable = false, length = 40)
	private CalendarMeetingStatus meetingStatus = CalendarMeetingStatus.RESERVED;

	@Enumerated(EnumType.STRING)
	@Column(nullable = false, length = 30)
	private CalendarVisibility visibility = CalendarVisibility.PRIVATE;

	@Enumerated(EnumType.STRING)
	@Column(name = "detail_visibility", nullable = false, length = 30)
	private CalendarDetailVisibility detailVisibility = CalendarDetailVisibility.FULL;

	@Column(name = "owner_user_id", nullable = false)
	private UUID ownerUserId;

	@Column(name = "created_by", nullable = false)
	private UUID createdBy;

	@Column(name = "updated_by")
	private UUID updatedBy;

	@Column(columnDefinition = "text")
	private String memo;

	@Column(name = "project_name", length = 160)
	private String projectName;

	@Column(name = "team_id", length = 80)
	private String teamId;

	@Enumerated(EnumType.STRING)
	@Column(nullable = false, length = 20)
	private CalendarImportance importance = CalendarImportance.NORMAL;

	@Column(name = "created_at", nullable = false)
	private Instant createdAt;

	@Column(name = "updated_at", nullable = false)
	private Instant updatedAt;

	@Column(name = "deleted_at")
	private Instant deletedAt;

	protected CalendarEventEntity() {
	}

	public CalendarEventEntity(UUID ownerUserId, UUID actorUserId) {
		this.id = UUID.randomUUID();
		this.ownerUserId = ownerUserId;
		this.createdBy = actorUserId;
		this.updatedBy = actorUserId;
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
	public String getTitle() { return title; }
	public String getDescription() { return description; }
	public Instant getStartAt() { return startAt; }
	public Instant getEndAt() { return endAt; }
	public boolean isAllDay() { return allDay; }
	public String getLocation() { return location; }
	public UUID getCategoryId() { return categoryId; }
	public String getColor() { return color; }
	public CalendarEventStatus getStatus() { return status; }
	public CalendarMeetingStatus getMeetingStatus() { return meetingStatus; }
	public CalendarVisibility getVisibility() { return visibility; }
	public CalendarDetailVisibility getDetailVisibility() { return detailVisibility; }
	public UUID getOwnerUserId() { return ownerUserId; }
	public UUID getCreatedBy() { return createdBy; }
	public UUID getUpdatedBy() { return updatedBy; }
	public String getMemo() { return memo; }
	public String getProjectName() { return projectName; }
	public String getTeamId() { return teamId; }
	public CalendarImportance getImportance() { return importance; }
	public Instant getCreatedAt() { return createdAt; }
	public Instant getUpdatedAt() { return updatedAt; }
	public Instant getDeletedAt() { return deletedAt; }

	public void apply(CalendarDtos.EventRequest request, UUID actorUserId) {
		this.title = request.title().trim();
		this.description = blankToNull(request.description());
		this.startAt = request.startAt();
		this.endAt = request.endAt();
		this.allDay = Boolean.TRUE.equals(request.allDay());
		this.location = blankToNull(request.location());
		this.categoryId = request.categoryId();
		this.color = blankToNull(request.color());
		this.status = request.status() == null ? CalendarEventStatus.SCHEDULED : request.status();
		this.meetingStatus = request.meetingStatus() == null ? CalendarMeetingStatus.RESERVED : request.meetingStatus();
		this.visibility = request.visibility() == null ? CalendarVisibility.PRIVATE : request.visibility();
		this.detailVisibility = request.detailVisibility() == null ? CalendarDetailVisibility.FULL : request.detailVisibility();
		this.memo = blankToNull(request.memo());
		this.projectName = blankToNull(request.projectName());
		this.teamId = blankToNull(request.teamId());
		this.importance = request.importance() == null ? CalendarImportance.NORMAL : request.importance();
		this.updatedBy = actorUserId;
	}

	public void softDelete(UUID actorUserId) {
		this.deletedAt = Instant.now();
		this.updatedBy = actorUserId;
	}

	private static String blankToNull(String value) {
		return value == null || value.trim().isEmpty() ? null : value.trim();
	}
}
