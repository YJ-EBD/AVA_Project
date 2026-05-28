package com.ava.backend.calendar;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Instant;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.TestPropertySource;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.company.CompanyScopeService;
import com.ava.backend.user.entity.UserRole;
import com.fasterxml.jackson.databind.ObjectMapper;

@DataJpaTest
@Import({
	CalendarAiCommandService.class,
	CalendarService.class,
	CompanyScopeService.class,
	NoopCalendarNotificationService.class,
	ObjectMapper.class
})
@TestPropertySource(properties = {
	"spring.flyway.enabled=false",
	"spring.jpa.hibernate.ddl-auto=create-drop"
})
class CalendarAiCommandServiceTest {
	private final AuthPrincipal owner = new AuthPrincipal(
		UUID.fromString("00000000-0000-0000-0000-000000000101"),
		"owner@abba-s.local",
		"Owner",
		UserRole.USER,
		"session"
	);

	@Autowired
	CalendarAiCommandService commandService;

	@Autowired
	CalendarService calendarService;

	@Test
	void createsListsAndDeletesCalendarEventFromNaturalLanguage() {
		UUID conversationId = UUID.randomUUID();

		CalendarAiCommandService.CommandResult created = commandService
			.handle("\"재고앱 개발\" 일정을 2026년 6월 10일 오후 3시에 추가해줘 상태는 예정이야", conversationId, owner)
			.orElseThrow();

		assertTrue(created.success());
		assertTrue(created.workspace().mutation());
		assertEquals("재고앱 개발", created.workspace().events().stream()
			.filter(event -> event.id().toString().equals(created.workspace().selectedEventId()))
			.findFirst()
			.orElseThrow()
			.title());

		CalendarAiCommandService.CommandResult listed = commandService
			.handle("2026년 6월 10일 일정 보여줘", conversationId, owner)
			.orElseThrow();

		assertFalse(listed.workspace().events().isEmpty());
		assertTrue(listed.answer().contains("재고앱 개발"));

		CalendarAiCommandService.CommandResult deleted = commandService
			.handle("\"재고앱 개발\" 일정 삭제해줘", conversationId, owner)
			.orElseThrow();

		assertTrue(deleted.success());
		assertTrue(deleted.workspace().mutation());
		assertTrue(calendarService.events(
			Instant.parse("2026-06-09T00:00:00Z"),
			Instant.parse("2026-06-11T00:00:00Z"),
			null,
			null,
			"재고앱 개발",
			null,
			null,
			owner
		).isEmpty());
	}

	@Test
	void returnsAvailabilitySuggestionsForAiWorkspace() {
		CalendarAiCommandService.CommandResult result = commandService
			.handle("2026년 6월 11일 가능한 회의 시간 30분 추천해줘", UUID.randomUUID(), owner)
			.orElseThrow();

		assertTrue(result.success());
		assertFalse(result.workspace().availability().isEmpty());
	}
}
