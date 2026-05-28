package com.ava.backend.calendar;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(name = "calendar_event_attendees")
class CalendarEventAttendeeEntity {
	@Id private UUID id;
	@Column(name = "event_id", nullable = false) private UUID eventId;
	@Column(name = "user_id") private UUID userId;
	@Column(name = "display_name", nullable = false, length = 120) private String displayName;
	@Column(length = 120) private String department;
	@Column(length = 120) private String position;
	@Column(length = 160) private String email;
	@Enumerated(EnumType.STRING) @Column(name = "response_status", nullable = false, length = 30) private CalendarAttendeeStatus responseStatus = CalendarAttendeeStatus.PENDING;
	@Column(name = "response_message", length = 500) private String responseMessage;
	@Column(name = "responded_at") private Instant respondedAt;
	@Column(name = "created_at", nullable = false) private Instant createdAt;
	protected CalendarEventAttendeeEntity() {}
	CalendarEventAttendeeEntity(UUID eventId, CalendarDtos.AttendeeRequest request) { this.id = UUID.randomUUID(); this.eventId = eventId; apply(request); }
	@PrePersist void prePersist() { if (id == null) id = UUID.randomUUID(); if (createdAt == null) createdAt = Instant.now(); }
	void apply(CalendarDtos.AttendeeRequest request) { this.userId = request.userId(); this.displayName = request.displayName().trim(); this.department = request.department(); this.position = request.position(); this.email = request.email(); this.responseStatus = request.responseStatus() == null ? CalendarAttendeeStatus.PENDING : request.responseStatus(); this.responseMessage = request.responseMessage(); this.respondedAt = request.respondedAt(); }
	UUID getId() { return id; } UUID getEventId() { return eventId; } UUID getUserId() { return userId; } String getDisplayName() { return displayName; } String getDepartment() { return department; } String getPosition() { return position; } String getEmail() { return email; } CalendarAttendeeStatus getResponseStatus() { return responseStatus; } String getResponseMessage() { return responseMessage; } Instant getRespondedAt() { return respondedAt; } Instant getCreatedAt() { return createdAt; }
}

@Entity
@Table(name = "calendar_event_reminders")
class CalendarEventReminderEntity {
	@Id private UUID id;
	@Column(name = "event_id", nullable = false) private UUID eventId;
	@Column(name = "remind_before_minutes", nullable = false) private int remindBeforeMinutes;
	@Enumerated(EnumType.STRING) @Column(name = "reminder_type", nullable = false, length = 30) private CalendarReminderType reminderType = CalendarReminderType.IN_APP;
	@Enumerated(EnumType.STRING) @Column(name = "target_type", nullable = false, length = 30) private CalendarReminderTargetType targetType = CalendarReminderTargetType.OWNER;
	@Column(name = "target_id", length = 120) private String targetId;
	@Column(name = "is_sent", nullable = false) private boolean sent;
	@Column(name = "sent_at") private Instant sentAt;
	@Column(name = "created_at", nullable = false) private Instant createdAt;
	protected CalendarEventReminderEntity() {}
	CalendarEventReminderEntity(UUID eventId, CalendarDtos.ReminderRequest request) { this.id = UUID.randomUUID(); this.eventId = eventId; apply(request); }
	@PrePersist void prePersist() { if (id == null) id = UUID.randomUUID(); if (createdAt == null) createdAt = Instant.now(); }
	void apply(CalendarDtos.ReminderRequest request) { this.remindBeforeMinutes = request.remindBeforeMinutes(); this.reminderType = request.reminderType() == null ? CalendarReminderType.IN_APP : request.reminderType(); this.targetType = request.targetType() == null ? CalendarReminderTargetType.OWNER : request.targetType(); this.targetId = request.targetId(); }
	UUID getId() { return id; } UUID getEventId() { return eventId; } int getRemindBeforeMinutes() { return remindBeforeMinutes; } CalendarReminderType getReminderType() { return reminderType; } CalendarReminderTargetType getTargetType() { return targetType; } String getTargetId() { return targetId; } boolean isSent() { return sent; } Instant getSentAt() { return sentAt; } Instant getCreatedAt() { return createdAt; }
}

@Entity
@Table(name = "calendar_event_recurrences")
class CalendarEventRecurrenceEntity {
	@Id private UUID id;
	@Column(name = "event_id", nullable = false, unique = true) private UUID eventId;
	@Enumerated(EnumType.STRING) @Column(name = "recurrence_type", nullable = false, length = 30) private CalendarRecurrenceType recurrenceType = CalendarRecurrenceType.NONE;
	@Column(name = "interval_value", nullable = false) private int intervalValue = 1;
	@Column(name = "days_of_week", length = 40) private String daysOfWeek;
	@Column(name = "day_of_month") private Integer dayOfMonth;
	@Enumerated(EnumType.STRING) @Column(name = "end_type", nullable = false, length = 30) private CalendarRecurrenceEndType endType = CalendarRecurrenceEndType.NEVER;
	@Column(name = "until_date") private LocalDate untilDate;
	@Column(name = "occurrence_count") private Integer occurrenceCount;
	@Column(columnDefinition = "text") private String rrule;
	@Column(nullable = false, length = 80) private String timezone = "Asia/Seoul";
	@Column(name = "created_at", nullable = false) private Instant createdAt;
	protected CalendarEventRecurrenceEntity() {}
	CalendarEventRecurrenceEntity(UUID eventId, CalendarDtos.RecurrenceRequest request) { this.id = UUID.randomUUID(); this.eventId = eventId; apply(request); }
	@PrePersist void prePersist() { if (id == null) id = UUID.randomUUID(); if (createdAt == null) createdAt = Instant.now(); }
	void apply(CalendarDtos.RecurrenceRequest request) { this.recurrenceType = request.recurrenceType() == null ? CalendarRecurrenceType.NONE : request.recurrenceType(); this.intervalValue = request.intervalValue() == null || request.intervalValue() < 1 ? 1 : request.intervalValue(); this.daysOfWeek = request.daysOfWeek(); this.dayOfMonth = request.dayOfMonth(); this.endType = request.endType() == null ? CalendarRecurrenceEndType.NEVER : request.endType(); this.untilDate = request.untilDate(); this.occurrenceCount = request.occurrenceCount(); this.rrule = request.rrule(); this.timezone = request.timezone() == null || request.timezone().isBlank() ? "Asia/Seoul" : request.timezone(); }
	UUID getId() { return id; } UUID getEventId() { return eventId; } CalendarRecurrenceType getRecurrenceType() { return recurrenceType; } int getIntervalValue() { return intervalValue; } String getDaysOfWeek() { return daysOfWeek; } Integer getDayOfMonth() { return dayOfMonth; } CalendarRecurrenceEndType getEndType() { return endType; } LocalDate getUntilDate() { return untilDate; } Integer getOccurrenceCount() { return occurrenceCount; } String getRrule() { return rrule; } String getTimezone() { return timezone; } Instant getCreatedAt() { return createdAt; }
}

@Entity
@Table(name = "calendar_event_files")
class CalendarEventFileEntity {
	@Id private UUID id; @Column(name = "event_id", nullable = false) private UUID eventId; @Column(name = "file_id", length = 120) private String fileId; @Column(name = "file_name", nullable = false, length = 240) private String fileName; @Column(name = "file_path", length = 800) private String filePath; @Column(name = "file_type", length = 80) private String fileType; @Column(name = "file_size") private Long fileSize; @Enumerated(EnumType.STRING) @Column(name = "source_type", nullable = false, length = 30) private CalendarFileSourceType sourceType = CalendarFileSourceType.NAS; @Column(name = "linked_at", nullable = false) private Instant linkedAt;
	protected CalendarEventFileEntity() {}
	CalendarEventFileEntity(UUID eventId, CalendarDtos.FileLinkRequest request) { this.id = UUID.randomUUID(); this.eventId = eventId; this.fileId = request.fileId(); this.fileName = request.fileName().trim(); this.filePath = request.filePath(); this.fileType = request.fileType(); this.fileSize = request.fileSize(); this.sourceType = request.sourceType() == null ? CalendarFileSourceType.NAS : request.sourceType(); }
	@PrePersist void prePersist() { if (id == null) id = UUID.randomUUID(); if (linkedAt == null) linkedAt = Instant.now(); }
	UUID getId() { return id; } UUID getEventId() { return eventId; } String getFileId() { return fileId; } String getFileName() { return fileName; } String getFilePath() { return filePath; } String getFileType() { return fileType; } Long getFileSize() { return fileSize; } CalendarFileSourceType getSourceType() { return sourceType; } Instant getLinkedAt() { return linkedAt; }
}

@Entity
@Table(name = "calendar_event_notion_links")
class CalendarEventNotionLinkEntity {
	@Id private UUID id; @Column(name = "event_id", nullable = false) private UUID eventId; @Column(name = "notion_page_id", length = 160) private String notionPageId; @Column(name = "notion_database_id", length = 160) private String notionDatabaseId; @Column(name = "notion_title", nullable = false, length = 240) private String notionTitle; @Column(name = "notion_url", length = 1000) private String notionUrl; @Column(name = "linked_at", nullable = false) private Instant linkedAt;
	protected CalendarEventNotionLinkEntity() {}
	CalendarEventNotionLinkEntity(UUID eventId, CalendarDtos.NotionLinkRequest request) { this.id = UUID.randomUUID(); this.eventId = eventId; this.notionPageId = request.notionPageId(); this.notionDatabaseId = request.notionDatabaseId(); this.notionTitle = request.notionTitle().trim(); this.notionUrl = request.notionUrl(); }
	@PrePersist void prePersist() { if (id == null) id = UUID.randomUUID(); if (linkedAt == null) linkedAt = Instant.now(); }
	UUID getId() { return id; } UUID getEventId() { return eventId; } String getNotionPageId() { return notionPageId; } String getNotionDatabaseId() { return notionDatabaseId; } String getNotionTitle() { return notionTitle; } String getNotionUrl() { return notionUrl; } Instant getLinkedAt() { return linkedAt; }
}

@Entity
@Table(name = "calendar_event_chat_links")
class CalendarEventChatLinkEntity {
	@Id private UUID id; @Column(name = "event_id", nullable = false) private UUID eventId; @Column(name = "chat_room_id", nullable = false, length = 120) private String chatRoomId; @Column(name = "chat_room_name", length = 160) private String chatRoomName; @Column(name = "source_message_id", length = 120) private String sourceMessageId; @Column(name = "source_message_preview", length = 1000) private String sourceMessagePreview; @Column(name = "linked_at", nullable = false) private Instant linkedAt;
	protected CalendarEventChatLinkEntity() {}
	CalendarEventChatLinkEntity(UUID eventId, CalendarDtos.ChatLinkRequest request) { this.id = UUID.randomUUID(); this.eventId = eventId; this.chatRoomId = request.chatRoomId().trim(); this.chatRoomName = request.chatRoomName(); this.sourceMessageId = request.sourceMessageId(); this.sourceMessagePreview = request.sourceMessagePreview(); }
	@PrePersist void prePersist() { if (id == null) id = UUID.randomUUID(); if (linkedAt == null) linkedAt = Instant.now(); }
	UUID getId() { return id; } UUID getEventId() { return eventId; } String getChatRoomId() { return chatRoomId; } String getChatRoomName() { return chatRoomName; } String getSourceMessageId() { return sourceMessageId; } String getSourceMessagePreview() { return sourceMessagePreview; } Instant getLinkedAt() { return linkedAt; }
}

@Entity
@Table(name = "calendar_event_azoom_links")
class CalendarEventAzoomLinkEntity {
	@Id private UUID id; @Column(name = "event_id", nullable = false) private UUID eventId; @Column(name = "azoom_meeting_id", length = 160) private String azoomMeetingId; @Column(name = "azoom_room_id", length = 160) private String azoomRoomId; @Column(name = "azoom_join_url", length = 1000) private String azoomJoinUrl; @Column(name = "azoom_recording_id", length = 160) private String azoomRecordingId; @Column(name = "azoom_transcript_id", length = 160) private String azoomTranscriptId; @Column(name = "azoom_minutes_id", length = 160) private String azoomMinutesId; @Column(name = "linked_at", nullable = false) private Instant linkedAt;
	protected CalendarEventAzoomLinkEntity() {}
	CalendarEventAzoomLinkEntity(UUID eventId, CalendarDtos.AzoomLinkRequest request) { this.id = UUID.randomUUID(); this.eventId = eventId; this.azoomMeetingId = request.azoomMeetingId(); this.azoomRoomId = request.azoomRoomId(); this.azoomJoinUrl = request.azoomJoinUrl(); this.azoomRecordingId = request.azoomRecordingId(); this.azoomTranscriptId = request.azoomTranscriptId(); this.azoomMinutesId = request.azoomMinutesId(); }
	@PrePersist void prePersist() { if (id == null) id = UUID.randomUUID(); if (linkedAt == null) linkedAt = Instant.now(); }
	UUID getId() { return id; } UUID getEventId() { return eventId; } String getAzoomMeetingId() { return azoomMeetingId; } String getAzoomRoomId() { return azoomRoomId; } String getAzoomJoinUrl() { return azoomJoinUrl; } String getAzoomRecordingId() { return azoomRecordingId; } String getAzoomTranscriptId() { return azoomTranscriptId; } String getAzoomMinutesId() { return azoomMinutesId; } Instant getLinkedAt() { return linkedAt; }
}

@Entity
@Table(name = "calendar_event_audit_logs")
class CalendarEventAuditLogEntity {
	@Id private UUID id; @Column(name = "event_id") private UUID eventId; @Column(name = "action_type", nullable = false, length = 80) private String actionType; @Column(name = "actor_user_id", nullable = false) private UUID actorUserId; @Column(name = "before_json", columnDefinition = "text") private String beforeJson; @Column(name = "after_json", columnDefinition = "text") private String afterJson; @Column(nullable = false, length = 40) private String source; @Column(name = "created_at", nullable = false) private Instant createdAt;
	protected CalendarEventAuditLogEntity() {}
	CalendarEventAuditLogEntity(UUID eventId, String actionType, UUID actorUserId, String beforeJson, String afterJson, String source) { this.id = UUID.randomUUID(); this.eventId = eventId; this.actionType = actionType; this.actorUserId = actorUserId; this.beforeJson = beforeJson; this.afterJson = afterJson; this.source = source == null || source.isBlank() ? "APP" : source; }
	@PrePersist void prePersist() { if (id == null) id = UUID.randomUUID(); if (createdAt == null) createdAt = Instant.now(); }
	UUID getId() { return id; } UUID getEventId() { return eventId; } String getActionType() { return actionType; } UUID getActorUserId() { return actorUserId; } String getBeforeJson() { return beforeJson; } String getAfterJson() { return afterJson; } String getSource() { return source; } Instant getCreatedAt() { return createdAt; }
}
