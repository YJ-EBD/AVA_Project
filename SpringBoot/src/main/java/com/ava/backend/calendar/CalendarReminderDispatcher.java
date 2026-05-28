package com.ava.backend.calendar;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@ConditionalOnProperty(prefix = "ava.calendar.reminders", name = "enabled", havingValue = "true", matchIfMissing = true)
class CalendarReminderDispatcher {
	private static final Logger log = LoggerFactory.getLogger(CalendarReminderDispatcher.class);
	private static final ZoneId DEFAULT_ZONE = ZoneId.of("Asia/Seoul");
	private static final Duration DUE_GRACE = Duration.ofMinutes(10);
	private static final Duration LOOK_AHEAD = Duration.ofHours(25);
	private static final List<Integer> DEFAULT_REMINDER_MINUTES = List.of(1440, 0);

	private final CalendarEventRepository eventRepository;
	private final CalendarEventReminderRepository reminderRepository;
	private final CalendarEventAttendeeRepository attendeeRepository;
	private final CalendarEventRecurrenceRepository recurrenceRepository;
	private final CalendarReminderDeliveryRepository deliveryRepository;
	private final CalendarNotificationService notificationService;

	CalendarReminderDispatcher(
		CalendarEventRepository eventRepository,
		CalendarEventReminderRepository reminderRepository,
		CalendarEventAttendeeRepository attendeeRepository,
		CalendarEventRecurrenceRepository recurrenceRepository,
		CalendarReminderDeliveryRepository deliveryRepository,
		CalendarNotificationService notificationService
	) {
		this.eventRepository = eventRepository;
		this.reminderRepository = reminderRepository;
		this.attendeeRepository = attendeeRepository;
		this.recurrenceRepository = recurrenceRepository;
		this.deliveryRepository = deliveryRepository;
		this.notificationService = notificationService;
	}

	@Scheduled(
		initialDelayString = "${ava.calendar.reminders.initial-delay-ms:15000}",
		fixedDelayString = "${ava.calendar.reminders.fixed-delay-ms:60000}"
	)
	public void dispatchScheduled() {
		try {
			dispatchDue(Instant.now());
		} catch (RuntimeException exception) {
			log.warn("Calendar reminder dispatch failed.", exception);
		}
	}

	@Transactional
	int dispatchDue(Instant now) {
		Instant dueStart = now.minus(DUE_GRACE);
		Instant occurrenceStartWindow = dueStart.minus(LOOK_AHEAD);
		Instant occurrenceEndWindow = now.plus(LOOK_AHEAD);
		int delivered = 0;
		for (CalendarEventEntity event : eventRepository.findByDeletedAtIsNullOrderByStartAtAsc()) {
			if (isTerminal(event)) {
				continue;
			}
			for (Instant occurrenceStartAt : occurrenceStarts(event, occurrenceStartWindow, occurrenceEndWindow)) {
				for (ReminderCandidate reminder : reminderCandidates(event.getId())) {
					Instant dueAt = dueAt(event, occurrenceStartAt, reminder.remindBeforeMinutes());
					if (dueAt.isBefore(dueStart) || dueAt.isAfter(now)) {
						continue;
					}
					for (UUID targetUserId : targetUsers(event, reminder)) {
						if (alreadyDelivered(event.getId(), occurrenceStartAt, targetUserId, reminder)) {
							continue;
						}
						notificationService.eventReminder(event, reminder.remindBeforeMinutes(), occurrenceStartAt, targetUserId);
						deliveryRepository.save(new CalendarReminderDeliveryEntity(
							event.getId(),
							reminder.reminderId(),
							occurrenceStartAt,
							targetUserId,
							reminder.remindBeforeMinutes(),
							reminder.reminderType(),
							now
						));
						if (reminder.entity() != null) {
							reminder.entity().markSent(now);
							reminderRepository.save(reminder.entity());
						}
						delivered++;
					}
				}
			}
		}
		return delivered;
	}

	private boolean isTerminal(CalendarEventEntity event) {
		return event.getStatus() == CalendarEventStatus.CANCELLED ||
			event.getStatus() == CalendarEventStatus.COMPLETED;
	}

	private List<ReminderCandidate> reminderCandidates(UUID eventId) {
		Map<String, ReminderCandidate> candidates = new LinkedHashMap<>();
		for (int minutes : DEFAULT_REMINDER_MINUTES) {
			ReminderCandidate candidate = ReminderCandidate.defaultOwner(minutes);
			candidates.put(candidate.uniqueKey(), candidate);
		}
		for (CalendarEventReminderEntity reminder : reminderRepository.findByEventIdOrderByRemindBeforeMinutesAsc(eventId)) {
			ReminderCandidate candidate = ReminderCandidate.fromEntity(reminder);
			candidates.putIfAbsent(candidate.uniqueKey(), candidate);
		}
		return new ArrayList<>(candidates.values());
	}

	private Set<UUID> targetUsers(CalendarEventEntity event, ReminderCandidate reminder) {
		Set<UUID> targets = new LinkedHashSet<>();
		switch (reminder.targetType()) {
			case OWNER -> targets.add(event.getOwnerUserId());
			case ATTENDEE -> {
				UUID explicitTarget = parseUuid(reminder.targetId());
				if (explicitTarget != null) {
					targets.add(explicitTarget);
				} else {
					attendeeRepository.findByEventIdOrderByCreatedAtAsc(event.getId()).stream()
						.map(CalendarEventAttendeeEntity::getUserId)
						.filter(Objects::nonNull)
						.forEach(targets::add);
				}
			}
			case CHAT_ROOM -> {
				targets.add(event.getOwnerUserId());
				attendeeRepository.findByEventIdOrderByCreatedAtAsc(event.getId()).stream()
					.map(CalendarEventAttendeeEntity::getUserId)
					.filter(Objects::nonNull)
					.forEach(targets::add);
			}
		}
		targets.remove(null);
		return targets;
	}

	private boolean alreadyDelivered(UUID eventId, Instant occurrenceStartAt, UUID targetUserId, ReminderCandidate reminder) {
		return deliveryRepository.existsByEventIdAndOccurrenceStartAtAndTargetUserIdAndRemindBeforeMinutesAndReminderType(
			eventId,
			occurrenceStartAt,
			targetUserId,
			reminder.remindBeforeMinutes(),
			reminder.reminderType()
		);
	}

	private Instant dueAt(CalendarEventEntity event, Instant occurrenceStartAt, int remindBeforeMinutes) {
		Instant base = occurrenceStartAt;
		if (event.isAllDay()) {
			LocalDate date = LocalDateTime.ofInstant(occurrenceStartAt, DEFAULT_ZONE).toLocalDate();
			base = date.atTime(LocalTime.of(9, 0)).atZone(DEFAULT_ZONE).toInstant();
		}
		return base.minus(remindBeforeMinutes, ChronoUnit.MINUTES);
	}

	private List<Instant> occurrenceStarts(CalendarEventEntity event, Instant windowStart, Instant windowEnd) {
		return recurrenceRepository.findByEventId(event.getId())
			.filter(recurrence -> recurrence.getRecurrenceType() != CalendarRecurrenceType.NONE)
			.map(recurrence -> recurringStarts(event, recurrence, windowStart, windowEnd))
			.orElseGet(() -> event.getStartAt().isBefore(windowStart) || event.getStartAt().isAfter(windowEnd)
				? List.of()
				: List.of(event.getStartAt()));
	}

	private List<Instant> recurringStarts(
		CalendarEventEntity event,
		CalendarEventRecurrenceEntity recurrence,
		Instant windowStart,
		Instant windowEnd
	) {
		List<Instant> starts = new ArrayList<>();
		Instant cursor = event.getStartAt();
		int count = 0;
		while (!cursor.isAfter(windowEnd) && count < 500) {
			if (!cursor.isBefore(windowStart)) {
				starts.add(cursor);
			}
			count++;
			if (recurrence.getEndType() == CalendarRecurrenceEndType.COUNT &&
				recurrence.getOccurrenceCount() != null &&
				count >= recurrence.getOccurrenceCount()) {
				break;
			}
			if (recurrence.getEndType() == CalendarRecurrenceEndType.UNTIL_DATE &&
				recurrence.getUntilDate() != null &&
				LocalDateTime.ofInstant(cursor, DEFAULT_ZONE).toLocalDate().isAfter(recurrence.getUntilDate())) {
				break;
			}
			Instant next = nextOccurrence(cursor, recurrence);
			if (!next.isAfter(cursor)) {
				break;
			}
			cursor = next;
		}
		return starts;
	}

	private Instant nextOccurrence(Instant current, CalendarEventRecurrenceEntity recurrence) {
		int interval = Math.max(1, recurrence.getIntervalValue());
		return switch (recurrence.getRecurrenceType()) {
			case DAILY -> current.plus(interval, ChronoUnit.DAYS);
			case WEEKLY, CUSTOM_DAYS -> current.plus(7L * interval, ChronoUnit.DAYS);
			case MONTHLY, MONTHLY_DAY -> LocalDateTime.ofInstant(current, DEFAULT_ZONE).plusMonths(interval).atZone(DEFAULT_ZONE).toInstant();
			case YEARLY -> LocalDateTime.ofInstant(current, DEFAULT_ZONE).plusYears(interval).atZone(DEFAULT_ZONE).toInstant();
			case WEEKDAYS -> nextWeekday(current);
			case CUSTOM -> current.plus(interval, ChronoUnit.DAYS);
			case NONE -> current;
		};
	}

	private Instant nextWeekday(Instant current) {
		LocalDateTime next = LocalDateTime.ofInstant(current, DEFAULT_ZONE).plusDays(1);
		while (next.getDayOfWeek().getValue() >= 6) {
			next = next.plusDays(1);
		}
		return next.atZone(DEFAULT_ZONE).toInstant();
	}

	private UUID parseUuid(String value) {
		if (value == null || value.isBlank()) {
			return null;
		}
		try {
			return UUID.fromString(value.trim());
		} catch (IllegalArgumentException exception) {
			return null;
		}
	}

	private record ReminderCandidate(
		UUID reminderId,
		int remindBeforeMinutes,
		CalendarReminderType reminderType,
		CalendarReminderTargetType targetType,
		String targetId,
		CalendarEventReminderEntity entity
	) {
		static ReminderCandidate defaultOwner(int minutes) {
			return new ReminderCandidate(null, minutes, CalendarReminderType.IN_APP, CalendarReminderTargetType.OWNER, null, null);
		}

		static ReminderCandidate fromEntity(CalendarEventReminderEntity reminder) {
			return new ReminderCandidate(
				reminder.getId(),
				reminder.getRemindBeforeMinutes(),
				reminder.getReminderType(),
				reminder.getTargetType(),
				reminder.getTargetId(),
				reminder
			);
		}

		String uniqueKey() {
			return remindBeforeMinutes + "|" + targetType + "|" + Objects.toString(targetId, "");
		}
	}
}
