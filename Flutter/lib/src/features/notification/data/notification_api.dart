import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_api.dart';

final notificationApiProvider = Provider<NotificationApi>((ref) {
  return NotificationApi(ref.watch(dioProvider));
});

class NotificationApi {
  const NotificationApi(this._dio);

  final Dio _dio;

  Future<NotificationListDto> list({required String accessToken}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/notifications',
      options: _authOptions(accessToken),
    );
    return NotificationListDto.fromJson(response.data ?? const {});
  }

  Future<NotificationDto> markRead({
    required String accessToken,
    required String notificationId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/notifications/$notificationId/read',
      options: _authOptions(accessToken),
    );
    return NotificationDto.fromJson(response.data ?? const {});
  }

  Future<NotificationListDto> markAllRead({required String accessToken}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/notifications/read-all',
      options: _authOptions(accessToken),
    );
    return NotificationListDto.fromJson(response.data ?? const {});
  }

  Options _authOptions(String accessToken) {
    return Options(headers: {'Authorization': 'Bearer $accessToken'});
  }
}

class NotificationListDto {
  const NotificationListDto({required this.unreadCount, required this.items});

  factory NotificationListDto.fromJson(Map<String, dynamic> json) {
    return NotificationListDto(
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      items: [
        for (final item in json['items'] as List<dynamic>? ?? const [])
          if (item is Map)
            NotificationDto.fromJson(item.cast<String, dynamic>()),
      ],
    );
  }

  final int unreadCount;
  final List<NotificationDto> items;
}

class NotificationDto {
  const NotificationDto({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.sourceType,
    required this.sourceId,
    required this.createdAt,
    required this.readAt,
    required this.read,
  });

  factory NotificationDto.fromJson(Map<String, dynamic> json) {
    return NotificationDto(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      sourceType: json['sourceType'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      readAt: DateTime.tryParse(json['readAt'] as String? ?? ''),
      read: json['read'] as bool? ?? false,
    );
  }

  final String id;
  final String type;
  final String title;
  final String body;
  final String sourceType;
  final String sourceId;
  final DateTime? createdAt;
  final DateTime? readAt;
  final bool read;
}
