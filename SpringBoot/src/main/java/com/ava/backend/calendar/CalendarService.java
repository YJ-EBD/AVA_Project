package com.ava.backend.calendar;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.user.entity.UserRole;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

@Service
@Transactional
public class CalendarService {
	private static final ZoneId DEFAULT_ZONE = ZoneId.of("Asia/Seoul");
	private static final List<DefaultCategory> DEFAULT_CATEGORIES = List.of(
		new DefaultCategory("개인 일정", "#4F7CFF", "person"),
		new DefaultCategory("회사 일정", "#22A06B", "business"),
		new DefaultCategory("팀 일정", "#7C3AED", "groups"),
		new DefaultCategory("부서 일정", "#0EA5E9", "account_tree"),
		new DefaultCategory("프로젝트 일정", "#F97316", "folder"),
		new DefaultCategory("회의 일정", "#EF4444", "meeting_room"),
		new DefaultCategory("AZOOM 회의", "#2563EB", "videocam"),
		new DefaultCategory("개발 일정", "#14B8A6", "code"),
		new DefaultCategory("생산 일정", "#A16207", "precision_manufacturing"),
		new DefaultCategory("재고 일정", "#64748B", "inventory"),
		new DefaultCategory("외근 일정", "#EC4899", "directions_car"),
		new DefaultCategory("휴가 일정", "#06B6D4", "beach_access"),
		new DefaultCategory("교육 일정", "#84CC16", "school"),
		new DefaultCategory("점검 일정", "#F59E0B", "fact_check"),
		new DefaultCategory("기타", "#6B7280", "more_horiz")
	);

	private final CalendarEventRepository eventRepository;
	private final CalendarCategoryRepository categoryRepository;
	private final CalendarEventAttendeeRepository attendeeRepository;
	private final CalendarEventReminderRepository reminderRepository;
	private final CalendarEventRecurrenceRepository recurrenceRepository;
	private final CalendarEventFileRepository fileRepository;
	private final CalendarEventNotionLinkRepository notionRepository;
	private final CalendarEventChatLinkRepository chatRepository;
	private final CalendarEventAzoomLinkRepository azoomRepository;
	private final CalendarEventAuditLogRepository auditRepository;
	private final CalendarNotificationService notificationService;
	private final ObjectMapper objectMapper;

	public CalendarService(
		CalendarEventRepository eventRepository,
		CalendarCategoryRepository categoryRepository,
		CalendarEventAttendeeRepository attendeeRepository,
		CalendarEventReminderRepository reminderRepository,
		CalendarEventRecurrenceRepository recurrenceRepository,
		CalendarEventFileRepository fileRepository,
		CalendarEventNotionLinkRepository notionRepository,
		CalendarEventChatLinkRepository chatRepository,
		CalendarEventAzoomLinkRepository azoomRepository,
		CalendarEventAuditLogRepository auditRepository,
		CalendarNotificationService notificationService,
		ObjectMapper objectMapper
	) {
		this.eventRepository = eventRepository;
		this.categoryRepository = categoryRepository;
		this.attendeeRepository = attendeeRepository;
		this.reminderRepository = reminderRepository;
		this.recurrenceRepository = recurrenceRepository;
		this.fileRepository = fileRepository;
		this.notionRepository = notionRepository;
		this.chatRepository = chatRepository;
		this.azoomRepository = azoomRepository;
		this.auditRepository = auditRepository;
		this.notificationService = notificationService;
		this.objectMapper = objectMapper;
	}

	public List<CalendarDtos.EventResponse> events(
		Instant startAt,
		Instant endAt,
		UUID categoryId,
		CalendarEventStatus status,
		String query,
		Integer page,
		Integer size,
		AuthPrincipal principal
	) {
		seedDefaultCategories();
		Instant rangeStart = startAt == null ? LocalDate.now(DEFAULT_ZONE).atStartOfDay(DEFAULT_ZONE).minusMonths(1).toInstant() : startAt;
		Instant rangeEnd = endAt == null ? LocalDate.now(DEFAULT_ZONE).atStartOfDay(DEFAULT_ZONE).plusMonths(2).toInstant() : endAt;
		List<CalendarEventEntity> candidates = query == null || query.isBlank()
			? eventRepository.findByDeletedAtIsNullOrderByStartAtAsc()
			: searchActiveEverywhere(query.trim());
		List<CalendarDtos.EventResponse> results = candidates.stream()
			.filter(event -> canView(event, principal))
			.filter(event -> categoryId == null || categoryId.equals(event.getCategoryId()))
			.filter(event -> status == null || status == event.getStatus())
			.flatMap(event -> expandEvent(event, rangeStart, rangeEnd, principal).stream())
			.sorted(Comparator.comparing(CalendarDtos.EventResponse::occurrenceStartAt))
			.limit(500)
			.toList();
		return slice(results, page, size);
	}

	public CalendarDtos.EventResponse event(UUID id, AuthPrincipal principal) {
		seedDefaultCategories();
		CalendarEventEntity event = activeEvent(id);
		requireView(event, principal);
		return toResponse(event, event.getStartAt(), event.getEndAt(), principal);
	}

	public CalendarDtos.EventResponse create(CalendarDtos.EventRequest request, AuthPrincipal principal) {
		seedDefaultCategories();
		validateEventRequest(request);
		if (!Boolean.TRUE.equals(request.ignoreConflicts())) {
			CalendarDtos.ConflictCheckResponse conflicts = checkConflicts(conflictRequestFrom(request, null), principal);
			if (conflicts.hasConflicts()) {
				throw new IllegalStateException("일정 시간이 기존 일정과 겹칩니다. 충돌 확인 후 다시 저장해 주세요.");
			}
		}
		CalendarEventEntity event = new CalendarEventEntity(principal.userId(), principal.userId());
		event.apply(request, principal.userId());
		if (event.getCategoryId() == null) {
			var category = defaultCategory();
			if (category.isPresent()) {
				event.apply(withCategory(request, category.get().getId()), principal.userId());
			}
		}
		event = eventRepository.save(event);
		replaceChildren(event.getId(), request);
		audit(event.getId(), "CREATE", principal, null, toResponse(event, event.getStartAt(), event.getEndAt(), principal), request.source());
		notificationService.eventChanged(event, "CREATE", principal);
		return event(event.getId(), principal);
	}

	public CalendarDtos.EventResponse update(UUID id, CalendarDtos.EventPatchRequest request, AuthPrincipal principal) {
		CalendarEventEntity event = activeEvent(id);
		requireMutate(event, principal);
		validateEventRequest(request.toEventRequest());
		if (!Boolean.TRUE.equals(request.ignoreConflicts())) {
			CalendarDtos.ConflictCheckResponse conflicts = checkConflicts(conflictRequestFrom(request.toEventRequest(), id), principal);
			if (conflicts.hasConflicts()) {
				throw new IllegalStateException("일정 시간이 기존 일정과 겹칩니다. 충돌 확인 후 다시 저장해 주세요.");
			}
		}
		CalendarDtos.EventResponse before = toResponse(event, event.getStartAt(), event.getEndAt(), principal);
		event.apply(request.toEventRequest(), principal.userId());
		eventRepository.save(event);
		replacePatchChildren(event.getId(), request);
		audit(event.getId(), "UPDATE", principal, before, toResponse(event, event.getStartAt(), event.getEndAt(), principal), request.source());
		notificationService.eventChanged(event, "UPDATE", principal);
		return event(event.getId(), principal);
	}

	public void delete(UUID id, String recurrenceDeleteScope, AuthPrincipal principal) {
		CalendarEventEntity event = activeEvent(id);
		requireMutate(event, principal);
		CalendarDtos.EventResponse before = toResponse(event, event.getStartAt(), event.getEndAt(), principal);
		event.softDelete(principal.userId());
		eventRepository.save(event);
		deleteChildren(id);
		audit(id, "DELETE", principal, before, Map.of("deleted", true, "scope", recurrenceDeleteScope == null ? "ALL" : recurrenceDeleteScope), "APP");
		notificationService.eventChanged(event, "DELETE", principal);
	}

	public List<CalendarDtos.CategoryResponse> categories(AuthPrincipal principal) {
		seedDefaultCategories();
		return categoryRepository.findByOwnerUserIdOrDefaultCategoryTrueOrderBySortOrderAscNameAsc(principal.userId())
			.stream()
			.map(this::toCategoryResponse)
			.toList();
	}

	public CalendarDtos.CategoryResponse createCategory(CalendarDtos.CategoryRequest request, AuthPrincipal principal) {
		validateCategoryRequest(request);
		CalendarCategoryEntity category = new CalendarCategoryEntity(
			request.name().trim(),
			request.color() == null || request.color().isBlank() ? "#4F7CFF" : request.color().trim(),
			request.icon(),
			request.scope() == null ? CalendarCategoryScope.USER : request.scope(),
			request.scope() == null || request.scope() == CalendarCategoryScope.USER ? principal.userId() : null,
			false,
			request.sortOrder() == null ? 100 : request.sortOrder()
		);
		return toCategoryResponse(categoryRepository.save(category));
	}

	public CalendarDtos.CategoryResponse updateCategory(UUID id, CalendarDtos.CategoryRequest request, AuthPrincipal principal) {
		validateCategoryRequest(request);
		CalendarCategoryEntity category = categoryRepository.findById(id)
			.orElseThrow(() -> new IllegalArgumentException("카테고리를 찾지 못했습니다."));
		if (category.isDefaultCategory()) {
			throw new AccessDeniedException("기본 카테고리는 수정할 수 없습니다.");
		}
		if (category.getOwnerUserId() != null && !category.getOwnerUserId().equals(principal.userId())) {
			throw new AccessDeniedException("카테고리 수정 권한이 없습니다.");
		}
		category.apply(request, principal.userId());
		return toCategoryResponse(categoryRepository.save(category));
	}

	public void deleteCategory(UUID id, AuthPrincipal principal) {
		CalendarCategoryEntity category = categoryRepository.findById(id)
			.orElseThrow(() -> new IllegalArgumentException("카테고리를 찾지 못했습니다."));
		if (category.isDefaultCategory()) {
			throw new AccessDeniedException("기본 카테고리는 삭제할 수 없습니다.");
		}
		if (category.getOwnerUserId() != null && !category.getOwnerUserId().equals(principal.userId())) {
			throw new AccessDeniedException("카테고리 삭제 권한이 없습니다.");
		}
		categoryRepository.delete(category);
	}

	public CalendarDtos.AttendeeResponse addAttendee(UUID eventId, CalendarDtos.AttendeeRequest request, AuthPrincipal principal) {
		CalendarEventEntity event = activeEvent(eventId);
		requireMutate(event, principal);
		validateAttendee(request, eventId);
		CalendarEventAttendeeEntity attendee = attendeeRepository.save(new CalendarEventAttendeeEntity(eventId, request));
		audit(eventId, "ADD_ATTENDEE", principal, null, toAttendeeResponse(attendee), "APP");
		return toAttendeeResponse(attendee);
	}

	public CalendarDtos.AttendeeResponse updateAttendee(UUID eventId, UUID attendeeId, CalendarDtos.AttendeeRequest request, AuthPrincipal principal) {
		CalendarEventEntity event = activeEvent(eventId);
		requireMutate(event, principal);
		CalendarEventAttendeeEntity attendee = attendeeRepository.findById(attendeeId)
			.filter(item -> item.getEventId().equals(eventId))
			.orElseThrow(() -> new IllegalArgumentException("참석자를 찾지 못했습니다."));
		CalendarDtos.AttendeeResponse before = toAttendeeResponse(attendee);
		attendee.apply(request);
		attendee = attendeeRepository.save(attendee);
		audit(eventId, "UPDATE_ATTENDEE", principal, before, toAttendeeResponse(attendee), "APP");
		return toAttendeeResponse(attendee);
	}

	public void deleteAttendee(UUID eventId, UUID attendeeId, AuthPrincipal principal) {
		CalendarEventEntity event = activeEvent(eventId);
		requireMutate(event, principal);
		CalendarEventAttendeeEntity attendee = attendeeRepository.findById(attendeeId)
			.filter(item -> item.getEventId().equals(eventId))
			.orElseThrow(() -> new IllegalArgumentException("참석자를 찾지 못했습니다."));
		attendeeRepository.delete(attendee);
		audit(eventId, "DELETE_ATTENDEE", principal, toAttendeeResponse(attendee), null, "APP");
	}

	public CalendarDtos.ReminderResponse addReminder(UUID eventId, CalendarDtos.ReminderRequest request, AuthPrincipal principal) {
		CalendarEventEntity event = activeEvent(eventId);
		requireMutate(event, principal);
		validateReminder(eventId, request);
		CalendarEventReminderEntity reminder = reminderRepository.save(new CalendarEventReminderEntity(eventId, request));
		audit(eventId, "ADD_REMINDER", principal, null, toReminderResponse(reminder), "APP");
		return toReminderResponse(reminder);
	}

	public void deleteReminder(UUID eventId, UUID reminderId, AuthPrincipal principal) {
		CalendarEventEntity event = activeEvent(eventId);
		requireMutate(event, principal);
		CalendarEventReminderEntity reminder = reminderRepository.findById(reminderId)
			.filter(item -> item.getEventId().equals(eventId))
			.orElseThrow(() -> new IllegalArgumentException("알림을 찾지 못했습니다."));
		reminderRepository.delete(reminder);
		audit(eventId, "DELETE_REMINDER", principal, toReminderResponse(reminder), null, "APP");
	}

	public CalendarDtos.FileLinkResponse addFile(UUID eventId, CalendarDtos.FileLinkRequest request, AuthPrincipal principal) {
		CalendarEventEntity event = activeEvent(eventId);
		requireMutate(event, principal);
		CalendarEventFileEntity link = fileRepository.save(new CalendarEventFileEntity(eventId, request));
		audit(eventId, "LINK_FILE", principal, null, toFileResponse(link), "APP");
		return toFileResponse(link);
	}

	public void deleteFile(UUID eventId, UUID linkId, AuthPrincipal principal) {
		deleteLink(eventId, linkId, principal, fileRepository, CalendarEventFileEntity::getEventId, this::toFileResponse, "UNLINK_FILE");
	}

	public CalendarDtos.NotionLinkResponse addNotion(UUID eventId, CalendarDtos.NotionLinkRequest request, AuthPrincipal principal) {
		CalendarEventEntity event = activeEvent(eventId);
		requireMutate(event, principal);
		CalendarEventNotionLinkEntity link = notionRepository.save(new CalendarEventNotionLinkEntity(eventId, request));
		audit(eventId, "LINK_NOTION", principal, null, toNotionResponse(link), "APP");
		return toNotionResponse(link);
	}

	public void deleteNotion(UUID eventId, UUID linkId, AuthPrincipal principal) {
		deleteLink(eventId, linkId, principal, notionRepository, CalendarEventNotionLinkEntity::getEventId, this::toNotionResponse, "UNLINK_NOTION");
	}

	public CalendarDtos.ChatLinkResponse addChat(UUID eventId, CalendarDtos.ChatLinkRequest request, AuthPrincipal principal) {
		CalendarEventEntity event = activeEvent(eventId);
		requireMutate(event, principal);
		CalendarEventChatLinkEntity link = chatRepository.save(new CalendarEventChatLinkEntity(eventId, request));
		audit(eventId, "LINK_CHAT", principal, null, toChatResponse(link), "APP");
		return toChatResponse(link);
	}

	public void deleteChat(UUID eventId, UUID linkId, AuthPrincipal principal) {
		deleteLink(eventId, linkId, principal, chatRepository, CalendarEventChatLinkEntity::getEventId, this::toChatResponse, "UNLINK_CHAT");
	}

	public CalendarDtos.AzoomLinkResponse addAzoom(UUID eventId, CalendarDtos.AzoomLinkRequest request, AuthPrincipal principal) {
		CalendarEventEntity event = activeEvent(eventId);
		requireMutate(event, principal);
		CalendarEventAzoomLinkEntity link = azoomRepository.save(new CalendarEventAzoomLinkEntity(eventId, request));
		audit(eventId, "LINK_AZOOM", principal, null, toAzoomResponse(link), "APP");
		return toAzoomResponse(link);
	}

	public void deleteAzoom(UUID eventId, UUID linkId, AuthPrincipal principal) {
		deleteLink(eventId, linkId, principal, azoomRepository, CalendarEventAzoomLinkEntity::getEventId, this::toAzoomResponse, "UNLINK_AZOOM");
	}

	public CalendarDtos.ConflictCheckResponse checkConflicts(CalendarDtos.ConflictCheckRequest request, AuthPrincipal principal) {
		if (request.endAt() == null || request.startAt() == null || !request.endAt().isAfter(request.startAt())) {
			throw new IllegalArgumentException("종료 시간은 시작 시간보다 늦어야 합니다.");
		}
		Set<UUID> attendeeIds = new LinkedHashSet<>(request.attendeeUserIds() == null ? List.of() : request.attendeeUserIds());
		attendeeIds.add(principal.userId());
		List<CalendarDtos.ConflictResponse> conflicts = eventRepository.findActiveInRange(request.startAt(), request.endAt()).stream()
			.filter(event -> request.excludeEventId() == null || !event.getId().equals(request.excludeEventId()))
			.filter(event -> canView(event, principal) || event.getOwnerUserId().equals(principal.userId()))
			.filter(event -> conflictsWith(event, attendeeIds, request.location(), request.azoomRoomId()))
			.map(event -> new CalendarDtos.ConflictResponse(
				event.getId(),
				event.getTitle(),
				event.getStartAt(),
				event.getEndAt(),
				conflictReason(event, attendeeIds, request.location(), request.azoomRoomId()),
				event.getOwnerUserId().toString()
			))
			.toList();
		return new CalendarDtos.ConflictCheckResponse(!conflicts.isEmpty(), conflicts);
	}

	public List<CalendarDtos.AvailabilitySuggestion> suggestAvailability(CalendarDtos.AvailabilityRequest request, AuthPrincipal principal) {
		if (request.rangeStart() == null || request.rangeEnd() == null || !request.rangeEnd().isAfter(request.rangeStart())) {
			throw new IllegalArgumentException("추천 범위가 올바르지 않습니다.");
		}
		int duration = request.durationMinutes() == null || request.durationMinutes() < 15 ? 30 : request.durationMinutes();
		LocalTime workStart = parseTime(request.workdayStart(), LocalTime.of(9, 0));
		LocalTime workEnd = parseTime(request.workdayEnd(), LocalTime.of(18, 0));
		List<CalendarDtos.AvailabilitySuggestion> suggestions = new ArrayList<>();
		LocalDate cursor = LocalDateTime.ofInstant(request.rangeStart(), DEFAULT_ZONE).toLocalDate();
		LocalDate endDate = LocalDateTime.ofInstant(request.rangeEnd(), DEFAULT_ZONE).toLocalDate();
		while (!cursor.isAfter(endDate) && suggestions.size() < 20) {
			LocalDateTime slot = cursor.atTime(workStart);
			LocalDateTime dayEnd = cursor.atTime(workEnd);
			while (!slot.plusMinutes(duration).isAfter(dayEnd) && suggestions.size() < 20) {
				LocalTime time = slot.toLocalTime();
				if (!time.isBefore(LocalTime.NOON) && time.isBefore(LocalTime.of(13, 0))) {
					slot = cursor.atTime(13, 0);
					continue;
				}
				Instant start = slot.atZone(DEFAULT_ZONE).toInstant();
				Instant end = slot.plusMinutes(duration).atZone(DEFAULT_ZONE).toInstant();
				if (!start.isBefore(request.rangeStart()) && !end.isAfter(request.rangeEnd()) && !excluded(start, end, request.excludedTimes())) {
					CalendarDtos.ConflictCheckResponse conflicts = checkConflicts(
						new CalendarDtos.ConflictCheckRequest(start, end, request.attendeeUserIds(), null, null, null),
						principal
					);
					if (!conflicts.hasConflicts()) {
						suggestions.add(new CalendarDtos.AvailabilitySuggestion(start, end, 100 - suggestions.size(), List.of()));
					}
				}
				slot = slot.plusMinutes(30);
			}
			cursor = cursor.plusDays(1);
		}
		return suggestions;
	}

	@Transactional(readOnly = true)
	public CalendarDtos.CalendarSummaryResponse today(AuthPrincipal principal) {
		LocalDate today = LocalDate.now(DEFAULT_ZONE);
		return summary("오늘 일정", today.atStartOfDay(DEFAULT_ZONE).toInstant(), today.plusDays(1).atStartOfDay(DEFAULT_ZONE).toInstant(), principal);
	}

	@Transactional(readOnly = true)
	public CalendarDtos.CalendarSummaryResponse week(AuthPrincipal principal) {
		LocalDate today = LocalDate.now(DEFAULT_ZONE);
		LocalDate start = today.minusDays(today.getDayOfWeek().getValue() - 1L);
		return summary("이번 주 일정", start.atStartOfDay(DEFAULT_ZONE).toInstant(), start.plusDays(7).atStartOfDay(DEFAULT_ZONE).toInstant(), principal);
	}

	public List<Map<String, Object>> toolSpecs() {
		return List.of(
			tool("calendar.list_events", "권한 범위 내 일정 목록을 조회합니다.", Map.of("startAt", "ISO-8601", "endAt", "ISO-8601", "status", "optional", "query", "optional", "page", "optional", "size", "optional")),
			tool("calendar.get_event", "단일 일정 상세를 조회합니다.", Map.of("id", "UUID")),
			tool("calendar.create_event", "사용자 확인 후 일정을 생성합니다.", Map.of("title", "string", "startAt", "ISO-8601", "endAt", "ISO-8601")),
			tool("calendar.update_event", "사용자 확인 후 일정을 수정합니다.", Map.of("id", "UUID", "patch", "CalendarEvent")),
			tool("calendar.delete_event", "사용자 확인 후 일정을 삭제합니다.", Map.of("id", "UUID", "recurrenceDeleteScope", "THIS|FUTURE|ALL")),
			tool("calendar.check_conflicts", "일정 충돌을 확인합니다.", Map.of("startAt", "ISO-8601", "endAt", "ISO-8601", "attendeeUserIds", "UUID[]")),
			tool("calendar.suggest_availability", "가능한 시간 후보를 추천합니다.", Map.of("rangeStart", "ISO-8601", "rangeEnd", "ISO-8601", "durationMinutes", "number")),
			tool("calendar.summarize_today", "오늘 일정을 구조화 JSON으로 요약합니다.", Map.of()),
			tool("calendar.summarize_week", "이번 주 일정을 구조화 JSON으로 요약합니다.", Map.of()),
			tool("calendar.link_chat_room", "사용자 확인 후 일정에 채팅방을 연결합니다.", Map.of("eventId", "UUID", "chatRoomId", "string")),
			tool("calendar.link_azoom_meeting", "사용자 확인 후 일정에 AZOOM 회의를 연결합니다.", Map.of("eventId", "UUID", "azoomMeetingId", "string")),
			tool("calendar.link_nas_file", "사용자 확인 후 일정에 NAS 파일을 연결합니다.", Map.of("eventId", "UUID", "filePath", "string")),
			tool("calendar.link_notion_page", "사용자 확인 후 일정에 Notion 페이지를 연결합니다.", Map.of("eventId", "UUID", "notionPageId", "string"))
		);
	}

	private CalendarDtos.CalendarSummaryResponse summary(String title, Instant start, Instant end, AuthPrincipal principal) {
		List<CalendarDtos.EventResponse> events = events(start, end, null, null, null, null, null, principal);
		Map<String, Long> counts = events.stream().collect(Collectors.groupingBy(event -> event.status().name(), LinkedHashMap::new, Collectors.counting()));
		return new CalendarDtos.CalendarSummaryResponse(title, start, end, events.size(), events, counts);
	}

	private List<CalendarEventEntity> searchActiveEverywhere(String query) {
		LinkedHashMap<UUID, CalendarEventEntity> matches = new LinkedHashMap<>();
		eventRepository.searchActive(query).forEach(event -> matches.put(event.getId(), event));
		categoryRepository.findByNameContainingIgnoreCase(query)
			.forEach(category -> eventRepository.findByCategoryIdAndDeletedAtIsNullOrderByStartAtAsc(category.getId())
				.forEach(event -> matches.put(event.getId(), event)));
		addSearchMatches(matches, attendeeRepository.searchEventIds(query));
		addSearchMatches(matches, fileRepository.searchEventIds(query));
		addSearchMatches(matches, notionRepository.searchEventIds(query));
		addSearchMatches(matches, chatRepository.searchEventIds(query));
		addSearchMatches(matches, azoomRepository.searchEventIds(query));
		return matches.values().stream()
			.sorted(Comparator.comparing(CalendarEventEntity::getStartAt))
			.toList();
	}

	private void addSearchMatches(Map<UUID, CalendarEventEntity> matches, List<UUID> eventIds) {
		for (UUID eventId : eventIds) {
			eventRepository.findByIdAndDeletedAtIsNull(eventId)
				.ifPresent(event -> matches.put(event.getId(), event));
		}
	}

	private <T> List<T> slice(List<T> results, Integer page, Integer size) {
		if (page == null && size == null) {
			return results;
		}
		int normalizedPage = Math.max(0, page == null ? 0 : page);
		int normalizedSize = Math.min(200, Math.max(1, size == null ? 100 : size));
		int from = normalizedPage * normalizedSize;
		if (from >= results.size()) {
			return List.of();
		}
		int to = Math.min(results.size(), from + normalizedSize);
		return results.subList(from, to);
	}

	private List<CalendarDtos.EventResponse> expandEvent(CalendarEventEntity event, Instant rangeStart, Instant rangeEnd, AuthPrincipal principal) {
		CalendarEventRecurrenceEntity recurrence = recurrenceRepository.findByEventId(event.getId()).orElse(null);
		if (recurrence == null || recurrence.getRecurrenceType() == CalendarRecurrenceType.NONE) {
			return overlaps(event.getStartAt(), event.getEndAt(), rangeStart, rangeEnd)
				? List.of(toResponse(event, event.getStartAt(), event.getEndAt(), principal))
				: List.of();
		}
		List<CalendarDtos.EventResponse> results = new ArrayList<>();
		Duration duration = Duration.between(event.getStartAt(), event.getEndAt());
		Instant occurrence = event.getStartAt();
		int count = 0;
		while (occurrence.isBefore(rangeEnd) && count < 200) {
			Instant occurrenceEnd = occurrence.plus(duration);
			if (overlaps(occurrence, occurrenceEnd, rangeStart, rangeEnd)) {
				results.add(toResponse(event, occurrence, occurrenceEnd, principal));
			}
			count++;
			if (recurrence.getEndType() == CalendarRecurrenceEndType.COUNT && recurrence.getOccurrenceCount() != null && count >= recurrence.getOccurrenceCount()) {
				break;
			}
			if (recurrence.getEndType() == CalendarRecurrenceEndType.UNTIL_DATE && recurrence.getUntilDate() != null &&
				LocalDateTime.ofInstant(occurrence, DEFAULT_ZONE).toLocalDate().isAfter(recurrence.getUntilDate())) {
				break;
			}
			occurrence = nextOccurrence(occurrence, recurrence);
			if (!occurrence.isAfter(event.getStartAt())) {
				break;
			}
		}
		return results;
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

	private CalendarDtos.EventResponse toResponse(CalendarEventEntity event, Instant occurrenceStart, Instant occurrenceEnd, AuthPrincipal principal) {
		boolean owner = event.getOwnerUserId().equals(principal.userId());
		boolean attendee = attendeeRepository.existsByEventIdAndUserId(event.getId(), principal.userId());
		CalendarDetailVisibility detail = event.getDetailVisibility();
		boolean redact = !owner && !attendee && detail != CalendarDetailVisibility.FULL;
		Map<UUID, CalendarCategoryEntity> categories = categoryRepository.findAll().stream().collect(Collectors.toMap(CalendarCategoryEntity::getId, Function.identity(), (a, b) -> a));
		CalendarCategoryEntity category = event.getCategoryId() == null ? null : categories.get(event.getCategoryId());
		return new CalendarDtos.EventResponse(
			event.getId(),
			redact && (detail == CalendarDetailVisibility.BUSY_ONLY || detail == CalendarDetailVisibility.PRIVATE) ? "바쁨" : event.getTitle(),
			redact ? null : event.getDescription(),
			event.getStartAt(),
			event.getEndAt(),
			occurrenceStart,
			occurrenceEnd,
			event.isAllDay(),
			redact ? null : event.getLocation(),
			event.getCategoryId(),
			category == null ? null : toCategoryResponse(category),
			event.getColor(),
			event.getStatus(),
			event.getMeetingStatus(),
			event.getVisibility(),
			event.getDetailVisibility(),
			event.getOwnerUserId(),
			event.getCreatedBy(),
			event.getUpdatedBy(),
			redact ? null : event.getMemo(),
			redact ? null : event.getProjectName(),
			redact ? List.of() : attendeeRepository.findByEventIdOrderByCreatedAtAsc(event.getId()).stream().map(this::toAttendeeResponse).toList(),
			redact ? List.of() : reminderRepository.findByEventIdOrderByRemindBeforeMinutesAsc(event.getId()).stream().map(this::toReminderResponse).toList(),
			redact ? null : recurrenceRepository.findByEventId(event.getId()).map(this::toRecurrenceResponse).orElse(null),
			redact ? List.of() : fileRepository.findByEventIdOrderByLinkedAtAsc(event.getId()).stream().map(this::toFileResponse).toList(),
			redact ? List.of() : notionRepository.findByEventIdOrderByLinkedAtAsc(event.getId()).stream().map(this::toNotionResponse).toList(),
			redact ? List.of() : chatRepository.findByEventIdOrderByLinkedAtAsc(event.getId()).stream().map(this::toChatResponse).toList(),
			redact ? List.of() : azoomRepository.findByEventIdOrderByLinkedAtAsc(event.getId()).stream().map(this::toAzoomResponse).toList(),
			event.getCreatedAt(),
			event.getUpdatedAt()
		);
	}

	private CalendarDtos.CategoryResponse toCategoryResponse(CalendarCategoryEntity category) {
		return new CalendarDtos.CategoryResponse(category.getId(), category.getName(), category.getColor(), category.getIcon(), category.getScope(), category.getOwnerUserId(), category.isDefaultCategory(), category.getSortOrder());
	}

	private CalendarDtos.AttendeeResponse toAttendeeResponse(CalendarEventAttendeeEntity attendee) {
		return new CalendarDtos.AttendeeResponse(attendee.getId(), attendee.getUserId(), attendee.getDisplayName(), attendee.getDepartment(), attendee.getPosition(), attendee.getEmail(), attendee.getResponseStatus(), attendee.getResponseMessage(), attendee.getRespondedAt(), attendee.getCreatedAt());
	}

	private CalendarDtos.ReminderResponse toReminderResponse(CalendarEventReminderEntity reminder) {
		return new CalendarDtos.ReminderResponse(reminder.getId(), reminder.getRemindBeforeMinutes(), reminder.getReminderType(), reminder.getTargetType(), reminder.getTargetId(), reminder.isSent(), reminder.getSentAt(), reminder.getCreatedAt());
	}

	private CalendarDtos.RecurrenceResponse toRecurrenceResponse(CalendarEventRecurrenceEntity recurrence) {
		return new CalendarDtos.RecurrenceResponse(recurrence.getId(), recurrence.getRecurrenceType(), recurrence.getIntervalValue(), recurrence.getDaysOfWeek(), recurrence.getDayOfMonth(), recurrence.getEndType(), recurrence.getUntilDate(), recurrence.getOccurrenceCount(), recurrence.getRrule(), recurrence.getTimezone());
	}

	private CalendarDtos.FileLinkResponse toFileResponse(CalendarEventFileEntity file) {
		return new CalendarDtos.FileLinkResponse(file.getId(), file.getFileId(), file.getFileName(), file.getFilePath(), file.getFileType(), file.getFileSize(), file.getSourceType(), file.getLinkedAt());
	}

	private CalendarDtos.NotionLinkResponse toNotionResponse(CalendarEventNotionLinkEntity link) {
		return new CalendarDtos.NotionLinkResponse(link.getId(), link.getNotionPageId(), link.getNotionDatabaseId(), link.getNotionTitle(), link.getNotionUrl(), link.getLinkedAt());
	}

	private CalendarDtos.ChatLinkResponse toChatResponse(CalendarEventChatLinkEntity link) {
		return new CalendarDtos.ChatLinkResponse(link.getId(), link.getChatRoomId(), link.getChatRoomName(), link.getSourceMessageId(), link.getSourceMessagePreview(), link.getLinkedAt());
	}

	private CalendarDtos.AzoomLinkResponse toAzoomResponse(CalendarEventAzoomLinkEntity link) {
		return new CalendarDtos.AzoomLinkResponse(link.getId(), link.getAzoomMeetingId(), link.getAzoomRoomId(), link.getAzoomJoinUrl(), link.getAzoomRecordingId(), link.getAzoomTranscriptId(), link.getAzoomMinutesId(), link.getLinkedAt());
	}

	private void replaceChildren(UUID eventId, CalendarDtos.EventRequest request) {
		if (request.attendees() != null) {
			for (CalendarDtos.AttendeeRequest attendee : request.attendees()) {
				validateAttendee(attendee, eventId);
				attendeeRepository.save(new CalendarEventAttendeeEntity(eventId, attendee));
			}
		}
		if (request.reminders() != null) {
			for (CalendarDtos.ReminderRequest reminder : request.reminders()) {
				validateReminder(eventId, reminder);
				reminderRepository.save(new CalendarEventReminderEntity(eventId, reminder));
			}
		}
		replaceRecurrence(eventId, request.recurrence());
		if (request.files() != null) request.files().forEach(file -> fileRepository.save(new CalendarEventFileEntity(eventId, file)));
		if (request.notionLinks() != null) request.notionLinks().forEach(link -> notionRepository.save(new CalendarEventNotionLinkEntity(eventId, link)));
		if (request.chatLinks() != null) request.chatLinks().forEach(link -> chatRepository.save(new CalendarEventChatLinkEntity(eventId, link)));
		if (request.azoomLinks() != null) request.azoomLinks().forEach(link -> azoomRepository.save(new CalendarEventAzoomLinkEntity(eventId, link)));
	}

	private void replacePatchChildren(UUID eventId, CalendarDtos.EventPatchRequest request) {
		if (request.attendees() != null) {
			attendeeRepository.deleteByEventId(eventId);
			for (CalendarDtos.AttendeeRequest attendee : request.attendees()) {
				validateAttendee(attendee, eventId);
				attendeeRepository.save(new CalendarEventAttendeeEntity(eventId, attendee));
			}
		}
		if (request.reminders() != null) {
			reminderRepository.deleteByEventId(eventId);
			for (CalendarDtos.ReminderRequest reminder : request.reminders()) {
				validateReminder(eventId, reminder);
				reminderRepository.save(new CalendarEventReminderEntity(eventId, reminder));
			}
		}
		replaceRecurrence(eventId, request.recurrence());
		if (request.files() != null) {
			fileRepository.deleteByEventId(eventId);
			request.files().forEach(file -> fileRepository.save(new CalendarEventFileEntity(eventId, file)));
		}
		if (request.notionLinks() != null) {
			notionRepository.deleteByEventId(eventId);
			request.notionLinks().forEach(link -> notionRepository.save(new CalendarEventNotionLinkEntity(eventId, link)));
		}
		if (request.chatLinks() != null) {
			chatRepository.deleteByEventId(eventId);
			request.chatLinks().forEach(link -> chatRepository.save(new CalendarEventChatLinkEntity(eventId, link)));
		}
		if (request.azoomLinks() != null) {
			azoomRepository.deleteByEventId(eventId);
			request.azoomLinks().forEach(link -> azoomRepository.save(new CalendarEventAzoomLinkEntity(eventId, link)));
		}
	}

	private void replaceRecurrence(UUID eventId, CalendarDtos.RecurrenceRequest recurrence) {
		recurrenceRepository.deleteByEventId(eventId);
		if (recurrence != null && recurrence.recurrenceType() != null && recurrence.recurrenceType() != CalendarRecurrenceType.NONE) {
			recurrenceRepository.save(new CalendarEventRecurrenceEntity(eventId, recurrence));
		}
	}

	private void deleteChildren(UUID eventId) {
		attendeeRepository.deleteByEventId(eventId);
		reminderRepository.deleteByEventId(eventId);
		recurrenceRepository.deleteByEventId(eventId);
		fileRepository.deleteByEventId(eventId);
		notionRepository.deleteByEventId(eventId);
		chatRepository.deleteByEventId(eventId);
		azoomRepository.deleteByEventId(eventId);
	}

	private <T, R> void deleteLink(UUID eventId, UUID linkId, AuthPrincipal principal, org.springframework.data.jpa.repository.JpaRepository<T, UUID> repository, Function<T, UUID> eventIdExtractor, Function<T, R> mapper, String action) {
		CalendarEventEntity event = activeEvent(eventId);
		requireMutate(event, principal);
		T link = repository.findById(linkId)
			.filter(item -> eventIdExtractor.apply(item).equals(eventId))
			.orElseThrow(() -> new IllegalArgumentException("연결 항목을 찾지 못했습니다."));
		repository.delete(link);
		audit(eventId, action, principal, mapper.apply(link), null, "APP");
	}

	private void validateEventRequest(CalendarDtos.EventRequest request) {
		if (request.title() == null || request.title().trim().isEmpty()) {
			throw new IllegalArgumentException("제목을 입력해 주세요.");
		}
		if (request.startAt() == null || request.endAt() == null) {
			throw new IllegalArgumentException("시작/종료 시간을 입력해 주세요.");
		}
		if (!request.endAt().isAfter(request.startAt())) {
			throw new IllegalArgumentException("종료 시간은 시작 시간보다 늦어야 합니다.");
		}
	}

	private void validateCategoryRequest(CalendarDtos.CategoryRequest request) {
		if (request.name() == null || request.name().trim().isEmpty()) {
			throw new IllegalArgumentException("카테고리 이름을 입력해 주세요.");
		}
	}

	private void validateAttendee(CalendarDtos.AttendeeRequest request, UUID eventId) {
		if (request.displayName() == null || request.displayName().trim().isEmpty()) {
			throw new IllegalArgumentException("참석자 이름을 입력해 주세요.");
		}
		if (request.userId() != null && attendeeRepository.existsByEventIdAndUserId(eventId, request.userId())) {
			throw new IllegalArgumentException("이미 추가된 참석자입니다.");
		}
		if (request.email() != null && !request.email().isBlank() && attendeeRepository.existsByEventIdAndEmailIgnoreCase(eventId, request.email())) {
			throw new IllegalArgumentException("이미 추가된 참석자 이메일입니다.");
		}
	}

	private void validateReminder(UUID eventId, CalendarDtos.ReminderRequest request) {
		if (request.remindBeforeMinutes() == null || request.remindBeforeMinutes() < 0) {
			throw new IllegalArgumentException("알림 시간은 0분 이상이어야 합니다.");
		}
		CalendarReminderType type = request.reminderType() == null ? CalendarReminderType.IN_APP : request.reminderType();
		CalendarReminderTargetType target = request.targetType() == null ? CalendarReminderTargetType.OWNER : request.targetType();
		if (reminderRepository.existsByEventIdAndRemindBeforeMinutesAndReminderTypeAndTargetType(eventId, request.remindBeforeMinutes(), type, target)) {
			throw new IllegalArgumentException("이미 같은 알림이 등록되어 있습니다.");
		}
	}

	private boolean canView(CalendarEventEntity event, AuthPrincipal principal) {
		if (event.getOwnerUserId().equals(principal.userId())) return true;
		if (isAdmin(principal) && event.getVisibility() == CalendarVisibility.ADMIN) return true;
		if (attendeeRepository.existsByEventIdAndUserId(event.getId(), principal.userId())) return true;
		return event.getVisibility() == CalendarVisibility.TEAM ||
			event.getVisibility() == CalendarVisibility.DEPARTMENT ||
			event.getVisibility() == CalendarVisibility.COMPANY;
	}

	private void requireView(CalendarEventEntity event, AuthPrincipal principal) {
		if (!canView(event, principal)) {
			throw new AccessDeniedException("일정 조회 권한이 없습니다.");
		}
	}

	private void requireMutate(CalendarEventEntity event, AuthPrincipal principal) {
		if (!event.getOwnerUserId().equals(principal.userId()) && !isAdmin(principal)) {
			throw new AccessDeniedException("일정 수정 권한이 없습니다.");
		}
	}

	private boolean isAdmin(AuthPrincipal principal) {
		return principal.role() == UserRole.ADMIN || principal.role() == UserRole.SUPERUSER;
	}

	private CalendarEventEntity activeEvent(UUID id) {
		return eventRepository.findByIdAndDeletedAtIsNull(id)
			.orElseThrow(() -> new IllegalArgumentException("일정을 찾지 못했습니다."));
	}

	private boolean conflictsWith(CalendarEventEntity event, Set<UUID> attendeeIds, String location, String azoomRoomId) {
		if (attendeeIds.contains(event.getOwnerUserId())) return true;
		for (CalendarEventAttendeeEntity attendee : attendeeRepository.findByEventIdOrderByCreatedAtAsc(event.getId())) {
			if (attendee.getUserId() != null && attendeeIds.contains(attendee.getUserId())) return true;
		}
		if (location != null && !location.isBlank() && event.getLocation() != null && event.getLocation().equalsIgnoreCase(location.trim())) return true;
		if (azoomRoomId != null && !azoomRoomId.isBlank()) {
			return azoomRepository.findByEventIdOrderByLinkedAtAsc(event.getId()).stream()
				.anyMatch(link -> azoomRoomId.equalsIgnoreCase(Objects.toString(link.getAzoomRoomId(), "")));
		}
		return false;
	}

	private String conflictReason(CalendarEventEntity event, Set<UUID> attendeeIds, String location, String azoomRoomId) {
		if (attendeeIds.contains(event.getOwnerUserId())) return "내 일정과 시간이 겹칩니다.";
		if (location != null && event.getLocation() != null && event.getLocation().equalsIgnoreCase(location.trim())) return "같은 장소의 일정과 겹칩니다.";
		if (azoomRoomId != null) return "같은 AZOOM 회의방 일정과 겹칠 수 있습니다.";
		return "참석자 일정과 시간이 겹칩니다.";
	}

	private CalendarDtos.ConflictCheckRequest conflictRequestFrom(CalendarDtos.EventRequest request, UUID excludeEventId) {
		List<UUID> attendeeIds = request.attendees() == null ? List.of() : request.attendees().stream()
			.map(CalendarDtos.AttendeeRequest::userId)
			.filter(Objects::nonNull)
			.toList();
		String azoomRoomId = request.azoomLinks() == null ? null : request.azoomLinks().stream()
			.map(CalendarDtos.AzoomLinkRequest::azoomRoomId)
			.filter(value -> value != null && !value.isBlank())
			.findFirst()
			.orElse(null);
		return new CalendarDtos.ConflictCheckRequest(request.startAt(), request.endAt(), attendeeIds, excludeEventId, request.location(), azoomRoomId);
	}

	private boolean overlaps(Instant start, Instant end, Instant rangeStart, Instant rangeEnd) {
		return start.isBefore(rangeEnd) && end.isAfter(rangeStart);
	}

	private boolean excluded(Instant start, Instant end, List<CalendarDtos.TimeRangeRequest> excludedTimes) {
		if (excludedTimes == null) return false;
		return excludedTimes.stream().anyMatch(range -> range.startAt() != null && range.endAt() != null && overlaps(start, end, range.startAt(), range.endAt()));
	}

	private LocalTime parseTime(String value, LocalTime fallback) {
		try {
			return value == null || value.isBlank() ? fallback : LocalTime.parse(value);
		} catch (RuntimeException exception) {
			return fallback;
		}
	}

	private CalendarDtos.EventRequest withCategory(CalendarDtos.EventRequest request, UUID categoryId) {
		return new CalendarDtos.EventRequest(request.title(), request.description(), request.startAt(), request.endAt(), request.allDay(), request.location(), categoryId, request.color(), request.status(), request.meetingStatus(), request.visibility(), request.detailVisibility(), request.memo(), request.projectName(), request.attendees(), request.reminders(), request.recurrence(), request.files(), request.notionLinks(), request.chatLinks(), request.azoomLinks(), request.ignoreConflicts(), request.source());
	}

	private java.util.Optional<CalendarCategoryEntity> defaultCategory() {
		return categoryRepository.findAll().stream().filter(CalendarCategoryEntity::isDefaultCategory).findFirst();
	}

	private void seedDefaultCategories() {
		for (int index = 0; index < DEFAULT_CATEGORIES.size(); index++) {
			DefaultCategory category = DEFAULT_CATEGORIES.get(index);
			if (!categoryRepository.existsByNameAndDefaultCategoryTrue(category.name())) {
				categoryRepository.save(new CalendarCategoryEntity(category.name(), category.color(), category.icon(), CalendarCategoryScope.SYSTEM, null, true, index));
			}
		}
	}

	private void audit(UUID eventId, String action, AuthPrincipal principal, Object before, Object after, String source) {
		auditRepository.save(new CalendarEventAuditLogEntity(eventId, action, principal.userId(), writeJson(before), writeJson(after), source));
	}

	private String writeJson(Object value) {
		if (value == null) return null;
		try {
			return objectMapper.writeValueAsString(value);
		} catch (JsonProcessingException exception) {
			return "{\"error\":\"audit serialization failed\"}";
		}
	}

	private Map<String, Object> tool(String name, String description, Map<String, Object> inputSchema) {
		return Map.of(
			"name", name,
			"description", description,
			"inputSchema", inputSchema,
			"outputSchema", Map.of("success", "boolean", "data", "object", "error", "string|null"),
			"permission", "현재 로그인 사용자의 캘린더 권한 범위 내에서만 실행",
			"requiresConfirmation", name.contains("create") || name.contains("update") || name.contains("delete") || name.contains("link_")
		);
	}

	private record DefaultCategory(String name, String color, String icon) {
	}
}
