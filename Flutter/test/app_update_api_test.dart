import 'dart:io' as io;

import 'package:ava_flutter/src/config/app_config.dart';
import 'package:ava_flutter/src/features/update/data/app_update_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps Apple platforms to update endpoints', () {
    final api = AppUpdateApi(
      Dio(),
      const AppConfig(
        apiBaseUrl: 'http://example.com',
        websocketUrl: 'ws://example.com/ws',
      ),
    );

    final expected = io.Platform.isWindows
        ? 'windows'
        : io.Platform.isAndroid
        ? 'android'
        : io.Platform.isMacOS
        ? 'macos'
        : io.Platform.isIOS
        ? 'ios'
        : null;

    expect(api.currentUpdatePlatform, expected);
  });

  test('builds absolute update download URLs from relative paths', () {
    final api = AppUpdateApi(
      Dio(),
      const AppConfig(
        apiBaseUrl: 'http://112.166.136.198:8080/',
        websocketUrl: 'ws://112.166.136.198:8080/ws',
      ),
    );

    expect(
      api.absoluteDownloadUrl('/api/app-updates/macos/download/app.dmg'),
      'http://112.166.136.198:8080/api/app-updates/macos/download/app.dmg',
    );
  });
}
