import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/company_scope.dart';
import '../../auth/data/auth_api.dart';
import '../domain/calendar_models.dart';

final calendarApiProvider = Provider<CalendarApi>((ref) {
  return CalendarApi(ref.watch(dioProvider), ref.watch(activeCompanyProvider));
});

class CalendarApi {
  const CalendarApi(this._dio, this._activeCompany);

  final Dio _dio;
  final String? _activeCompany;

  Future<List<CalendarEvent>> events({
    required String accessToken,
    DateTime? startAt,
    DateTime? endAt,
    String? categoryId,
    String? teamId,
    String? status,
    String? query,
    int? page,
    int? size,
  }) async {
    final queryParameters = <String, Object?>{
      if (startAt != null) 'startAt': startAt.toUtc().toIso8601String(),
      if (endAt != null) 'endAt': endAt.toUtc().toIso8601String(),
      if (categoryId != null && categoryId.isNotEmpty) 'categoryId': categoryId,
      if (teamId != null && teamId.isNotEmpty) 'teamId': teamId,
      if (status != null && status.isNotEmpty) 'status': status,
      if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
    };
    if (page != null) {
      queryParameters['page'] = page;
    }
    if (size != null) {
      queryParameters['size'] = size;
    }
    final response = await _dio.get<List<dynamic>>(
      '/api/calendar/events',
      queryParameters: queryParameters,
      options: _authOptions(accessToken),
    );
    return [
      for (final item in response.data ?? const [])
        CalendarEvent.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  Future<CalendarEvent> event({
    required String accessToken,
    required String eventId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/calendar/events/$eventId',
      options: _authOptions(accessToken),
    );
    return CalendarEvent.fromJson(response.data ?? const {});
  }

  Future<CalendarEvent> createEvent({
    required String accessToken,
    required CalendarEvent event,
    bool ignoreConflicts = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/calendar/events',
      data: event.toRequest(ignoreConflicts: ignoreConflicts),
      options: _authOptions(accessToken),
    );
    return CalendarEvent.fromJson(response.data ?? const {});
  }

  Future<CalendarEvent> updateEvent({
    required String accessToken,
    required CalendarEvent event,
    String recurrenceEditScope = 'THIS',
    bool ignoreConflicts = false,
  }) async {
    final data = event.toRequest(
      ignoreConflicts: ignoreConflicts,
      includeEmptyCollections: true,
    )..['recurrenceEditScope'] = recurrenceEditScope;
    final response = await _dio.patch<Map<String, dynamic>>(
      '/api/calendar/events/${event.id}',
      data: data,
      options: _authOptions(accessToken),
    );
    return CalendarEvent.fromJson(response.data ?? const {});
  }

  Future<void> deleteEvent({
    required String accessToken,
    required String eventId,
    String recurrenceDeleteScope = 'THIS',
  }) async {
    await _dio.delete<void>(
      '/api/calendar/events/$eventId',
      queryParameters: {'recurrenceDeleteScope': recurrenceDeleteScope},
      options: _authOptions(accessToken),
    );
  }

  Future<List<CalendarCategory>> categories(String accessToken) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/calendar/categories',
      options: _authOptions(accessToken),
    );
    return [
      for (final item in response.data ?? const [])
        CalendarCategory.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  Future<CalendarCategory> createCategory({
    required String accessToken,
    required String name,
    required String color,
    String scope = 'USER',
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/calendar/categories',
      data: {'name': name, 'color': color, 'scope': scope},
      options: _authOptions(accessToken),
    );
    return CalendarCategory.fromJson(response.data ?? const {});
  }

  Future<List<CalendarConflict>> checkConflicts({
    required String accessToken,
    required DateTime startAt,
    required DateTime endAt,
    String? excludeEventId,
    String? location,
    String? azoomRoomId,
    List<String> attendeeUserIds = const [],
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/calendar/conflicts/check',
      data: {
        'startAt': startAt.toUtc().toIso8601String(),
        'endAt': endAt.toUtc().toIso8601String(),
        if (attendeeUserIds.isNotEmpty) 'attendeeUserIds': attendeeUserIds,
        if (excludeEventId != null && excludeEventId.isNotEmpty)
          'excludeEventId': excludeEventId,
        if (location != null && location.isNotEmpty) 'location': location,
        if (azoomRoomId != null && azoomRoomId.isNotEmpty)
          'azoomRoomId': azoomRoomId,
      },
      options: _authOptions(accessToken),
    );
    final data = response.data ?? const {};
    return [
      for (final item in data['conflicts'] as List? ?? const [])
        CalendarConflict.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  Future<List<AvailabilitySuggestion>> suggestAvailability({
    required String accessToken,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    int durationMinutes = 60,
    List<String> attendeeUserIds = const [],
  }) async {
    final response = await _dio.post<List<dynamic>>(
      '/api/calendar/availability/suggest',
      data: {
        if (attendeeUserIds.isNotEmpty) 'attendeeUserIds': attendeeUserIds,
        'rangeStart': rangeStart.toUtc().toIso8601String(),
        'rangeEnd': rangeEnd.toUtc().toIso8601String(),
        'durationMinutes': durationMinutes,
        'workdayStart': '09:00',
        'workdayEnd': '18:00',
        'excludedTimes': [
          {
            'startAt': DateTime(
              rangeStart.year,
              rangeStart.month,
              rangeStart.day,
              12,
            ).toUtc().toIso8601String(),
            'endAt': DateTime(
              rangeStart.year,
              rangeStart.month,
              rangeStart.day,
              13,
            ).toUtc().toIso8601String(),
          },
        ],
      },
      options: _authOptions(accessToken),
    );
    return [
      for (final item in response.data ?? const [])
        AvailabilitySuggestion.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  Future<Map<String, dynamic>> summaryToday(String accessToken) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/calendar/summary/today',
      options: _authOptions(accessToken),
    );
    return response.data ?? const {};
  }

  Future<Map<String, dynamic>> summaryWeek(String accessToken) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/calendar/summary/week',
      options: _authOptions(accessToken),
    );
    return response.data ?? const {};
  }

  Future<List<Map<String, dynamic>>> tools(String accessToken) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/calendar/tools',
      options: _authOptions(accessToken),
    );
    return [
      for (final item in response.data ?? const [])
        (item as Map).cast<String, dynamic>(),
    ];
  }

  Options _authOptions(String accessToken) {
    return Options(
      headers: {
        'Authorization': 'Bearer $accessToken',
        if (_activeCompany != null && _activeCompany.isNotEmpty)
          avaCompanyHeader: _activeCompany,
      },
      receiveTimeout: const Duration(seconds: 30),
    );
  }
}
