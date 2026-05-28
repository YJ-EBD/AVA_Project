package com.ava.backend.calendar;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

interface CalendarEventRepository extends JpaRepository<CalendarEventEntity, UUID> {
	@Query("""
		select e from CalendarEventEntity e
		where e.deletedAt is null
		  and e.startAt < :endAt
		  and e.endAt > :startAt
		order by e.startAt asc
		""")
	List<CalendarEventEntity> findActiveInRange(@Param("startAt") Instant startAt, @Param("endAt") Instant endAt);

	@Query("""
		select e from CalendarEventEntity e
		where e.deletedAt is null
		  and (
		    lower(e.title) like lower(concat('%', :query, '%'))
		    or lower(coalesce(e.description, '')) like lower(concat('%', :query, '%'))
		    or lower(coalesce(e.location, '')) like lower(concat('%', :query, '%'))
		    or lower(coalesce(e.projectName, '')) like lower(concat('%', :query, '%'))
		  )
		order by e.startAt asc
		""")
	List<CalendarEventEntity> searchActive(@Param("query") String query);

	Optional<CalendarEventEntity> findByIdAndDeletedAtIsNull(UUID id);
	List<CalendarEventEntity> findByDeletedAtIsNullOrderByStartAtAsc();
	List<CalendarEventEntity> findByCategoryIdAndDeletedAtIsNullOrderByStartAtAsc(UUID categoryId);
}

interface CalendarCategoryRepository extends JpaRepository<CalendarCategoryEntity, UUID> {
	List<CalendarCategoryEntity> findByOwnerUserIdOrDefaultCategoryTrueOrderBySortOrderAscNameAsc(UUID ownerUserId);
	List<CalendarCategoryEntity> findByNameContainingIgnoreCase(String name);
	boolean existsByNameAndDefaultCategoryTrue(String name);
}

interface CalendarEventAttendeeRepository extends JpaRepository<CalendarEventAttendeeEntity, UUID> {
	List<CalendarEventAttendeeEntity> findByEventIdOrderByCreatedAtAsc(UUID eventId);
	List<CalendarEventAttendeeEntity> findByUserId(UUID userId);
	@Query("""
		select distinct a.eventId from CalendarEventAttendeeEntity a
		where lower(coalesce(a.displayName, '')) like lower(concat('%', :query, '%'))
		   or lower(coalesce(a.department, '')) like lower(concat('%', :query, '%'))
		   or lower(coalesce(a.position, '')) like lower(concat('%', :query, '%'))
		   or lower(coalesce(a.email, '')) like lower(concat('%', :query, '%'))
		""")
	List<UUID> searchEventIds(@Param("query") String query);
	boolean existsByEventIdAndUserId(UUID eventId, UUID userId);
	boolean existsByEventIdAndEmailIgnoreCase(UUID eventId, String email);
	void deleteByEventId(UUID eventId);
}

interface CalendarEventReminderRepository extends JpaRepository<CalendarEventReminderEntity, UUID> {
	List<CalendarEventReminderEntity> findByEventIdOrderByRemindBeforeMinutesAsc(UUID eventId);
	boolean existsByEventIdAndRemindBeforeMinutesAndReminderTypeAndTargetType(UUID eventId, int remindBeforeMinutes, CalendarReminderType reminderType, CalendarReminderTargetType targetType);
	void deleteByEventId(UUID eventId);
}

interface CalendarReminderDeliveryRepository extends JpaRepository<CalendarReminderDeliveryEntity, UUID> {
	boolean existsByEventIdAndOccurrenceStartAtAndTargetUserIdAndRemindBeforeMinutesAndReminderType(
		UUID eventId,
		Instant occurrenceStartAt,
		UUID targetUserId,
		int remindBeforeMinutes,
		CalendarReminderType reminderType
	);
}

interface CalendarEventRecurrenceRepository extends JpaRepository<CalendarEventRecurrenceEntity, UUID> {
	Optional<CalendarEventRecurrenceEntity> findByEventId(UUID eventId);
	void deleteByEventId(UUID eventId);
}

interface CalendarEventFileRepository extends JpaRepository<CalendarEventFileEntity, UUID> {
	List<CalendarEventFileEntity> findByEventIdOrderByLinkedAtAsc(UUID eventId);
	@Query("""
		select distinct f.eventId from CalendarEventFileEntity f
		where lower(coalesce(f.fileName, '')) like lower(concat('%', :query, '%'))
		   or lower(coalesce(f.filePath, '')) like lower(concat('%', :query, '%'))
		   or lower(coalesce(f.fileType, '')) like lower(concat('%', :query, '%'))
		""")
	List<UUID> searchEventIds(@Param("query") String query);
	void deleteByEventId(UUID eventId);
}

interface CalendarEventNotionLinkRepository extends JpaRepository<CalendarEventNotionLinkEntity, UUID> {
	List<CalendarEventNotionLinkEntity> findByEventIdOrderByLinkedAtAsc(UUID eventId);
	@Query("""
		select distinct n.eventId from CalendarEventNotionLinkEntity n
		where lower(coalesce(n.notionTitle, '')) like lower(concat('%', :query, '%'))
		   or lower(coalesce(n.notionUrl, '')) like lower(concat('%', :query, '%'))
		   or lower(coalesce(n.notionPageId, '')) like lower(concat('%', :query, '%'))
		   or lower(coalesce(n.notionDatabaseId, '')) like lower(concat('%', :query, '%'))
		""")
	List<UUID> searchEventIds(@Param("query") String query);
	void deleteByEventId(UUID eventId);
}

interface CalendarEventChatLinkRepository extends JpaRepository<CalendarEventChatLinkEntity, UUID> {
	List<CalendarEventChatLinkEntity> findByEventIdOrderByLinkedAtAsc(UUID eventId);
	@Query("""
		select distinct c.eventId from CalendarEventChatLinkEntity c
		where lower(coalesce(c.chatRoomId, '')) like lower(concat('%', :query, '%'))
		   or lower(coalesce(c.chatRoomName, '')) like lower(concat('%', :query, '%'))
		   or lower(coalesce(c.sourceMessageId, '')) like lower(concat('%', :query, '%'))
		   or lower(coalesce(c.sourceMessagePreview, '')) like lower(concat('%', :query, '%'))
		""")
	List<UUID> searchEventIds(@Param("query") String query);
	void deleteByEventId(UUID eventId);
}

interface CalendarEventAzoomLinkRepository extends JpaRepository<CalendarEventAzoomLinkEntity, UUID> {
	List<CalendarEventAzoomLinkEntity> findByEventIdOrderByLinkedAtAsc(UUID eventId);
	@Query("""
		select distinct z.eventId from CalendarEventAzoomLinkEntity z
		where lower(coalesce(z.azoomMeetingId, '')) like lower(concat('%', :query, '%'))
		   or lower(coalesce(z.azoomRoomId, '')) like lower(concat('%', :query, '%'))
		   or lower(coalesce(z.azoomJoinUrl, '')) like lower(concat('%', :query, '%'))
		   or lower(coalesce(z.azoomRecordingId, '')) like lower(concat('%', :query, '%'))
		   or lower(coalesce(z.azoomTranscriptId, '')) like lower(concat('%', :query, '%'))
		   or lower(coalesce(z.azoomMinutesId, '')) like lower(concat('%', :query, '%'))
		""")
	List<UUID> searchEventIds(@Param("query") String query);
	void deleteByEventId(UUID eventId);
}

interface CalendarEventAuditLogRepository extends JpaRepository<CalendarEventAuditLogEntity, UUID> {
	List<CalendarEventAuditLogEntity> findTop100ByEventIdOrderByCreatedAtDesc(UUID eventId);
}
