package com.ava.backend.calendar;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.company.CompanyScopeService;
import com.ava.backend.user.entity.UserAccount;
import com.ava.backend.user.entity.UserProfile;
import com.ava.backend.user.repository.UserAccountRepository;
import com.ava.backend.user.repository.UserProfileRepository;

@Service
public class CalendarAiCommandService {
	private static final ZoneId DEFAULT_ZONE = ZoneId.of("Asia/Seoul");
	private static final DateTimeFormatter DATE_TIME_LABEL = DateTimeFormatter.ofPattern("M월 d일 HH:mm", Locale.KOREAN);
	private static final Pattern KOREAN_DATE = Pattern.compile("(?:(\\d{4})\\s*년\\s*)?(\\d{1,2})\\s*월\\s*(\\d{1,2})\\s*일");
	private static final Pattern ISO_DATE = Pattern.compile("(\\d{4})[-/.](\\d{1,2})[-/.](\\d{1,2})");
	private static final Pattern SHORT_DATE = Pattern.compile("(?<!\\d)(\\d{1,2})/(\\d{1,2})(?!\\d)");
	private static final Pattern TIME = Pattern.compile("(?:(오전|오후|am|pm)\\s*)?(\\d{1,2})(?:\\s*시|:)(?:\\s*(\\d{1,2})\\s*분?)?", Pattern.CASE_INSENSITIVE);
	private static final Pattern QUOTED = Pattern.compile("[\"'“”‘’]([^\"'“”‘’]{1,120})[\"'“”‘’]");
	private static final Pattern DURATION_MINUTES = Pattern.compile("(\\d{1,3})\\s*분");
	private static final Pattern DURATION_HOURS = Pattern.compile("(\\d{1,2})\\s*시간");

	private final CalendarService calendarService;
	private final UserAccountRepository accountRepository;
	private final UserProfileRepository profileRepository;
	private final CompanyScopeService companyScopeService;
	private final ConcurrentMap<UUID, ConversationCalendarState> conversationStates = new ConcurrentHashMap<>();

	public CalendarAiCommandService(
		CalendarService calendarService,
		UserAccountRepository accountRepository,
		UserProfileRepository profileRepository,
		CompanyScopeService companyScopeService
	) {
		this.calendarService = calendarService;
		this.accountRepository = accountRepository;
		this.profileRepository = profileRepository;
		this.companyScopeService = companyScopeService;
	}

	@Transactional
	public Optional<CommandResult> handle(String content, UUID conversationId, AuthPrincipal principal) {
		String normalized = normalize(content);
		if (!looksLikeCalendarIntent(normalized)) {
			return Optional.empty();
		}
		ConversationCalendarState state = conversationStates.computeIfAbsent(
			conversationId == null ? principal.userId() : conversationId,
			key -> new ConversationCalendarState()
		);
		try {
			CommandResult result = switch (detectIntent(normalized)) {
				case CREATE -> create(content, normalized, principal, state);
				case DELETE -> delete(content, normalized, principal, state);
				case UPDATE -> update(content, normalized, principal, state);
				case CONFLICT -> checkConflicts(content, normalized, principal, state);
				case AVAILABILITY -> suggestAvailability(content, normalized, principal, state);
				case LIST -> list(content, normalized, principal, state);
			};
			return Optional.of(result);
		} catch (AccessDeniedException exception) {
			return Optional.of(errorResult(
				"권한이 없는 일정이라 처리하지 못했습니다.",
				exception,
				principal,
				state
			));
		} catch (IllegalArgumentException | IllegalStateException exception) {
			return Optional.of(errorResult(
				"일정표 요청을 처리하지 못했습니다. " + safeMessage(exception),
				exception,
				principal,
				state
			));
		}
	}

	@Transactional(readOnly = true)
	public CalendarAiWorkspaceResponse snapshot(String mode, AuthPrincipal principal) {
		String normalized = normalize(mode);
		if (normalized.contains("week") || normalized.contains("주")) {
			CalendarDtos.CalendarSummaryResponse summary = calendarService.week(principal);
			return workspaceFromSummary("week", "이번 주 일정표를 불러왔습니다.", summary, "", false, false);
		}
		if (normalized.contains("month") || normalized.contains("월")) {
			DateRange range = monthRange(LocalDate.now(DEFAULT_ZONE));
			List<CalendarDtos.EventResponse> events = calendarService.events(
				range.start(),
				range.end(),
				null,
				null,
				null,
				0,
				100,
				principal
			);
			return workspaceFromEvents(
				"month",
				"이번 달 일정표를 불러왔습니다.",
				"이번 달 일정",
				range,
				events,
				events.isEmpty() ? "" : events.get(0).id().toString(),
				false,
				false,
				List.of(),
				List.of(),
				Map.of()
			);
		}
		CalendarDtos.CalendarSummaryResponse summary = calendarService.today(principal);
		return workspaceFromSummary("today", "오늘 일정표를 불러왔습니다.", summary, "", false, false);
	}

	private CommandResult create(
		String content,
		String normalized,
		AuthPrincipal principal,
		ConversationCalendarState state
	) {
		ParsedWindow window = parseWindow(content, normalized, true);
		String title = extractTitle(content, normalized, true);
		if (title.isBlank()) {
			return clarification("일정 제목을 확인해야 합니다. 예: \"재고앱 개발\" 제목으로 내일 오후 3시에 일정 추가", "create", principal, state);
		}
		List<CalendarDtos.AttendeeRequest> attendees = attendeeRequests(content, principal);
		CalendarEventStatus status = parseStatus(normalized).orElse(CalendarEventStatus.SCHEDULED);
		CalendarMeetingStatus meetingStatus = normalized.contains("회의")
			? CalendarMeetingStatus.RESERVED
			: CalendarMeetingStatus.RESERVED;
		CalendarDtos.EventRequest request = new CalendarDtos.EventRequest(
			title,
			extractDescription(content, title),
			window.startAt(),
			window.endAt(),
			window.allDay(),
			extractLocation(content),
			null,
			null,
			status,
			meetingStatus,
			CalendarVisibility.PRIVATE,
			CalendarDetailVisibility.FULL,
			"",
			extractProjectName(content),
			attendees,
			List.of(new CalendarDtos.ReminderRequest(10, CalendarReminderType.IN_APP, CalendarReminderTargetType.OWNER, null)),
			parseRecurrence(normalized),
			List.of(),
			List.of(),
			List.of(),
			parseAzoomLinks(content, normalized),
			true,
			"AVA_AI"
		);
		CalendarDtos.ConflictCheckResponse conflicts = calendarService.checkConflicts(conflictRequestFrom(request, null), principal);
		if (conflicts.hasConflicts() && !containsAny(normalized, "그래도", "무시", "겹쳐도")) {
			CalendarAiWorkspaceResponse workspace = workspaceFromEvents(
				"conflicts",
				"일정 충돌이 있어 저장 전 확인이 필요합니다.",
				"충돌 확인",
				new DateRange(window.startAt(), window.endAt()),
				List.of(),
				"",
				false,
				true,
				conflicts.conflicts(),
				List.of(),
				Map.of("draftTitle", title)
			);
			return new CommandResult(
				"일정 시간이 기존 일정과 겹칩니다. 그래도 저장하려면 '그래도 저장해줘'라고 말해 주세요.",
				workspace,
				true,
				false,
				true
			);
		}
		CalendarDtos.EventResponse created = calendarService.create(request, principal);
		CalendarDtos.EventResponse verified = calendarService.event(created.id(), principal);
		state.remember(verified.id(), title, "create");
		CalendarAiWorkspaceResponse workspace = workspaceForEvent("created", "일정을 생성하고 다시 조회해 검증했습니다.", verified, principal);
		return new CommandResult(createdAnswer(verified), workspace, true, true, false);
	}

	private CommandResult list(
		String content,
		String normalized,
		AuthPrincipal principal,
		ConversationCalendarState state
	) {
		QueryRange queryRange = parseQueryRange(content, normalized);
		String query = extractSearchQuery(content, normalized);
		CalendarEventStatus status = parseStatus(normalized).orElse(null);
		List<CalendarDtos.EventResponse> events = calendarService.events(
			queryRange.range().start(),
			queryRange.range().end(),
			null,
			status,
			query.isBlank() ? null : query,
			0,
			100,
			principal
		);
		String selectedId = events.isEmpty() ? "" : events.get(0).id().toString();
		if (!events.isEmpty()) {
			state.remember(events.get(0).id(), events.get(0).title(), "list");
		}
		CalendarAiWorkspaceResponse workspace = workspaceFromEvents(
			queryRange.mode(),
			events.isEmpty() ? "조건에 맞는 일정이 없습니다." : events.size() + "개의 일정을 찾았습니다.",
			queryRange.title(),
			queryRange.range(),
			events,
			selectedId,
			false,
			false,
			List.of(),
			List.of(),
			query.isBlank() ? Map.of() : Map.of("query", query)
		);
		return new CommandResult(listAnswer(queryRange.title(), events), workspace, true, true, false);
	}

	private CommandResult update(
		String content,
		String normalized,
		AuthPrincipal principal,
		ConversationCalendarState state
	) {
		ResolvedEvents resolved = resolveEvents(content, normalized, principal, state);
		if (resolved.events().isEmpty()) {
			return clarification("수정할 일정을 찾지 못했습니다. 제목이나 날짜를 함께 말해 주세요.", "update", principal, state);
		}
		if (resolved.events().size() > 1 && !hasContextReference(normalized)) {
			return ambiguous("수정할 일정이 여러 개입니다. 하나를 선택할 수 있게 일정표에 표시했습니다.", "update", resolved.events(), principal, state);
		}
		CalendarDtos.EventResponse current = resolved.events().get(0);
		ParsedWindow parsedWindow = parseWindow(content, normalized, false);
		CalendarDtos.EventPatchRequest patch = patchFrom(
			current,
			extractReplacementTitle(content, normalized).orElse(current.title()),
			parsedWindow.hasExplicitDateOrTime() ? parsedWindow.startAt() : current.startAt(),
			parsedWindow.hasExplicitDateOrTime() ? parsedWindow.endAt() : current.endAt(),
			parsedWindow.hasExplicitDateOrTime() ? parsedWindow.allDay() : current.allDay(),
			parseStatus(normalized).orElse(current.status())
		);
		CalendarDtos.EventResponse updated = calendarService.update(current.id(), patch, principal);
		CalendarDtos.EventResponse verified = calendarService.event(updated.id(), principal);
		state.remember(verified.id(), verified.title(), "update");
		CalendarAiWorkspaceResponse workspace = workspaceForEvent("updated", "일정을 수정하고 다시 조회해 검증했습니다.", verified, principal);
		return new CommandResult(updateAnswer(verified), workspace, true, true, false);
	}

	private CommandResult delete(
		String content,
		String normalized,
		AuthPrincipal principal,
		ConversationCalendarState state
	) {
		ResolvedEvents resolved = resolveEvents(content, normalized, principal, state);
		if (resolved.events().isEmpty()) {
			return clarification("삭제할 일정을 찾지 못했습니다. 삭제할 일정의 제목이나 날짜를 함께 말해 주세요.", "delete", principal, state);
		}
		if (resolved.events().size() > 1 && !hasContextReference(normalized)) {
			return ambiguous("삭제 대상 일정이 여러 개입니다. 하나를 정확히 지정해 주세요.", "delete", resolved.events(), principal, state);
		}
		CalendarDtos.EventResponse target = resolved.events().get(0);
		calendarService.delete(target.id(), "ALL", principal);
		List<CalendarDtos.EventResponse> remaining = calendarService.events(
			target.startAt().minus(Duration.ofDays(1)),
			target.endAt().plus(Duration.ofDays(1)),
			null,
			null,
			target.title(),
			0,
			20,
			principal
		);
		state.remember(null, "", "delete");
		CalendarAiWorkspaceResponse workspace = workspaceFromEvents(
			"deleted",
			"일정을 삭제하고 다시 조회해 검증했습니다.",
			"삭제 검증",
			new DateRange(target.startAt().minus(Duration.ofDays(1)), target.endAt().plus(Duration.ofDays(1))),
			remaining,
			remaining.isEmpty() ? "" : remaining.get(0).id().toString(),
			true,
			false,
			List.of(),
			List.of(),
			Map.of("deletedEventId", target.id().toString(), "deletedTitle", target.title())
		);
		return new CommandResult(
			"일정을 삭제했습니다.\n제목: " + target.title() + "\n검증: 같은 제목으로 다시 조회했습니다.",
			workspace,
			true,
			true,
			false
		);
	}

	private CommandResult checkConflicts(
		String content,
		String normalized,
		AuthPrincipal principal,
		ConversationCalendarState state
	) {
		ParsedWindow window = parseWindow(content, normalized, false);
		if (!window.hasExplicitDateOrTime() && state.lastEventId != null) {
			CalendarDtos.EventResponse event = calendarService.event(state.lastEventId, principal);
			window = new ParsedWindow(event.startAt(), event.endAt(), event.allDay(), true);
		}
		if (!window.hasExplicitDateOrTime()) {
			return clarification("충돌을 확인할 날짜와 시간을 알려 주세요.", "conflict", principal, state);
		}
		CalendarDtos.ConflictCheckResponse conflicts = calendarService.checkConflicts(
			new CalendarDtos.ConflictCheckRequest(
				window.startAt(),
				window.endAt(),
				attendeeUserIds(content, principal),
				null,
				extractLocation(content),
				null
			),
			principal
		);
		CalendarAiWorkspaceResponse workspace = workspaceFromEvents(
			"conflicts",
			conflicts.hasConflicts() ? "충돌 일정이 있습니다." : "충돌 일정이 없습니다.",
			"충돌 확인",
			new DateRange(window.startAt(), window.endAt()),
			List.of(),
			"",
			false,
			false,
			conflicts.conflicts(),
			List.of(),
			Map.of()
		);
		String answer = conflicts.hasConflicts()
			? "충돌 일정 " + conflicts.conflicts().size() + "개를 찾았습니다. 일정표 작업공간에 표시했습니다."
			: "충돌 일정이 없습니다. 해당 시간에 저장 가능합니다.";
		return new CommandResult(answer, workspace, true, true, false);
	}

	private CommandResult suggestAvailability(
		String content,
		String normalized,
		AuthPrincipal principal,
		ConversationCalendarState state
	) {
		QueryRange range = parseQueryRange(content, normalized);
		int durationMinutes = parseDurationMinutes(normalized);
		List<CalendarDtos.AvailabilitySuggestion> suggestions = calendarService.suggestAvailability(
			new CalendarDtos.AvailabilityRequest(
				attendeeUserIds(content, principal),
				range.range().start(),
				range.range().end(),
				durationMinutes,
				"09:00",
				"18:00",
				List.of()
			),
			principal
		);
		CalendarAiWorkspaceResponse workspace = workspaceFromEvents(
			"availability",
			suggestions.isEmpty() ? "추천 가능한 시간이 없습니다." : suggestions.size() + "개의 가능한 시간을 찾았습니다.",
			"가능한 시간",
			range.range(),
			List.of(),
			"",
			false,
			false,
			List.of(),
			suggestions,
			Map.of("durationMinutes", durationMinutes)
		);
		return new CommandResult(availabilityAnswer(suggestions), workspace, true, true, false);
	}

	private CommandResult errorResult(
		String answer,
		RuntimeException exception,
		AuthPrincipal principal,
		ConversationCalendarState state
	) {
		CalendarAiWorkspaceResponse workspace = snapshot("today", principal);
		return new CommandResult(answer, workspace, false, false, false);
	}

	private CommandResult clarification(String answer, String mode, AuthPrincipal principal, ConversationCalendarState state) {
		CalendarAiWorkspaceResponse workspace = snapshot("today", principal);
		workspace = new CalendarAiWorkspaceResponse(
			true,
			false,
			true,
			mode,
			answer,
			workspace.selectedEventId(),
			workspace.summary(),
			workspace.events(),
			workspace.conflicts(),
			workspace.availability(),
			workspace.metadata()
		);
		return new CommandResult(answer, workspace, true, false, true);
	}

	private CommandResult ambiguous(
		String answer,
		String mode,
		List<CalendarDtos.EventResponse> events,
		AuthPrincipal principal,
		ConversationCalendarState state
	) {
		DateRange range = events.isEmpty()
			? defaultSearchRange()
			: new DateRange(events.get(0).startAt().minus(Duration.ofDays(1)), events.get(events.size() - 1).endAt().plus(Duration.ofDays(1)));
		CalendarAiWorkspaceResponse workspace = workspaceFromEvents(
			mode,
			answer,
			"일정 선택 필요",
			range,
			events,
			events.isEmpty() ? "" : events.get(0).id().toString(),
			false,
			true,
			List.of(),
			List.of(),
			Map.of()
		);
		return new CommandResult(answer, workspace, true, true, true);
	}

	private boolean looksLikeCalendarIntent(String normalized) {
		if (normalized.isBlank()) {
			return false;
		}
		boolean notionOnly = containsAny(normalized, "notion", "노션")
			&& !containsAny(normalized, "일정", "캘린더", "일정표", "스케줄", "calendar", "schedule");
		if (notionOnly) {
			return false;
		}
		boolean scheduleWord = containsAny(normalized, "일정", "캘린더", "일정표", "스케줄", "calendar", "schedule");
		boolean meetingWord = containsAny(normalized, "회의", "미팅", "meeting");
		boolean action = containsAny(normalized,
			"추가", "등록", "생성", "작성", "잡아", "만들", "보여", "알려", "조회", "검색", "찾아",
			"삭제", "지워", "없애", "수정", "변경", "완료", "취소", "가능한", "빈 시간", "충돌", "겹");
		return scheduleWord || (meetingWord && action);
	}

	private Intent detectIntent(String normalized) {
		if (containsAny(normalized, "가능한", "빈 시간", "시간 추천", "가능 시간")) {
			return Intent.AVAILABILITY;
		}
		if (containsAny(normalized, "충돌", "겹치", "중복")) {
			return Intent.CONFLICT;
		}
		if (containsAny(normalized, "삭제", "지워", "없애")) {
			return Intent.DELETE;
		}
		if (containsAny(normalized, "수정", "변경", "완료로", "예정으로", "취소로", "연기로", "보류로", "진행 중", "진행중")) {
			return Intent.UPDATE;
		}
		if (containsAny(normalized, "추가", "등록", "생성", "작성", "잡아", "만들")) {
			return Intent.CREATE;
		}
		return Intent.LIST;
	}

	private ParsedWindow parseWindow(String content, String normalized, boolean createDefault) {
		LocalDate today = LocalDate.now(DEFAULT_ZONE);
		List<DateMatch> explicitDates = explicitDates(content, today);
		LocalDate startDate = relativeStartDate(normalized, today).orElse(explicitDates.isEmpty() ? today : explicitDates.get(0).date());
		LocalDate endDate = startDate;
		boolean hasRange = containsAny(normalized, "부터", "까지", "~", "에서");
		if (hasRange) {
			if (normalized.contains("오늘부터")) {
				startDate = today;
			} else if (normalized.contains("내일부터")) {
				startDate = today.plusDays(1);
			} else if (!explicitDates.isEmpty()) {
				startDate = explicitDates.get(0).date();
			}
			if (explicitDates.size() >= 2) {
				endDate = explicitDates.get(explicitDates.size() - 1).date();
			} else if (explicitDates.size() == 1 && containsAny(normalized, "까지", "~")) {
				endDate = explicitDates.get(0).date();
			} else {
				endDate = startDate;
			}
		} else if (!explicitDates.isEmpty()) {
			startDate = explicitDates.get(0).date();
			endDate = startDate;
		}
		Optional<LocalTime> time = explicitTime(content, createDefault);
		boolean hasExplicitDateOrTime = !explicitDates.isEmpty()
			|| containsAny(normalized, "오늘", "내일", "모레", "이번 주", "이번주", "다음 주", "다음주", "이번 달", "이번달")
			|| time.isPresent();
		if (hasRange && !time.isPresent()) {
			Instant start = startDate.atStartOfDay(DEFAULT_ZONE).toInstant();
			Instant end = endDate.plusDays(1).atStartOfDay(DEFAULT_ZONE).toInstant();
			return new ParsedWindow(start, end, true, true);
		}
		if (time.isEmpty() && !createDefault) {
			return new ParsedWindow(
				startDate.atTime(9, 0).atZone(DEFAULT_ZONE).toInstant(),
				startDate.atTime(10, 0).atZone(DEFAULT_ZONE).toInstant(),
				false,
				hasExplicitDateOrTime
			);
		}
		if (time.isEmpty()) {
			Instant start = startDate.atStartOfDay(DEFAULT_ZONE).toInstant();
			Instant end = startDate.plusDays(1).atStartOfDay(DEFAULT_ZONE).toInstant();
			return new ParsedWindow(start, end, true, hasExplicitDateOrTime || createDefault);
		}
		int duration = parseDurationMinutes(normalized);
		LocalDateTime start = LocalDateTime.of(startDate, time.get());
		return new ParsedWindow(
			start.atZone(DEFAULT_ZONE).toInstant(),
			start.plusMinutes(duration).atZone(DEFAULT_ZONE).toInstant(),
			false,
			true
		);
	}

	private QueryRange parseQueryRange(String content, String normalized) {
		LocalDate today = LocalDate.now(DEFAULT_ZONE);
		if (containsAny(normalized, "이번 주", "이번주")) {
			LocalDate monday = today.minusDays(today.getDayOfWeek().getValue() - 1L);
			return new QueryRange("week", "이번 주 일정", new DateRange(
				monday.atStartOfDay(DEFAULT_ZONE).toInstant(),
				monday.plusDays(7).atStartOfDay(DEFAULT_ZONE).toInstant()
			));
		}
		if (containsAny(normalized, "다음 주", "다음주")) {
			LocalDate monday = today.minusDays(today.getDayOfWeek().getValue() - 1L).plusDays(7);
			return new QueryRange("week", "다음 주 일정", new DateRange(
				monday.atStartOfDay(DEFAULT_ZONE).toInstant(),
				monday.plusDays(7).atStartOfDay(DEFAULT_ZONE).toInstant()
			));
		}
		if (containsAny(normalized, "이번 달", "이번달")) {
			return new QueryRange("month", "이번 달 일정", monthRange(today));
		}
		List<DateMatch> dates = explicitDates(content, today);
		if (!dates.isEmpty()) {
			LocalDate date = dates.get(0).date();
			return new QueryRange("day", date.getMonthValue() + "월 " + date.getDayOfMonth() + "일 일정", new DateRange(
				date.atStartOfDay(DEFAULT_ZONE).toInstant(),
				date.plusDays(1).atStartOfDay(DEFAULT_ZONE).toInstant()
			));
		}
		if (normalized.contains("내일")) {
			LocalDate date = today.plusDays(1);
			return new QueryRange("day", "내일 일정", new DateRange(
				date.atStartOfDay(DEFAULT_ZONE).toInstant(),
				date.plusDays(1).atStartOfDay(DEFAULT_ZONE).toInstant()
			));
		}
		if (normalized.contains("모레")) {
			LocalDate date = today.plusDays(2);
			return new QueryRange("day", "모레 일정", new DateRange(
				date.atStartOfDay(DEFAULT_ZONE).toInstant(),
				date.plusDays(1).atStartOfDay(DEFAULT_ZONE).toInstant()
			));
		}
		if (normalized.contains("오늘")) {
			return new QueryRange("today", "오늘 일정", new DateRange(
				today.atStartOfDay(DEFAULT_ZONE).toInstant(),
				today.plusDays(1).atStartOfDay(DEFAULT_ZONE).toInstant()
			));
		}
		String query = extractSearchQuery(content, normalized);
		if (!query.isBlank()) {
			return new QueryRange("search", "검색 결과", defaultSearchRange());
		}
		return new QueryRange("today", "오늘 일정", new DateRange(
			today.atStartOfDay(DEFAULT_ZONE).toInstant(),
			today.plusDays(1).atStartOfDay(DEFAULT_ZONE).toInstant()
		));
	}

	private ResolvedEvents resolveEvents(String content, String normalized, AuthPrincipal principal, ConversationCalendarState state) {
		if (hasContextReference(normalized) && state.lastEventId != null) {
			try {
				return new ResolvedEvents(List.of(calendarService.event(state.lastEventId, principal)));
			} catch (RuntimeException ignored) {
				state.remember(null, "", "stale");
			}
		}
		String query = extractSearchQuery(content, normalized);
		if (query.isBlank() && state.lastTitle != null && !state.lastTitle.isBlank()) {
			query = state.lastTitle;
		}
		List<CalendarDtos.EventResponse> events = calendarService.events(
			defaultSearchRange().start(),
			defaultSearchRange().end(),
			null,
			null,
			query.isBlank() ? null : query,
			0,
			20,
			principal
		);
		String normalizedQuery = normalize(query);
		if (!normalizedQuery.isBlank()) {
			events = events.stream()
				.filter(event -> normalize(event.title()).contains(normalizedQuery)
					|| normalizedQuery.contains(normalize(event.title()))
					|| normalize(event.description()).contains(normalizedQuery))
				.toList();
		}
		return new ResolvedEvents(events);
	}

	private String extractTitle(String content, String normalized, boolean create) {
		Optional<String> quoted = firstQuoted(content);
		if (quoted.isPresent()) {
			return cleanTitle(quoted.get());
		}
		Matcher namedTitle = Pattern.compile("(.{1,120}?)(?:이라는|라는)?\\s*제목").matcher(content);
		if (namedTitle.find()) {
			return cleanTitle(namedTitle.group(1));
		}
		String cleaned = content;
		cleaned = KOREAN_DATE.matcher(cleaned).replaceAll(" ");
		cleaned = ISO_DATE.matcher(cleaned).replaceAll(" ");
		cleaned = SHORT_DATE.matcher(cleaned).replaceAll(" ");
		cleaned = TIME.matcher(cleaned).replaceAll(" ");
		cleaned = cleaned.replaceAll("(오늘|내일|모레|이번\\s*주|다음\\s*주|이번\\s*달|부터|까지|오전|오후)", " ");
		cleaned = cleaned.replaceAll("(일정|캘린더|일정표|스케줄|추가|등록|생성|작성|잡아줘|잡아|만들어줘|만들어|해줘|해주세요|상태는|예정|완료|진행\\s*중|취소|연기|보류)", " ");
		cleaned = cleaned.replaceAll("([가-힣A-Za-z0-9_.-]{2,20})(이랑|랑|하고|와|과)\\s*", " ");
		cleaned = cleanTitle(cleaned);
		if (cleaned.isBlank() && normalized.contains("회의")) {
			return "회의";
		}
		return cleaned.length() > 80 ? cleaned.substring(0, 80).strip() : cleaned;
	}

	private Optional<String> extractReplacementTitle(String content, String normalized) {
		Optional<String> quoted = firstQuoted(content);
		if (quoted.isPresent() && containsAny(normalized, "제목", "이름")) {
			return Optional.of(cleanTitle(quoted.get()));
		}
		Matcher matcher = Pattern.compile("제목(?:을|은)?\\s*(.{1,80}?)(?:로|으로)\\s*(?:수정|변경)").matcher(content);
		if (matcher.find()) {
			return Optional.of(cleanTitle(matcher.group(1)));
		}
		return Optional.empty();
	}

	private String extractSearchQuery(String content, String normalized) {
		Optional<String> quoted = firstQuoted(content);
		if (quoted.isPresent()) {
			return cleanTitle(quoted.get());
		}
		String query = content;
		query = query.replaceAll("(오늘|내일|모레|이번\\s*주|다음\\s*주|이번\\s*달)", " ");
		query = KOREAN_DATE.matcher(query).replaceAll(" ");
		query = ISO_DATE.matcher(query).replaceAll(" ");
		query = SHORT_DATE.matcher(query).replaceAll(" ");
		query = TIME.matcher(query).replaceAll(" ");
		query = query.replaceAll("(일정|캘린더|일정표|스케줄|회의|보여줘|보여|알려줘|알려|조회|검색|찾아줘|찾아|삭제|지워줘|지워|없애줘|없애|수정|변경|완료로|예정으로|취소로|상태|해줘|해주세요)", " ");
		parseStatus(normalized).ifPresent(status -> {});
		query = cleanTitle(query);
		return query.length() > 80 ? query.substring(0, 80).strip() : query;
	}

	private List<CalendarDtos.AttendeeRequest> attendeeRequests(String content, AuthPrincipal principal) {
		LinkedHashMap<UUID, CalendarDtos.AttendeeRequest> attendees = new LinkedHashMap<>();
		String companyName = companyScopeService.effectiveCompany(principal);
		for (UserProfile profile : profileRepository.findByCompanyNameIgnoreCase(companyName)) {
			UserAccount account = profile.getAccount();
			if (account == null || account.getId().equals(principal.userId())) {
				continue;
			}
			String displayName = account.getDisplayName();
			String nickname = profile.getNickname();
			if (containsPerson(content, displayName) || containsPerson(content, nickname)) {
				attendees.put(account.getId(), new CalendarDtos.AttendeeRequest(
					account.getId(),
					displayName,
					profile.getDepartment(),
					profile.getPosition(),
					profile.getContactEmail() == null || profile.getContactEmail().isBlank() ? account.getEmail() : profile.getContactEmail(),
					CalendarAttendeeStatus.PENDING,
					null,
					null
				));
			}
		}
		if (attendees.isEmpty()) {
			accountRepository.findAll().stream()
				.filter(account -> !account.getId().equals(principal.userId()))
				.filter(account -> containsPerson(content, account.getDisplayName()))
				.forEach(account -> attendees.put(account.getId(), new CalendarDtos.AttendeeRequest(
					account.getId(),
					account.getDisplayName(),
					"",
					"",
					account.getEmail(),
					CalendarAttendeeStatus.PENDING,
					null,
					null
				)));
		}
		return new ArrayList<>(attendees.values());
	}

	private List<UUID> attendeeUserIds(String content, AuthPrincipal principal) {
		return attendeeRequests(content, principal).stream()
			.map(CalendarDtos.AttendeeRequest::userId)
			.filter(id -> id != null)
			.toList();
	}

	private boolean containsPerson(String content, String name) {
		if (name == null || name.isBlank()) {
			return false;
		}
		String normalizedContent = normalize(content).replace(" ", "");
		String normalizedName = normalize(name).replace(" ", "");
		return normalizedName.length() >= 2 && normalizedContent.contains(normalizedName);
	}

	private Optional<CalendarEventStatus> parseStatus(String normalized) {
		if (containsAny(normalized, "진행 중", "진행중")) {
			return Optional.of(CalendarEventStatus.IN_PROGRESS);
		}
		if (normalized.contains("완료")) {
			return Optional.of(CalendarEventStatus.COMPLETED);
		}
		if (normalized.contains("취소")) {
			return Optional.of(CalendarEventStatus.CANCELLED);
		}
		if (normalized.contains("연기")) {
			return Optional.of(CalendarEventStatus.POSTPONED);
		}
		if (normalized.contains("보류")) {
			return Optional.of(CalendarEventStatus.ON_HOLD);
		}
		if (normalized.contains("예정")) {
			return Optional.of(CalendarEventStatus.SCHEDULED);
		}
		return Optional.empty();
	}

	private CalendarDtos.RecurrenceRequest parseRecurrence(String normalized) {
		if (containsAny(normalized, "매일", "매주", "매월", "매년", "평일")) {
			CalendarRecurrenceType type = CalendarRecurrenceType.DAILY;
			if (normalized.contains("매주")) {
				type = CalendarRecurrenceType.WEEKLY;
			} else if (normalized.contains("매월")) {
				type = CalendarRecurrenceType.MONTHLY;
			} else if (normalized.contains("매년")) {
				type = CalendarRecurrenceType.YEARLY;
			} else if (normalized.contains("평일")) {
				type = CalendarRecurrenceType.WEEKDAYS;
			}
			return new CalendarDtos.RecurrenceRequest(type, 1, null, null, CalendarRecurrenceEndType.NEVER, null, null, null, "Asia/Seoul");
		}
		return null;
	}

	private List<CalendarDtos.AzoomLinkRequest> parseAzoomLinks(String content, String normalized) {
		if (!containsAny(normalized, "azoom", "아줌", "회의")) {
			return List.of();
		}
		if (!containsAny(normalized, "azoom", "아줌")) {
			return List.of();
		}
		return List.of(new CalendarDtos.AzoomLinkRequest("", "", "", null, null, null));
	}

	private String extractDescription(String content, String title) {
		return "";
	}

	private String extractLocation(String content) {
		Matcher matcher = Pattern.compile("(?:장소|위치)(?:는|:)?\\s*([^,\\n]{1,80})").matcher(content);
		return matcher.find() ? matcher.group(1).strip() : null;
	}

	private String extractProjectName(String content) {
		Matcher matcher = Pattern.compile("(?:프로젝트)(?:는|:)?\\s*([^,\\n]{1,80})").matcher(content);
		return matcher.find() ? matcher.group(1).strip() : null;
	}

	private CalendarDtos.EventPatchRequest patchFrom(
		CalendarDtos.EventResponse current,
		String title,
		Instant startAt,
		Instant endAt,
		boolean allDay,
		CalendarEventStatus status
	) {
		return new CalendarDtos.EventPatchRequest(
			title,
			current.description(),
			startAt,
			endAt,
			allDay,
			current.location(),
			current.categoryId(),
			current.color(),
			status,
			current.meetingStatus(),
			current.visibility(),
			current.detailVisibility(),
			current.memo(),
			current.projectName(),
			current.attendees().stream().map(this::attendeeRequestFrom).toList(),
			current.reminders().stream().map(this::reminderRequestFrom).toList(),
			recurrenceRequestFrom(current.recurrence()),
			current.files().stream().map(this::fileRequestFrom).toList(),
			current.notionLinks().stream().map(this::notionRequestFrom).toList(),
			current.chatLinks().stream().map(this::chatRequestFrom).toList(),
			current.azoomLinks().stream().map(this::azoomRequestFrom).toList(),
			true,
			"THIS",
			"AVA_AI"
		);
	}

	private CalendarDtos.AttendeeRequest attendeeRequestFrom(CalendarDtos.AttendeeResponse response) {
		return new CalendarDtos.AttendeeRequest(
			response.userId(),
			response.displayName(),
			response.department(),
			response.position(),
			response.email(),
			response.responseStatus(),
			response.responseMessage(),
			response.respondedAt()
		);
	}

	private CalendarDtos.ReminderRequest reminderRequestFrom(CalendarDtos.ReminderResponse response) {
		return new CalendarDtos.ReminderRequest(
			response.remindBeforeMinutes(),
			response.reminderType(),
			response.targetType(),
			response.targetId()
		);
	}

	private CalendarDtos.RecurrenceRequest recurrenceRequestFrom(CalendarDtos.RecurrenceResponse response) {
		if (response == null) {
			return null;
		}
		return new CalendarDtos.RecurrenceRequest(
			response.recurrenceType(),
			response.intervalValue(),
			response.daysOfWeek(),
			response.dayOfMonth(),
			response.endType(),
			response.untilDate(),
			response.occurrenceCount(),
			response.rrule(),
			response.timezone()
		);
	}

	private CalendarDtos.FileLinkRequest fileRequestFrom(CalendarDtos.FileLinkResponse response) {
		return new CalendarDtos.FileLinkRequest(
			response.fileId(),
			response.fileName(),
			response.filePath(),
			response.fileType(),
			response.fileSize(),
			response.sourceType()
		);
	}

	private CalendarDtos.NotionLinkRequest notionRequestFrom(CalendarDtos.NotionLinkResponse response) {
		return new CalendarDtos.NotionLinkRequest(
			response.notionPageId(),
			response.notionDatabaseId(),
			response.notionTitle(),
			response.notionUrl()
		);
	}

	private CalendarDtos.ChatLinkRequest chatRequestFrom(CalendarDtos.ChatLinkResponse response) {
		return new CalendarDtos.ChatLinkRequest(
			response.chatRoomId(),
			response.chatRoomName(),
			response.sourceMessageId(),
			response.sourceMessagePreview()
		);
	}

	private CalendarDtos.AzoomLinkRequest azoomRequestFrom(CalendarDtos.AzoomLinkResponse response) {
		return new CalendarDtos.AzoomLinkRequest(
			response.azoomMeetingId(),
			response.azoomRoomId(),
			response.azoomJoinUrl(),
			response.azoomRecordingId(),
			response.azoomTranscriptId(),
			response.azoomMinutesId()
		);
	}

	private CalendarDtos.ConflictCheckRequest conflictRequestFrom(CalendarDtos.EventRequest request, UUID excludeId) {
		return new CalendarDtos.ConflictCheckRequest(
			request.startAt(),
			request.endAt(),
			request.attendees() == null ? List.of() : request.attendees().stream()
				.map(CalendarDtos.AttendeeRequest::userId)
				.filter(id -> id != null)
				.toList(),
			excludeId,
			request.location(),
			request.azoomLinks() == null || request.azoomLinks().isEmpty() ? null : request.azoomLinks().get(0).azoomRoomId()
		);
	}

	private CalendarAiWorkspaceResponse workspaceForEvent(
		String mode,
		String status,
		CalendarDtos.EventResponse event,
		AuthPrincipal principal
	) {
		DateRange range = new DateRange(
			event.startAt().minus(Duration.ofDays(1)),
			event.endAt().plus(Duration.ofDays(1))
		);
		List<CalendarDtos.EventResponse> events = calendarService.events(
			range.start(),
			range.end(),
			null,
			null,
			null,
			0,
			100,
			principal
		);
		return workspaceFromEvents(mode, status, "일정 상세", range, events, event.id().toString(), true, false, List.of(), List.of(), Map.of());
	}

	private CalendarAiWorkspaceResponse workspaceFromSummary(
		String mode,
		String status,
		CalendarDtos.CalendarSummaryResponse summary,
		String selectedEventId,
		boolean mutation,
		boolean requiresClarification
	) {
		return new CalendarAiWorkspaceResponse(
			true,
			mutation,
			requiresClarification,
			mode,
			status,
			selectedEventId.isBlank() && !summary.events().isEmpty() ? summary.events().get(0).id().toString() : selectedEventId,
			new CalendarAiWorkspaceResponse.Summary(
				summary.title(),
				summary.rangeStart(),
				summary.rangeEnd(),
				summary.totalCount(),
				summary.countsByStatus()
			),
			summary.events().stream().map(this::eventCard).toList(),
			List.of(),
			List.of(),
			Map.of()
		);
	}

	private CalendarAiWorkspaceResponse workspaceFromEvents(
		String mode,
		String status,
		String title,
		DateRange range,
		List<CalendarDtos.EventResponse> events,
		String selectedEventId,
		boolean mutation,
		boolean requiresClarification,
		List<CalendarDtos.ConflictResponse> conflicts,
		List<CalendarDtos.AvailabilitySuggestion> availability,
		Map<String, Object> metadata
	) {
		Map<String, Long> counts = events.stream()
			.collect(LinkedHashMap::new, (map, event) -> map.merge(event.status().name(), 1L, Long::sum), LinkedHashMap::putAll);
		return new CalendarAiWorkspaceResponse(
			true,
			mutation,
			requiresClarification,
			mode,
			status,
			selectedEventId,
			new CalendarAiWorkspaceResponse.Summary(title, range.start(), range.end(), events.size(), counts),
			events.stream().map(this::eventCard).toList(),
			conflicts,
			availability,
			metadata == null ? Map.of() : metadata
		);
	}

	private CalendarAiWorkspaceResponse.EventCard eventCard(CalendarDtos.EventResponse event) {
		return new CalendarAiWorkspaceResponse.EventCard(
			event.id(),
			event.title(),
			event.description(),
			event.occurrenceStartAt() == null ? event.startAt() : event.occurrenceStartAt(),
			event.occurrenceEndAt() == null ? event.endAt() : event.occurrenceEndAt(),
			event.allDay(),
			event.location(),
			event.status().name(),
			statusLabel(event.status()),
			event.category() == null ? "" : event.category().name(),
			event.color(),
			event.azoomLinks() != null && !event.azoomLinks().isEmpty(),
			event.chatLinks() != null && !event.chatLinks().isEmpty(),
			event.files() != null && !event.files().isEmpty(),
			event.notionLinks() != null && !event.notionLinks().isEmpty(),
			event.memo()
		);
	}

	private List<DateMatch> explicitDates(String content, LocalDate today) {
		List<DateMatch> matches = new ArrayList<>();
		Matcher korean = KOREAN_DATE.matcher(content);
		while (korean.find()) {
			int year = korean.group(1) == null ? today.getYear() : Integer.parseInt(korean.group(1));
			matches.add(new DateMatch(korean.start(), LocalDate.of(year, Integer.parseInt(korean.group(2)), Integer.parseInt(korean.group(3)))));
		}
		Matcher iso = ISO_DATE.matcher(content);
		while (iso.find()) {
			matches.add(new DateMatch(iso.start(), LocalDate.of(Integer.parseInt(iso.group(1)), Integer.parseInt(iso.group(2)), Integer.parseInt(iso.group(3)))));
		}
		Matcher shortDate = SHORT_DATE.matcher(content);
		while (shortDate.find()) {
			matches.add(new DateMatch(shortDate.start(), LocalDate.of(today.getYear(), Integer.parseInt(shortDate.group(1)), Integer.parseInt(shortDate.group(2)))));
		}
		return matches.stream()
			.sorted(Comparator.comparingInt(DateMatch::index))
			.toList();
	}

	private Optional<LocalDate> relativeStartDate(String normalized, LocalDate today) {
		if (normalized.contains("내일")) {
			return Optional.of(today.plusDays(1));
		}
		if (normalized.contains("모레")) {
			return Optional.of(today.plusDays(2));
		}
		if (normalized.contains("어제")) {
			return Optional.of(today.minusDays(1));
		}
		if (normalized.contains("오늘")) {
			return Optional.of(today);
		}
		return Optional.empty();
	}

	private Optional<LocalTime> explicitTime(String content, boolean createDefault) {
		Matcher matcher = TIME.matcher(content);
		while (matcher.find()) {
			String marker = matcher.group(1) == null ? "" : matcher.group(1).toLowerCase(Locale.ROOT);
			int hour = Integer.parseInt(matcher.group(2));
			int minute = matcher.group(3) == null ? 0 : Integer.parseInt(matcher.group(3));
			boolean hasMarker = !marker.isBlank();
			if (marker.equals("오후") || marker.equals("pm")) {
				if (hour < 12) {
					hour += 12;
				}
			} else if (marker.equals("오전") || marker.equals("am")) {
				if (hour == 12) {
					hour = 0;
				}
			} else if (createDefault && hour >= 1 && hour <= 7) {
				hour += 12;
			}
			if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
				return Optional.of(LocalTime.of(hour, minute));
			}
		}
		return Optional.empty();
	}

	private int parseDurationMinutes(String normalized) {
		Matcher minutes = DURATION_MINUTES.matcher(normalized);
		if (minutes.find()) {
			return Math.max(15, Integer.parseInt(minutes.group(1)));
		}
		Matcher hours = DURATION_HOURS.matcher(normalized);
		if (hours.find()) {
			return Math.max(15, Integer.parseInt(hours.group(1)) * 60);
		}
		return 60;
	}

	private DateRange monthRange(LocalDate date) {
		LocalDate first = date.withDayOfMonth(1);
		return new DateRange(
			first.atStartOfDay(DEFAULT_ZONE).toInstant(),
			first.plusMonths(1).atStartOfDay(DEFAULT_ZONE).toInstant()
		);
	}

	private DateRange defaultSearchRange() {
		LocalDate today = LocalDate.now(DEFAULT_ZONE);
		return new DateRange(
			today.minusYears(1).atStartOfDay(DEFAULT_ZONE).toInstant(),
			today.plusYears(2).atStartOfDay(DEFAULT_ZONE).toInstant()
		);
	}

	private Optional<String> firstQuoted(String content) {
		Matcher matcher = QUOTED.matcher(content);
		if (matcher.find()) {
			return Optional.of(matcher.group(1));
		}
		return Optional.empty();
	}

	private boolean hasContextReference(String normalized) {
		return containsAny(normalized, "방금", "그거", "이거", "위 일정", "최근", "마지막");
	}

	private String createdAnswer(CalendarDtos.EventResponse event) {
		return String.join("\n",
			"일정을 생성하고 다시 열어 검증했습니다.",
			"제목: " + event.title(),
			"시간: " + formatRange(event.startAt(), event.endAt(), event.allDay()),
			"상태: " + statusLabel(event.status())
		);
	}

	private String updateAnswer(CalendarDtos.EventResponse event) {
		return String.join("\n",
			"일정을 수정하고 다시 열어 검증했습니다.",
			"제목: " + event.title(),
			"시간: " + formatRange(event.startAt(), event.endAt(), event.allDay()),
			"상태: " + statusLabel(event.status())
		);
	}

	private String listAnswer(String title, List<CalendarDtos.EventResponse> events) {
		if (events.isEmpty()) {
			return title + "이 없습니다. 일정표 작업공간도 같은 조건으로 비어 있습니다.";
		}
		StringBuilder answer = new StringBuilder();
		answer.append(title).append(" ").append(events.size()).append("개를 찾았습니다.");
		for (CalendarDtos.EventResponse event : events.stream().limit(5).toList()) {
			answer.append("\n- ")
				.append(event.title())
				.append(" (")
				.append(formatRange(event.occurrenceStartAt() == null ? event.startAt() : event.occurrenceStartAt(), event.occurrenceEndAt() == null ? event.endAt() : event.occurrenceEndAt(), event.allDay()))
				.append(")");
		}
		if (events.size() > 5) {
			answer.append("\n나머지는 일정표 작업공간에 표시했습니다.");
		}
		return answer.toString();
	}

	private String availabilityAnswer(List<CalendarDtos.AvailabilitySuggestion> suggestions) {
		if (suggestions.isEmpty()) {
			return "추천 가능한 시간이 없습니다. 날짜 범위나 참석자를 줄여 다시 요청해 주세요.";
		}
		StringBuilder answer = new StringBuilder("가능한 시간 후보를 찾았습니다.");
		for (CalendarDtos.AvailabilitySuggestion suggestion : suggestions.stream().limit(5).toList()) {
			answer.append("\n- ").append(formatRange(suggestion.startAt(), suggestion.endAt(), false));
		}
		return answer.toString();
	}

	private String formatRange(Instant startAt, Instant endAt, boolean allDay) {
		LocalDateTime start = LocalDateTime.ofInstant(startAt, DEFAULT_ZONE);
		LocalDateTime end = LocalDateTime.ofInstant(endAt, DEFAULT_ZONE);
		if (allDay) {
			return start.toLocalDate() + " ~ " + end.toLocalDate();
		}
		return DATE_TIME_LABEL.format(start) + " ~ " + DATE_TIME_LABEL.format(end);
	}

	private String statusLabel(CalendarEventStatus status) {
		return switch (status) {
			case SCHEDULED -> "예정";
			case IN_PROGRESS -> "진행 중";
			case COMPLETED -> "완료";
			case CANCELLED -> "취소";
			case POSTPONED -> "연기";
			case ON_HOLD -> "보류";
		};
	}

	private String cleanTitle(String value) {
		if (value == null) {
			return "";
		}
		return value
			.replaceAll("[\\r\\n]+", " ")
			.replaceAll("\\s+", " ")
			.replaceAll("^(에|을|를|은|는|이|가|으로|로)\\s+", "")
			.strip();
	}

	private String safeMessage(RuntimeException exception) {
		String message = exception.getMessage();
		return message == null || message.isBlank() ? exception.getClass().getSimpleName() : message;
	}

	private String normalize(String value) {
		return value == null ? "" : value.toLowerCase(Locale.ROOT).replaceAll("\\s+", " ").strip();
	}

	private boolean containsAny(String normalized, String... terms) {
		for (String term : terms) {
			if (normalized.contains(term)) {
				return true;
			}
		}
		return false;
	}

	public record CommandResult(
		String answer,
		CalendarAiWorkspaceResponse workspace,
		boolean success,
		boolean verified,
		boolean requiresClarification
	) {
	}

	private enum Intent {
		CREATE,
		LIST,
		UPDATE,
		DELETE,
		CONFLICT,
		AVAILABILITY
	}

	private record DateRange(Instant start, Instant end) {
	}

	private record QueryRange(String mode, String title, DateRange range) {
	}

	private record ParsedWindow(Instant startAt, Instant endAt, boolean allDay, boolean hasExplicitDateOrTime) {
	}

	private record DateMatch(int index, LocalDate date) {
	}

	private record ResolvedEvents(List<CalendarDtos.EventResponse> events) {
	}

	private static final class ConversationCalendarState {
		private UUID lastEventId;
		private String lastTitle = "";
		private String lastAction = "";

		private void remember(UUID eventId, String title, String action) {
			this.lastEventId = eventId;
			this.lastTitle = title == null ? "" : title;
			this.lastAction = action == null ? "" : action;
		}
	}
}
