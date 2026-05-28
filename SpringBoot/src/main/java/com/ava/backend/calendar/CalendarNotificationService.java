package com.ava.backend.calendar;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.notification.service.NotificationService;

interface CalendarNotificationService {
	void eventChanged(CalendarEventEntity event, String action, AuthPrincipal actor);
	void eventReminder(CalendarEventEntity event, int remindBeforeMinutes, Instant occurrenceStartAt, UUID targetUserId);
}

@Service
class CalendarAppNotificationService implements CalendarNotificationService {
	private static final Logger log = LoggerFactory.getLogger(CalendarAppNotificationService.class);
	private static final ZoneId DEFAULT_ZONE = ZoneId.of("Asia/Seoul");
	private static final DateTimeFormatter DATE_TIME_FORMAT = DateTimeFormatter.ofPattern("M월 d일 HH:mm");

	private final NotificationService notificationService;
	private final CalendarEventAttendeeRepository attendeeRepository;

	CalendarAppNotificationService(
		NotificationService notificationService,
		CalendarEventAttendeeRepository attendeeRepository
	) {
		this.notificationService = notificationService;
		this.attendeeRepository = attendeeRepository;
	}

	@Override
	@Transactional
	public void eventChanged(CalendarEventEntity event, String action, AuthPrincipal actor) {
		Set<UUID> targets = new LinkedHashSet<>();
		targets.add(event.getOwnerUserId());
		attendeeRepository.findByEventIdOrderByCreatedAtAsc(event.getId()).stream()
			.map(CalendarEventAttendeeEntity::getUserId)
			.filter(userId -> userId != null && !userId.equals(actor.userId()))
			.forEach(targets::add);
		targets.remove(actor.userId());

		String title = switch (action) {
			case "CREATE" -> "일정이 등록되었습니다.";
			case "UPDATE" -> "일정이 수정되었습니다.";
			case "DELETE" -> "일정이 삭제되었습니다.";
			default -> "캘린더 일정이 변경되었습니다.";
		};
		String body = event.getTitle() == null || event.getTitle().isBlank()
			? "캘린더에서 일정을 확인해 주세요."
			: event.getTitle();
		for (UUID target : targets) {
			try {
				notificationService.notifyUser(
					target,
					"CALENDAR_EVENT_" + action,
					title,
					body,
					"CALENDAR_EVENT",
					event.getId().toString()
				);
			} catch (RuntimeException exception) {
				log.warn("Calendar notification delivery failed. eventId={}, target={}", event.getId(), target, exception);
			}
		}
	}

	@Override
	@Transactional
	public void eventReminder(CalendarEventEntity event, int remindBeforeMinutes, Instant occurrenceStartAt, UUID targetUserId) {
		if (event == null || targetUserId == null) {
			return;
		}
		try {
			notificationService.notifyUser(
				targetUserId,
				"CALENDAR_REMINDER",
				reminderTitle(remindBeforeMinutes),
				reminderBody(event, remindBeforeMinutes, occurrenceStartAt),
				"CALENDAR_EVENT",
				event.getId().toString()
			);
		} catch (RuntimeException exception) {
			log.warn("Calendar reminder delivery failed. eventId={}, target={}", event.getId(), targetUserId, exception);
			throw exception;
		}
	}

	private String reminderTitle(int remindBeforeMinutes) {
		if (remindBeforeMinutes >= 1440) {
			return "내일 일정 알림";
		}
		if (remindBeforeMinutes == 0) {
			return "오늘 일정 시작";
		}
		if (remindBeforeMinutes % 60 == 0) {
			return remindBeforeMinutes / 60 + "시간 후 일정";
		}
		return remindBeforeMinutes + "분 후 일정";
	}

	private String reminderBody(CalendarEventEntity event, int remindBeforeMinutes, Instant occurrenceStartAt) {
		String eventTitle = event.getTitle() == null || event.getTitle().isBlank()
			? "제목 없는 일정"
			: event.getTitle();
		String when = DATE_TIME_FORMAT.format(LocalDateTime.ofInstant(occurrenceStartAt, DEFAULT_ZONE));
		if (remindBeforeMinutes >= 1440) {
			return when + " 일정이 내일 예정되어 있습니다: " + eventTitle;
		}
		if (remindBeforeMinutes == 0) {
			return when + " 일정이 지금 시작됩니다: " + eventTitle;
		}
		return when + " 일정이 곧 시작됩니다: " + eventTitle;
	}
}

class NoopCalendarNotificationService implements CalendarNotificationService {
	@Override
	public void eventChanged(CalendarEventEntity event, String action, AuthPrincipal actor) {
	}

	@Override
	public void eventReminder(CalendarEventEntity event, int remindBeforeMinutes, Instant occurrenceStartAt, UUID targetUserId) {
	}
}
