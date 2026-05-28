package com.ava.backend.calendar;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.TestPropertySource;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.user.entity.UserRole;
import com.fasterxml.jackson.databind.ObjectMapper;

@DataJpaTest
@Import({
	CalendarService.class,
	CalendarReminderDispatcher.class,
	CalendarReminderDispatcherTest.ReminderTestConfig.class,
	ObjectMapper.class
})
@TestPropertySource(properties = {
	"spring.flyway.enabled=false",
	"spring.jpa.hibernate.ddl-auto=create-drop"
})
class CalendarReminderDispatcherTest {
	private final AuthPrincipal owner = new AuthPrincipal(
		UUID.fromString("00000000-0000-0000-0000-000000000201"),
		"owner@abba-s.local",
		"Owner",
		UserRole.USER,
		"session"
	);

	@Autowired
	CalendarService calendarService;

	@Autowired
	CalendarReminderDispatcher dispatcher;

	@Autowired
	CollectingCalendarNotificationService notifications;

	@Test
	void sendsDefaultStartAndDayBeforeRemindersOnlyOnce() {
		Instant now = Instant.parse("2026-06-10T00:00:00Z");
		calendarService.create(request("Today standup", now), owner);
		calendarService.create(request("Tomorrow meeting", now.plus(1, ChronoUnit.DAYS)), owner);

		int delivered = dispatcher.dispatchDue(now);

		assertEquals(2, delivered);
		assertEquals(2, notifications.deliveries.size());
		assertTrue(notifications.deliveries.stream().anyMatch(item -> item.remindBeforeMinutes == 0));
		assertTrue(notifications.deliveries.stream().anyMatch(item -> item.remindBeforeMinutes == 1440));
		assertEquals(0, dispatcher.dispatchDue(now));
		assertEquals(2, notifications.deliveries.size());
	}

	private CalendarDtos.EventRequest request(String title, Instant start) {
		return new CalendarDtos.EventRequest(
			title,
			null,
			start,
			start.plus(1, ChronoUnit.HOURS),
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

	@TestConfiguration
	static class ReminderTestConfig {
		@Bean
		CollectingCalendarNotificationService calendarNotificationService() {
			return new CollectingCalendarNotificationService();
		}
	}

	static class CollectingCalendarNotificationService implements CalendarNotificationService {
		final List<Delivery> deliveries = new ArrayList<>();

		@Override
		public void eventChanged(CalendarEventEntity event, String action, AuthPrincipal actor) {
		}

		@Override
		public void eventReminder(CalendarEventEntity event, int remindBeforeMinutes, Instant occurrenceStartAt, UUID targetUserId) {
			deliveries.add(new Delivery(event.getId(), remindBeforeMinutes, occurrenceStartAt, targetUserId));
		}
	}

	record Delivery(UUID eventId, int remindBeforeMinutes, Instant occurrenceStartAt, UUID targetUserId) {
	}
}
