import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/calendar_api.dart';
import '../domain/calendar_models.dart';

final calendarControllerProvider =
    NotifierProvider<CalendarController, CalendarState>(CalendarController.new);

class CalendarState {
  const CalendarState({
    required this.focusedDate,
    required this.selectedDate,
    required this.viewMode,
    required this.events,
    required this.categories,
    required this.visibleCategoryIds,
    this.selectedEventId,
    this.teamFilter,
    this.statusFilter,
    this.searchQuery = '',
    this.loading = false,
    this.errorText,
    this.conflicts = const [],
    this.availability = const [],
  });

  factory CalendarState.initial() {
    final now = DateTime.now();
    return CalendarState(
      focusedDate: DateTime(now.year, now.month, now.day),
      selectedDate: DateTime(now.year, now.month, now.day),
      viewMode: CalendarViewMode.month,
      events: const [],
      categories: const [],
      visibleCategoryIds: const {},
    );
  }

  final DateTime focusedDate;
  final DateTime selectedDate;
  final CalendarViewMode viewMode;
  final List<CalendarEvent> events;
  final List<CalendarCategory> categories;
  final Set<String> visibleCategoryIds;
  final String? selectedEventId;
  final String? teamFilter;
  final String? statusFilter;
  final String searchQuery;
  final bool loading;
  final String? errorText;
  final List<CalendarConflict> conflicts;
  final List<AvailabilitySuggestion> availability;

  CalendarEvent? get selectedEvent {
    if (selectedEventId == null) {
      return null;
    }
    for (final event in events) {
      if (event.id == selectedEventId) {
        return event;
      }
    }
    return null;
  }

  List<CalendarEvent> get visibleEvents {
    return [
      for (final event in events)
        if (_isVisibleByCategory(event) &&
            _isVisibleByTeam(event) &&
            _isVisibleByStatus(event))
          event,
    ]..sort((a, b) => a.displayStart.compareTo(b.displayStart));
  }

  List<CalendarEvent> selectedDateEvents(DateTime date) {
    return [
      for (final event in visibleEvents)
        if (_sameDate(event.displayStart, date) ||
            _spansDate(event.displayStart, event.displayEnd, date))
          event,
    ];
  }

  List<CalendarEvent> eventsForRange(DateTime start, DateTime end) {
    return [
      for (final event in visibleEvents)
        if (event.displayStart.isBefore(end) && event.displayEnd.isAfter(start))
          event,
    ];
  }

  bool _isVisibleByCategory(CalendarEvent event) {
    if (visibleCategoryIds.isEmpty) {
      return true;
    }
    final id = event.categoryId;
    return id == null || visibleCategoryIds.contains(id);
  }

  bool _isVisibleByStatus(CalendarEvent event) {
    final filter = statusFilter;
    return filter == null || filter.isEmpty || event.status == filter;
  }

  bool _isVisibleByTeam(CalendarEvent event) {
    final filter = teamFilter;
    return filter == null || filter.isEmpty || event.teamId == filter;
  }

  CalendarState copyWith({
    DateTime? focusedDate,
    DateTime? selectedDate,
    CalendarViewMode? viewMode,
    List<CalendarEvent>? events,
    List<CalendarCategory>? categories,
    Set<String>? visibleCategoryIds,
    Object? selectedEventId = _unchanged,
    Object? teamFilter = _unchanged,
    Object? statusFilter = _unchanged,
    String? searchQuery,
    bool? loading,
    Object? errorText = _unchanged,
    List<CalendarConflict>? conflicts,
    List<AvailabilitySuggestion>? availability,
  }) {
    return CalendarState(
      focusedDate: focusedDate ?? this.focusedDate,
      selectedDate: selectedDate ?? this.selectedDate,
      viewMode: viewMode ?? this.viewMode,
      events: events ?? this.events,
      categories: categories ?? this.categories,
      visibleCategoryIds: visibleCategoryIds ?? this.visibleCategoryIds,
      selectedEventId: identical(selectedEventId, _unchanged)
          ? this.selectedEventId
          : selectedEventId as String?,
      teamFilter: identical(teamFilter, _unchanged)
          ? this.teamFilter
          : teamFilter as String?,
      statusFilter: identical(statusFilter, _unchanged)
          ? this.statusFilter
          : statusFilter as String?,
      searchQuery: searchQuery ?? this.searchQuery,
      loading: loading ?? this.loading,
      errorText: identical(errorText, _unchanged)
          ? this.errorText
          : errorText as String?,
      conflicts: conflicts ?? this.conflicts,
      availability: availability ?? this.availability,
    );
  }
}

class CalendarController extends Notifier<CalendarState> {
  @override
  CalendarState build() {
    final initial = CalendarState.initial();
    unawaited(Future<void>.microtask(refresh));
    return initial;
  }

  Future<void> refresh() async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      return;
    }
    state = state.copyWith(loading: true, errorText: null);
    try {
      final range = _queryRange(state.focusedDate, state.viewMode);
      final api = ref.read(calendarApiProvider);
      final results = await Future.wait([
        api.categories(session.accessToken),
        api.events(
          accessToken: session.accessToken,
          startAt: range.start,
          endAt: range.end,
          categoryId: state.visibleCategoryIds.length == 1
              ? state.visibleCategoryIds.first
              : null,
          teamId: state.teamFilter,
          status: state.statusFilter,
          query: state.searchQuery,
        ),
      ]);
      final categories = results[0] as List<CalendarCategory>;
      final events = results[1] as List<CalendarEvent>;
      final selectedStillExists = events.any(
        (event) => event.id == state.selectedEventId,
      );
      state = state.copyWith(
        categories: categories,
        events: events,
        selectedEventId: selectedStillExists
            ? state.selectedEventId
            : _firstEventIdForDate(events, state.selectedDate),
        loading: false,
      );
    } on Object catch (error) {
      state = state.copyWith(
        loading: false,
        errorText: _calendarErrorMessage(error),
      );
    }
  }

  Future<void> refreshFromExternalMutation({
    DateTime? focusDate,
    String? selectedEventId,
  }) async {
    if (focusDate != null) {
      final normalized = DateTime(
        focusDate.year,
        focusDate.month,
        focusDate.day,
      );
      state = state.copyWith(
        focusedDate: normalized,
        selectedDate: normalized,
        selectedEventId: selectedEventId == null || selectedEventId.isEmpty
            ? state.selectedEventId
            : selectedEventId,
      );
    } else if (selectedEventId != null && selectedEventId.isNotEmpty) {
      state = state.copyWith(selectedEventId: selectedEventId);
    }
    await refresh();
    if (selectedEventId != null &&
        selectedEventId.isNotEmpty &&
        state.events.any((event) => event.id == selectedEventId)) {
      state = state.copyWith(selectedEventId: selectedEventId);
    }
  }

  void setViewMode(CalendarViewMode mode) {
    state = state.copyWith(viewMode: mode);
    unawaited(refresh());
  }

  void selectDate(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    state = state.copyWith(
      selectedDate: normalized,
      focusedDate: normalized,
      selectedEventId: _firstEventIdForDate(state.events, normalized),
    );
  }

  void selectEvent(CalendarEvent? event) {
    state = state.copyWith(selectedEventId: event?.id);
    if (event != null) {
      state = state.copyWith(
        selectedDate: DateTime(
          event.displayStart.year,
          event.displayStart.month,
          event.displayStart.day,
        ),
      );
    }
  }

  void goToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    state = state.copyWith(focusedDate: today, selectedDate: today);
    unawaited(refresh());
  }

  void move(int amount) {
    final current = state.focusedDate;
    final next = switch (state.viewMode) {
      CalendarViewMode.month => DateTime(
        current.year,
        current.month + amount,
        1,
      ),
      CalendarViewMode.week => current.add(Duration(days: 7 * amount)),
      CalendarViewMode.day => current.add(Duration(days: amount)),
      CalendarViewMode.list => DateTime(
        current.year,
        current.month + amount,
        1,
      ),
    };
    state = state.copyWith(focusedDate: next, selectedDate: next);
    unawaited(refresh());
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
    unawaited(refresh());
  }

  void setStatusFilter(String? status) {
    state = state.copyWith(statusFilter: status);
    unawaited(refresh());
  }

  void setTeamFilter(String? teamId) {
    state = state.copyWith(teamFilter: teamId);
    unawaited(refresh());
  }

  void toggleCategory(String categoryId) {
    final next = {...state.visibleCategoryIds};
    if (next.contains(categoryId)) {
      next.remove(categoryId);
    } else {
      next.add(categoryId);
    }
    state = state.copyWith(visibleCategoryIds: next);
    unawaited(refresh());
  }

  Future<List<CalendarConflict>> checkConflicts(CalendarEvent event) async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      return const [];
    }
    final conflicts = await ref
        .read(calendarApiProvider)
        .checkConflicts(
          accessToken: session.accessToken,
          startAt: event.startAt,
          endAt: event.endAt,
          excludeEventId: event.id == 'new' ? null : event.id,
          location: event.location,
          azoomRoomId: event.azoomLinks.isEmpty
              ? null
              : event.azoomLinks.first.azoomRoomId,
          attendeeUserIds: [
            for (final attendee in event.attendees)
              if (attendee.userId != null && attendee.userId!.isNotEmpty)
                attendee.userId!,
          ],
        );
    state = state.copyWith(conflicts: conflicts);
    return conflicts;
  }

  Future<List<AvailabilitySuggestion>> suggestAvailability({
    int durationMinutes = 60,
  }) async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      return const [];
    }
    final start = DateTime(
      state.selectedDate.year,
      state.selectedDate.month,
      state.selectedDate.day,
      9,
    );
    final suggestions = await ref
        .read(calendarApiProvider)
        .suggestAvailability(
          accessToken: session.accessToken,
          rangeStart: start,
          rangeEnd: start.add(const Duration(days: 5)),
          durationMinutes: durationMinutes,
          attendeeUserIds:
              state.selectedEvent?.attendees
                  .map((item) => item.userId)
                  .whereType<String>()
                  .where((id) => id.isNotEmpty)
                  .toList() ??
              const [],
        );
    state = state.copyWith(availability: suggestions);
    return suggestions;
  }

  Future<CalendarEvent?> saveEvent(
    CalendarEvent event, {
    bool ignoreConflicts = false,
    String recurrenceEditScope = 'THIS',
  }) async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      state = state.copyWith(errorText: '로그인이 필요합니다.');
      return null;
    }
    state = state.copyWith(loading: true, errorText: null);
    try {
      final api = ref.read(calendarApiProvider);
      final saved = event.id == 'new'
          ? await api.createEvent(
              accessToken: session.accessToken,
              event: event,
              ignoreConflicts: ignoreConflicts,
            )
          : await api.updateEvent(
              accessToken: session.accessToken,
              event: event,
              recurrenceEditScope: recurrenceEditScope,
              ignoreConflicts: ignoreConflicts,
            );
      await refresh();
      state = state.copyWith(selectedEventId: saved.id, loading: false);
      return saved;
    } on Object catch (error) {
      state = state.copyWith(
        loading: false,
        errorText: _calendarErrorMessage(error),
      );
      return null;
    }
  }

  Future<void> deleteEvent(
    CalendarEvent event, {
    String recurrenceDeleteScope = 'THIS',
  }) async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      state = state.copyWith(errorText: '로그인이 필요합니다.');
      return;
    }
    state = state.copyWith(loading: true, errorText: null);
    try {
      await ref
          .read(calendarApiProvider)
          .deleteEvent(
            accessToken: session.accessToken,
            eventId: event.id,
            recurrenceDeleteScope: recurrenceDeleteScope,
          );
      await refresh();
      state = state.copyWith(selectedEventId: null, loading: false);
    } on Object catch (error) {
      state = state.copyWith(
        loading: false,
        errorText: _calendarErrorMessage(error),
      );
    }
  }

  Future<void> createCategory(String name, String color) async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      return;
    }
    await ref
        .read(calendarApiProvider)
        .createCategory(
          accessToken: session.accessToken,
          name: name,
          color: color,
        );
    await refresh();
  }

  _CalendarRange _queryRange(DateTime date, CalendarViewMode viewMode) {
    return switch (viewMode) {
      CalendarViewMode.month || CalendarViewMode.list => _CalendarRange(
        DateTime(date.year, date.month - 1, 1),
        DateTime(date.year, date.month + 2, 1),
      ),
      CalendarViewMode.week => _CalendarRange(
        _startOfWeek(date).subtract(const Duration(days: 7)),
        _startOfWeek(date).add(const Duration(days: 14)),
      ),
      CalendarViewMode.day => _CalendarRange(
        DateTime(
          date.year,
          date.month,
          date.day,
        ).subtract(const Duration(days: 1)),
        DateTime(date.year, date.month, date.day).add(const Duration(days: 2)),
      ),
    };
  }

  String? _firstEventIdForDate(List<CalendarEvent> events, DateTime date) {
    for (final event
        in events..sort((a, b) => a.displayStart.compareTo(b.displayStart))) {
      if (_sameDate(event.displayStart, date) ||
          _spansDate(event.displayStart, event.displayEnd, date)) {
        return event.id;
      }
    }
    return null;
  }
}

class _CalendarRange {
  const _CalendarRange(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

const Object _unchanged = Object();

String _calendarErrorMessage(Object error) {
  final text = error.toString();
  if (text.contains('401') || text.contains('403')) {
    return '캘린더 접근 권한을 확인해 주세요.';
  }
  if (text.contains('500') || text.contains('DioException')) {
    return '일정 정보를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.';
  }
  return '캘린더를 불러오는 중 문제가 발생했습니다.';
}

bool _sameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _spansDate(DateTime start, DateTime end, DateTime date) {
  final dayStart = DateTime(date.year, date.month, date.day);
  final dayEnd = dayStart.add(const Duration(days: 1));
  return start.isBefore(dayEnd) && end.isAfter(dayStart);
}

DateTime _startOfWeek(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}
