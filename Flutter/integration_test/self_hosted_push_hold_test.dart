import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('holds AVA self hosted push service for task-state checks', (
    tester,
  ) async {
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
      'deviceId': 'integration-hold-emulator',
    });
    final status = await _waitForStatus(
      channel,
      (status) =>
          status['running'] == true &&
          ((status['lastConnectedAtMillis'] as int?) ?? 0) > 0,
    );
    expect(status?['running'], isTrue);
    debugPrint('SELF_PUSH_HOLD_READY status=$status');
    await Future<void>.delayed(const Duration(seconds: 120));
  });
}

Future<Map<String, dynamic>?> _waitForStatus(
  MethodChannel channel,
  bool Function(Map<String, dynamic> status) accept,
) async {
  for (var i = 0; i < 30; i += 1) {
    final status = await channel.invokeMapMethod<String, dynamic>('status');
    if (status != null && accept(status)) {
      return status;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return channel.invokeMapMethod<String, dynamic>('status');
}
