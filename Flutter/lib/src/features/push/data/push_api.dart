import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_version.dart';
import '../../auth/data/auth_api.dart';

final pushApiProvider = Provider<PushApi>((ref) {
  return PushApi(ref.watch(dioProvider));
});

class PushApi {
  const PushApi(this._dio);

  final Dio _dio;

  Future<void> heartbeat({
    required String accessToken,
    required String deviceId,
  }) async {
    await _dio.post<void>(
      '/api/push/devices/heartbeat',
      data: {
        'platform': defaultTargetPlatform.name,
        'appVersion': AppVersion.name,
        'deviceId': deviceId,
      },
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
  }

  Future<List<MobilePushEventDto>> events({
    required String accessToken,
    DateTime? after,
    int limit = 50,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/push/events',
      queryParameters: {
        if (after != null) 'after': after.toUtc().toIso8601String(),
        'limit': limit,
      },
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map(
          (json) => MobilePushEventDto.fromJson(json.cast<String, dynamic>()),
        )
        .toList();
  }
}

class MobilePushEventDto {
  const MobilePushEventDto({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.data,
    this.roomId,
    this.roomTitle,
    this.senderName,
    this.senderNickname,
    this.avatarColor,
    this.sourceType,
    this.sourceId,
  });

  factory MobilePushEventDto.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return MobilePushEventDto(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? 'AVA',
      body: json['body'] as String? ?? '',
      roomId: json['roomId'] as String?,
      roomTitle: json['roomTitle'] as String?,
      senderName: json['senderName'] as String?,
      senderNickname: json['senderNickname'] as String?,
      avatarColor: json['avatarColor'] as String?,
      sourceType: json['sourceType'] as String?,
      sourceId: json['sourceId'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      data: data is Map
          ? data.map((key, value) => MapEntry(key.toString(), value.toString()))
          : const {},
    );
  }

  final String id;
  final String type;
  final String title;
  final String body;
  final String? roomId;
  final String? roomTitle;
  final String? senderName;
  final String? senderNickname;
  final String? avatarColor;
  final String? sourceType;
  final String? sourceId;
  final DateTime? createdAt;
  final Map<String, String> data;
}
