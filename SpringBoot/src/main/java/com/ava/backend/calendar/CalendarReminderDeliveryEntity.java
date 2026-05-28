package com.ava.backend.calendar;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(
	name = "calendar_reminder_deliveries",
	uniqueConstraints = @UniqueConstraint(
		name = "uq_calendar_reminder_delivery",
		columnNames = {"event_id", "occurrence_start_at", "target_user_id", "remind_before_minutes", "reminder_type"}
	)
)
class CalendarReminderDeliveryEntity {
	@Id
	private UUID id;

	@Column(name = "event_id", nullable = false)
	private UUID eventId;

	@Column(name = "reminder_id")
	private UUID reminderId;

	@Column(name = "occurrence_start_at", nullable = false)
	private Instant occurrenceStartAt;

	@Column(name = "target_user_id", nullable = false)
	private UUID targetUserId;

	@Column(name = "remind_before_minutes", nullable = false)
	private int remindBeforeMinutes;

	@Enumerated(EnumType.STRING)
	@Column(name = "reminder_type", nullable = false, length = 30)
	private CalendarReminderType reminderType;

	@Column(name = "delivered_at", nullable = false)
	private Instant deliveredAt;

	protected CalendarReminderDeliveryEntity() {
	}

	CalendarReminderDeliveryEntity(
		UUID eventId,
		UUID reminderId,
		Instant occurrenceStartAt,
		UUID targetUserId,
		int remindBeforeMinutes,
		CalendarReminderType reminderType,
		Instant deliveredAt
	) {
		this.id = UUID.randomUUID();
		this.eventId = eventId;
		this.reminderId = reminderId;
		this.occurrenceStartAt = occurrenceStartAt;
		this.targetUserId = targetUserId;
		this.remindBeforeMinutes = remindBeforeMinutes;
		this.reminderType = reminderType == null ? CalendarReminderType.IN_APP : reminderType;
		this.deliveredAt = deliveredAt == null ? Instant.now() : deliveredAt;
	}

	@PrePersist
	void prePersist() {
		if (id == null) {
			id = UUID.randomUUID();
		}
		if (deliveredAt == null) {
			deliveredAt = Instant.now();
		}
	}
}
