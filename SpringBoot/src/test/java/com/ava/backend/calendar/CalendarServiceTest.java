package com.ava.backend.calendar;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.context.annotation.Import;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.test.context.TestPropertySource;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.user.entity.UserRole;
import com.fasterxml.jackson.databind.ObjectMapper;

@DataJpaTest
@Import({CalendarService.class, NoopCalendarNotificationService.class, ObjectMapper.class})
@TestPropertySource(properties = {
	"spring.flyway.enabled=false",
	"spring.jpa.hibernate.ddl-auto=create-drop"
})
class CalendarServiceTest {
	private final AuthPrincipal owner = new AuthPrincipal(
		UUID.fromString("00000000-0000-0000-0000-000000000001"),
		"owner@abba-s.local",
		"Owner",
		UserRole.USER,
		"session"
	);
	private final AuthPrincipal other = new AuthPrincipal(
		UUID.fromString("00000000-0000-0000-0000-000000000002"),
		"other@abba-s.local",
		"Other",
		UserRole.USER,
		"session"
	);

	@Autowired
	CalendarService calendarService;

	@Test
	void createsReadsUpdatesAndDeletesEvent() {
		Instant start = Instant.parse("2026-06-01T01:00:00Z");
		CalendarDtos.EventResponse created = calendarService.create(request("캘린더 회의", start, start.plus(1, ChronoUnit.HOURS)), owner);

		assertEquals("캘린더 회의", calendarService.event(created.id(), owner).title());

		CalendarDtos.EventResponse updated = calendarService.update(
			created.id(),
			new CalendarDtos.EventPatchRequest(
				"수정된 회의",
				"설명",
				start.plus(1, ChronoUnit.HOURS),
				start.plus(2, ChronoUnit.HOURS),
				false,
				"회의실 A",
				created.categoryId(),
				"#2563EB",
				CalendarEventStatus.IN_PROGRESS,
				CalendarMeetingStatus.BEFORE_START,
				CalendarVisibility.PRIVATE,
				CalendarDetailVisibility.FULL,
				"메모",
				null,
				null,
				CalendarImportance.NORMAL,
				null,
				null,
				null,
				null,
				null,
				null,
				null,
				true,
				null,
				"APP"
			),
			owner
		);

		assertEquals("수정된 회의", updated.title());
		calendarService.delete(created.id(), "ALL", owner);
		assertThrows(IllegalArgumentException.class, () -> calendarService.event(created.id(), owner));
	}

	@Test
	void validatesTitleAndTime() {
		Instant start = Instant.parse("2026-06-01T01:00:00Z");

		assertThrows(IllegalArgumentException.class, () ->
			calendarService.create(request("", start, start.plus(1, ChronoUnit.HOURS)), owner));
		assertThrows(IllegalArgumentException.class, () ->
			calendarService.create(request("역전 일정", start, start.minus(1, ChronoUnit.HOURS)), owner));
	}

	@Test
	void detectsConflictsAndSuggestsAvailability() {
		Instant start = Instant.parse("2026-06-02T01:00:00Z");
		calendarService.create(request("겹치는 일정", start, start.plus(1, ChronoUnit.HOURS)), owner);

		CalendarDtos.ConflictCheckResponse conflicts = calendarService.checkConflicts(
			new CalendarDtos.ConflictCheckRequest(start.plus(10, ChronoUnit.MINUTES), start.plus(40, ChronoUnit.MINUTES), List.of(owner.userId()), null, null, null),
			owner
		);

		assertTrue(conflicts.hasConflicts());
		assertFalse(calendarService.suggestAvailability(new CalendarDtos.AvailabilityRequest(
			List.of(owner.userId()),
			Instant.parse("2026-06-02T00:00:00Z"),
			Instant.parse("2026-06-02T09:00:00Z"),
			30,
			"09:00",
			"18:00",
			List.of()
		), owner).isEmpty());
	}

	@Test
	void createsRecurrenceAttendeeReminderAndBlocksUnauthorizedPrivateRead() {
		Instant start = Instant.parse("2026-06-03T01:00:00Z");
		CalendarDtos.EventResponse created = calendarService.create(new CalendarDtos.EventRequest(
			"반복 일정",
			null,
			start,
			start.plus(30, ChronoUnit.MINUTES),
			false,
			null,
			null,
			null,
			CalendarEventStatus.SCHEDULED,
			CalendarMeetingStatus.RESERVED,
			CalendarVisibility.PRIVATE,
			CalendarDetailVisibility.FULL,
			null,
			null,
			"development",
			CalendarImportance.HIGH,
			List.of(new CalendarDtos.AttendeeRequest(other.userId(), "Other", "연구소", "팀원", "other@abba-s.local", CalendarAttendeeStatus.PENDING, null, null)),
			List.of(new CalendarDtos.ReminderRequest(30, CalendarReminderType.IN_APP, CalendarReminderTargetType.OWNER, null)),
			new CalendarDtos.RecurrenceRequest(CalendarRecurrenceType.DAILY, 1, null, null, CalendarRecurrenceEndType.COUNT, null, 3, null, "Asia/Seoul"),
			List.of(),
			List.of(),
			List.of(),
			List.of(),
			true,
			"APP"
		), owner);

		List<CalendarDtos.EventResponse> expanded = calendarService.events(start.minus(1, ChronoUnit.HOURS), start.plus(4, ChronoUnit.DAYS), null, null, null, null, null, null, owner);
		assertTrue(expanded.size() >= 3);
		assertEquals(1, calendarService.event(created.id(), owner).attendees().size());
		assertEquals(3, calendarService.event(created.id(), owner).reminders().size());
		assertEquals("development", calendarService.event(created.id(), owner).teamId());
		assertEquals(CalendarImportance.HIGH, calendarService.event(created.id(), owner).importance());
		assertThrows(AccessDeniedException.class, () -> calendarService.delete(created.id(), "ALL", other));
	}

	@Test
	void returnsDefaultCategories() {
		assertTrue(calendarService.categories(owner).stream().anyMatch(category -> category.name().equals("AZOOM 회의")));
	}

	@Test
	void searchesLinkedCalendarDataAndSupportsPagination() {
		Instant start = Instant.parse("2026-06-04T01:00:00Z");
		calendarService.create(new CalendarDtos.EventRequest(
			"주간 회의",
			"연결 검색 검증",
			start,
			start.plus(1, ChronoUnit.HOURS),
			false,
			"회의실 B",
			null,
			null,
			CalendarEventStatus.SCHEDULED,
			CalendarMeetingStatus.RESERVED,
			CalendarVisibility.PRIVATE,
			CalendarDetailVisibility.FULL,
			null,
			null,
			"product",
			CalendarImportance.NORMAL,
			List.of(new CalendarDtos.AttendeeRequest(null, "장유종", "연구소", "팀장", "jang@example.com", CalendarAttendeeStatus.PENDING, null, null)),
			List.of(),
			null,
			List.of(new CalendarDtos.FileLinkRequest(null, "회의자료.pdf", "\\\\NAS\\회의자료.pdf", "pdf", 128L, CalendarFileSourceType.NAS)),
			List.of(new CalendarDtos.NotionLinkRequest("notion-page-1", null, "연구소 회의록", "https://notion.so/research")),
			List.of(new CalendarDtos.ChatLinkRequest("research-lab", "연구소 채팅방", "msg-1", "회의 일정 논의")),
			List.of(new CalendarDtos.AzoomLinkRequest("meeting-1", "azoom-room-1", "https://azoom.example/join", null, null, "minutes-1")),
			true,
			"APP"
		), owner);

		assertEquals(1, calendarService.events(start.minus(1, ChronoUnit.HOURS), start.plus(2, ChronoUnit.HOURS), null, null, null, "장유종", null, null, owner).size());
		assertEquals(1, calendarService.events(start.minus(1, ChronoUnit.HOURS), start.plus(2, ChronoUnit.HOURS), null, null, null, "회의자료", null, null, owner).size());
		assertEquals(1, calendarService.events(start.minus(1, ChronoUnit.HOURS), start.plus(2, ChronoUnit.HOURS), null, null, null, "연구소 채팅방", null, null, owner).size());
		assertEquals(1, calendarService.events(start.minus(1, ChronoUnit.HOURS), start.plus(2, ChronoUnit.HOURS), null, null, null, "azoom-room-1", null, null, owner).size());
		assertEquals(1, calendarService.events(start.minus(1, ChronoUnit.HOURS), start.plus(2, ChronoUnit.HOURS), null, "product", null, null, null, null, owner).size());
		assertEquals(1, calendarService.events(start.minus(1, ChronoUnit.HOURS), start.plus(2, ChronoUnit.HOURS), null, null, null, null, 0, 1, owner).size());
	}

	private CalendarDtos.EventRequest request(String title, Instant start, Instant end) {
		return new CalendarDtos.EventRequest(
			title,
			null,
			start,
			end,
			false,
			null,
			null,
			null,
			CalendarEventStatus.SCHEDULED,
			CalendarMeetingStatus.RESERVED,
			CalendarVisibility.PRIVATE,
			CalendarDetailVisibility.FULL,
			null,
			null,
			null,
			CalendarImportance.NORMAL,
			List.of(),
			List.of(),
			null,
			List.of(),
			List.of(),
			List.of(),
			List.of(),
			true,
			"APP"
		);
	}
}
