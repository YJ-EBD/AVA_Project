import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

const _testEmail = String.fromEnvironment(
  'AVA_AZOOM_TEST_EMAIL',
  defaultValue: 'azoom-proxy-live@ava.local',
);
const _testPassword = String.fromEnvironment(
  'AVA_AZOOM_TEST_PASSWORD',
  defaultValue: 'ava-azoom-proxy-live-1234!',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('joins AZOOM LiveKit media through backend proxy', (
    tester,
  ) async {
    if (!Platform.isAndroid && !Platform.isWindows) {
      return;
    }
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final loopbackHost = Platform.isAndroid ? '10.0.2.2' : '127.0.0.1';
    final apiBaseUrl = 'http://$loopbackHost:8080';
    final dio = Dio(BaseOptions(baseUrl: apiBaseUrl));
    final login = await dio.post<Map<String, dynamic>>(
      '/api/auth/login',
      data: {
        'email': _testEmail,
        'password': _testPassword,
        'rememberMe': true,
        'autoLogin': true,
        'forceLogin': true,
      },
    );
    final token = login.data?['accessToken'] as String? ?? '';
    final headers = Options(headers: {'Authorization': 'Bearer $token'});
    final channels = await dio.get<Map<String, dynamic>>(
      '/api/azoom/channels',
      options: headers,
    );
    final voiceChannels =
        (channels.data?['voiceChannels'] as List?)?.cast<dynamic>() ??
        const <dynamic>[];
    expect(voiceChannels, isNotEmpty);
    final channel = (voiceChannels.first as Map).cast<String, dynamic>();
    final join = await dio.post<Map<String, dynamic>>(
      '/api/azoom/voice-channels/${channel['id']}/join',
      options: headers,
    );
    final liveKit = (join.data?['liveKit'] as Map).cast<String, dynamic>();
    expect(liveKit['enabled'], isTrue);
    expect((liveKit['token'] as String?)?.isNotEmpty, isTrue);

    final room = lk.Room();
    try {
      await room
          .connect(
            'ws://$loopbackHost:8080',
            liveKit['token'] as String,
            connectOptions: const lk.ConnectOptions(autoSubscribe: true),
          )
          .timeout(const Duration(seconds: 25));
      expect(room.connectionState, lk.ConnectionState.connected);
      debugPrint('AZOOM_LIVEKIT_CONNECTED room=${liveKit['roomName']}');
    } finally {
      await room.disconnect();
      await room.dispose();
      await dio.post<void>(
        '/api/azoom/voice-channels/${channel['id']}/leave',
        options: headers,
      );
    }
  });
}
