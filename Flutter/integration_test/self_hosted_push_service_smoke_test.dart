import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ava_flutter/src/features/messenger/data/chat_realtime_client.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('starts AVA self hosted push foreground service', (tester) async {
    if (!Platform.isAndroid) {
      return;
    }
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    try {
      final status = await Permission.notification.status;
      if (!status.isGranted && !status.isLimited) {
        await Permission.notification.request();
      }
    } on Object {
      // Android 12L and older do not expose a runtime notification permission.
    }
    const apiBaseUrl = 'http://10.0.2.2:8080';
    const websocketUrl = 'ws://10.0.2.2:8080/ws';
    final dio = Dio(BaseOptions(baseUrl: apiBaseUrl));
    final login = await dio.post<Map<String, dynamic>>(
      '/api/auth/login',
      data: {
        'email': 'admin@ava.admin',
        'password': 'Ava1234!',
        'rememberMe': true,
        'autoLogin': true,
        'forceLogin': true,
      },
    );
    final payload = login.data ?? const {};
    const channel = MethodChannel('ava/self_push');
    await channel.invokeMethod<void>('start', {
      'apiBaseUrl': apiBaseUrl,
      'websocketUrl': websocketUrl,
      'accessToken': payload['accessToken'] as String? ?? '',
      'refreshToken': payload['refreshToken'] as String? ?? '',
      'userId': (payload['user'] as Map?)?['id'] as String? ?? '',
      'deviceId': 'integration-emulator',
    });
    final status = await _waitForStatus(
      channel,
      (status) =>
          status['running'] == true &&
          ((status['lastConnectedAtMillis'] as int?) ?? 0) > 0,
    );
    expect(status?['running'], isTrue);

    final sender = await dio.post<Map<String, dynamic>>(
      '/api/auth/login',
      data: {
        'email': 'ava.invite.test01@abba-s.local',
        'password': 'Ava1234!',
        'rememberMe': true,
        'autoLogin': true,
        'forceLogin': true,
      },
    );
    final senderToken = sender.data?['accessToken'] as String? ?? '';
    final rooms = await dio.get<List<dynamic>>(
      '/api/chat/rooms',
      options: Options(headers: {'Authorization': 'Bearer $senderToken'}),
    );
    final room = (rooms.data ?? const [])
        .whereType<Map>()
        .cast<Map<dynamic, dynamic>>()
        .firstWhere((item) => item['type'] == 'GROUP');
    final foregroundLatency = await _sendAndWaitForPush(
      dio: dio,
      channel: channel,
      senderToken: senderToken,
      roomCode: room['code'] as String,
      previousEventAt: 0,
      content: 'AVA self-hosted push service event smoke',
    );
    final eventStatus = await _waitForStatus(
      channel,
      (status) =>
          ((status['lastEventAtMillis'] as int?) ?? 0) > 0 &&
          ((status['lastNotificationAtMillis'] as int?) ?? 0) > 0,
    );
    expect((eventStatus?['lastEventAtMillis'] as int?) ?? 0, greaterThan(0));
    expect(
      (eventStatus?['lastNotificationAtMillis'] as int?) ?? 0,
      greaterThan(0),
    );
    await channel.invokeMethod<void>('setActiveChatRoom', {
      'roomId': room['code'] as String,
    });
    final suppressedLatency = await _sendAndWaitForSuppressedPush(
      dio: dio,
      channel: channel,
      senderToken: senderToken,
      roomCode: room['code'] as String,
      previousEventAt: (eventStatus?['lastEventAtMillis'] as int?) ?? 0,
      previousSuppressedAt:
          (eventStatus?['lastSuppressedNotificationAtMillis'] as int?) ?? 0,
      content: 'AVA self-hosted push active room suppression smoke',
    );
    await channel.invokeMethod<void>('setActiveChatRoom', {'roomId': ''});
    final foregroundStatus = await channel.invokeMapMethod<String, dynamic>(
      'status',
    );
    final previousForegroundEventAt =
        (foregroundStatus?['lastEventAtMillis'] as int?) ??
        (eventStatus?['lastEventAtMillis'] as int?) ??
        0;
    await channel.invokeMethod<void>('moveToBackground');
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final backgroundLatency = await _sendAndWaitForPush(
      dio: dio,
      channel: channel,
      senderToken: senderToken,
      roomCode: room['code'] as String,
      previousEventAt: previousForegroundEventAt,
      content: 'AVA self-hosted push background event smoke',
    );
    final previousBackgroundEventAt =
        ((await channel.invokeMapMethod<String, dynamic>(
              'status',
            ))?['lastEventAtMillis']
            as int?) ??
        previousForegroundEventAt;
    final websocketLatency = await _sendRealtimeAndWaitForPush(
      websocketUrl: websocketUrl,
      channel: channel,
      senderToken: senderToken,
      roomCode: room['code'] as String,
      previousEventAt: previousBackgroundEventAt,
      content: 'AVA self-hosted push websocket event smoke',
    );
    debugPrint(
      'SELF_PUSH_LATENCY foregroundMs=$foregroundLatency suppressedMs=$suppressedLatency backgroundMs=$backgroundLatency websocketMs=$websocketLatency',
    );
    await channel.invokeMethod<void>('stop');
  });
}

Future<int> _sendAndWaitForSuppressedPush({
  required Dio dio,
  required MethodChannel channel,
  required String senderToken,
  required String roomCode,
  required int previousEventAt,
  required int previousSuppressedAt,
  required String content,
}) async {
  final started = DateTime.now();
  await dio.post<Map<String, dynamic>>(
    '/api/chat/rooms/$roomCode/messages',
    data: {
      'content': content,
      'silent': false,
      'spoiler': false,
      'mentions': const [],
    },
    options: Options(headers: {'Authorization': 'Bearer $senderToken'}),
  );
  final status = await _waitForStatus(
    channel,
    (status) =>
        ((status['lastEventAtMillis'] as int?) ?? 0) > previousEventAt &&
        ((status['lastSuppressedNotificationAtMillis'] as int?) ?? 0) >
            previousSuppressedAt,
  );
  expect(
    (status?['lastSuppressedNotificationAtMillis'] as int?) ?? 0,
    greaterThan(previousSuppressedAt),
  );
  return DateTime.now().difference(started).inMilliseconds;
}

Future<int> _sendAndWaitForPush({
  required Dio dio,
  required MethodChannel channel,
  required String senderToken,
  required String roomCode,
  required int previousEventAt,
  required String content,
}) async {
  final started = DateTime.now();
  await dio.post<Map<String, dynamic>>(
    '/api/chat/rooms/$roomCode/messages',
    data: {
      'content': content,
      'silent': false,
      'spoiler': false,
      'mentions': const [],
    },
    options: Options(headers: {'Authorization': 'Bearer $senderToken'}),
  );
  final status = await _waitForStatus(
    channel,
    (status) => ((status['lastEventAtMillis'] as int?) ?? 0) > previousEventAt,
  );
  expect(
    (status?['lastEventAtMillis'] as int?) ?? 0,
    greaterThan(previousEventAt),
  );
  return DateTime.now().difference(started).inMilliseconds;
}

Future<int> _sendRealtimeAndWaitForPush({
  required String websocketUrl,
  required MethodChannel channel,
  required String senderToken,
  required String roomCode,
  required int previousEventAt,
  required String content,
}) async {
  final started = DateTime.now();
  final client = ChatRealtimeClient(
    websocketUrl: websocketUrl,
    accessToken: senderToken,
    roomCode: roomCode,
  );
  client.connect();
  try {
    for (var i = 0; i < 30 && !client.isConnected; i += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(client.isConnected, isTrue);
    expect(client.send(content), isTrue);
    final status = await _waitForStatus(
      channel,
      (status) =>
          ((status['lastEventAtMillis'] as int?) ?? 0) > previousEventAt,
    );
    expect(
      (status?['lastEventAtMillis'] as int?) ?? 0,
      greaterThan(previousEventAt),
    );
    return DateTime.now().difference(started).inMilliseconds;
  } finally {
    client.dispose();
  }
}

Future<Map<String, dynamic>?> _waitForStatus(
  MethodChannel channel,
  bool Function(Map<String, dynamic> status) accept,
) async {
  for (var i = 0; i < 20; i += 1) {
    final status = await channel.invokeMapMethod<String, dynamic>('status');
    if (status != null && accept(status)) {
      return status;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return channel.invokeMapMethod<String, dynamic>('status');
}
