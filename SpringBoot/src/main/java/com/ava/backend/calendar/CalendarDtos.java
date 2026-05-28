package com.ava.backend.calendar;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public final class CalendarDtos {
	private CalendarDtos() {
	}

	public record EventRequest(
		@NotBlank @Size(max = 200) String title,
		@Size(max = 4000) String description,
		@NotNull Instant startAt,
		@NotNull Instant endAt,
		Boolean allDay,
		@Size(max = 240) String location,
		UUID categoryId,
		@Size(max = 30) String color,
		CalendarEventStatus status,
		CalendarMeetingStatus meetingStatus,
		CalendarVisibility visibility,
		CalendarDetailVisibility detailVisibility,
		@Size(max = 3000) String memo,
		@Size(max = 160) String projectName,
		@Valid List<AttendeeRequest> attendees,
		@Valid List<ReminderRequest> reminders,
		@Valid RecurrenceRequest recurrence,
		@Valid List<FileLinkRequest> files,
		@Valid List<NotionLinkRequest> notionLinks,
		@Valid List<ChatLinkRequest> chatLinks,
		@Valid List<AzoomLinkRequest> azoomLinks,
		Boolean ignoreConflicts,
		String source
	) {
	}

	public record EventPatchRequest(
		@NotBlank @Size(max = 200) String title,
		@Size(max = 4000) String description,
		@NotNull Instant startAt,
		@NotNull Instant endAt,
		Boolean allDay,
		@Size(max = 240) String location,
		UUID categoryId,
		@Size(max = 30) String color,
		CalendarEventStatus status,
		CalendarMeetingStatus meetingStatus,
		CalendarVisibility visibility,
		CalendarDetailVisibility detailVisibility,
		@Size(max = 3000) String memo,
		@Size(max = 160) String projectName,
		@Valid List<AttendeeRequest> attendees,
		@Valid List<ReminderRequest> reminders,
		@Valid RecurrenceRequest recurrence,
		@Valid List<FileLinkRequest> files,
		@Valid List<NotionLinkRequest> notionLinks,
		@Valid List<ChatLinkRequest> chatLinks,
		@Valid List<AzoomLinkRequest> azoomLinks,
		Boolean ignoreConflicts,
		String recurrenceEditScope,
		String source
	) {
		EventRequest toEventRequest() {
			return new EventRequest(
				title,
				description,
				startAt,
				endAt,
				allDay,
				location,
				categoryId,
				color,
				status,
				meetingStatus,
				visibility,
				detailVisibility,
				memo,
				projectName,
				attendees,
				reminders,
				recurrence,
				files,
				notionLinks,
				chatLinks,
				azoomLinks,
				ignoreConflicts,
				source
			);
		}
	}

	public record EventResponse(
		UUID id,
		String title,
		String description,
		Instant startAt,
		Instant endAt,
		Instant occurrenceStartAt,
		Instant occurrenceEndAt,
		boolean allDay,
		String location,
		UUID categoryId,
		CategoryResponse category,
		String color,
		CalendarEventStatus status,
		CalendarMeetingStatus meetingStatus,
		CalendarVisibility visibility,
		CalendarDetailVisibility detailVisibility,
		UUID ownerUserId,
		UUID createdBy,
		UUID updatedBy,
		String memo,
		String projectName,
		List<AttendeeResponse> attendees,
		List<ReminderResponse> reminders,
		RecurrenceResponse recurrence,
		List<FileLinkResponse> files,
		List<NotionLinkResponse> notionLinks,
		List<ChatLinkResponse> chatLinks,
		List<AzoomLinkResponse> azoomLinks,
		Instant createdAt,
		Instant updatedAt
	) {
	}

	public record CategoryRequest(
		@NotBlank @Size(max = 80) String name,
		@Size(max = 30) String color,
		@Size(max = 60) String icon,
		CalendarCategoryScope scope,
		Integer sortOrder
	) {
	}

	public record CategoryResponse(
		UUID id,
		String name,
		String color,
		String icon,
		CalendarCategoryScope scope,
		UUID ownerUserId,
		boolean defaultCategory,
		int sortOrder
	) {
	}

	public record AttendeeRequest(
		UUID userId,
		@NotBlank @Size(max = 120) String displayName,
		@Size(max = 120) String department,
		@Size(max = 120) String position,
		@Size(max = 160) String email,
		CalendarAttendeeStatus responseStatus,
		@Size(max = 500) String responseMessage,
		Instant respondedAt
	) {
	}

	public record AttendeeResponse(UUID id, UUID userId, String displayName, String department, String position, String email, CalendarAttendeeStatus responseStatus, String responseMessage, Instant respondedAt, Instant createdAt) {
	}

	public record ReminderRequest(
		@NotNull Integer remindBeforeMinutes,
		CalendarReminderType reminderType,
		CalendarReminderTargetType targetType,
		@Size(max = 120) String targetId
	) {
	}

	public record ReminderResponse(UUID id, int remindBeforeMinutes, CalendarReminderType reminderType, CalendarReminderTargetType targetType, String targetId, boolean sent, Instant sentAt, Instant createdAt) {
	}

	public record RecurrenceRequest(
		CalendarRecurrenceType recurrenceType,
		Integer intervalValue,
		@Size(max = 40) String daysOfWeek,
		Integer dayOfMonth,
		CalendarRecurrenceEndType endType,
		LocalDate untilDate,
		Integer occurrenceCount,
		@Size(max = 1000) String rrule,
		@Size(max = 80) String timezone
	) {
	}

	public record RecurrenceResponse(UUID id, CalendarRecurrenceType recurrenceType, int intervalValue, String daysOfWeek, Integer dayOfMonth, CalendarRecurrenceEndType endType, LocalDate untilDate, Integer occurrenceCount, String rrule, String timezone) {
	}

	public record FileLinkRequest(String fileId, @NotBlank @Size(max = 240) String fileName, @Size(max = 800) String filePath, @Size(max = 80) String fileType, Long fileSize, CalendarFileSourceType sourceType) {
	}
	public record FileLinkResponse(UUID id, String fileId, String fileName, String filePath, String fileType, Long fileSize, CalendarFileSourceType sourceType, Instant linkedAt) {
	}
	public record NotionLinkRequest(@Size(max = 160) String notionPageId, @Size(max = 160) String notionDatabaseId, @NotBlank @Size(max = 240) String notionTitle, @Size(max = 1000) String notionUrl) {
	}
	public record NotionLinkResponse(UUID id, String notionPageId, String notionDatabaseId, String notionTitle, String notionUrl, Instant linkedAt) {
	}
	public record ChatLinkRequest(@NotBlank @Size(max = 120) String chatRoomId, @Size(max = 160) String chatRoomName, @Size(max = 120) String sourceMessageId, @Size(max = 1000) String sourceMessagePreview) {
	}
	public record ChatLinkResponse(UUID id, String chatRoomId, String chatRoomName, String sourceMessageId, String sourceMessagePreview, Instant linkedAt) {
	}
	public record AzoomLinkRequest(@Size(max = 160) String azoomMeetingId, @Size(max = 160) String azoomRoomId, @Size(max = 1000) String azoomJoinUrl, @Size(max = 160) String azoomRecordingId, @Size(max = 160) String azoomTranscriptId, @Size(max = 160) String azoomMinutesId) {
	}
	public record AzoomLinkResponse(UUID id, String azoomMeetingId, String azoomRoomId, String azoomJoinUrl, String azoomRecordingId, String azoomTranscriptId, String azoomMinutesId, Instant linkedAt) {
	}

	public record ConflictCheckRequest(
		@NotNull Instant startAt,
		@NotNull Instant endAt,
		List<UUID> attendeeUserIds,
		UUID excludeEventId,
		@Size(max = 240) String location,
		@Size(max = 160) String azoomRoomId
	) {
	}

	public record ConflictResponse(UUID eventId, String title, Instant startAt, Instant endAt, String reason, String ownerName) {
	}

	public record ConflictCheckResponse(boolean hasConflicts, List<ConflictResponse> conflicts) {
	}

	public record AvailabilityRequest(
		List<UUID> attendeeUserIds,
		@NotNull Instant rangeStart,
		@NotNull Instant rangeEnd,
		Integer durationMinutes,
		String workdayStart,
		String workdayEnd,
		List<TimeRangeRequest> excludedTimes
	) {
	}

	public record TimeRangeRequest(Instant startAt, Instant endAt) {
	}

	public record AvailabilitySuggestion(Instant startAt, Instant endAt, int score, List<ConflictResponse> attendeeConflicts) {
	}

	public record CalendarSummaryResponse(String title, Instant rangeStart, Instant rangeEnd, long totalCount, List<EventResponse> events, Map<String, Long> countsByStatus) {
	}
}
