import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saves downloaded Android APK package to visible downloads', (
    tester,
  ) async {
    if (!Platform.isAndroid) {
      return;
    }
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    const channel = MethodChannel('ava/android_update');
    final basePath = await channel.invokeMethod<String>(
      'updateDownloadDirectory',
    );
    expect(basePath, isNotNull);
    expect(basePath!.trim(), isNotEmpty);

    final workingDir = Directory('${basePath.trim()}/ava_updates');
    await workingDir.create(recursive: true);
    final apk = File('${workingDir.path}/ava-update-channel-smoke.apk');
    await apk.writeAsBytes(const <int>[
      0x50,
      0x4B,
      0x03,
      0x04,
      0x41,
      0x56,
      0x41,
    ], flush: true);

    for (var attempt = 0; attempt < 2; attempt += 1) {
      final location = await channel.invokeMethod<String>('saveApkToDownloads', {
        'path': apk.path,
        'fileName': 'ava-update-channel-smoke.apk',
      });
      expect(location, isNotNull);
      expect(location!.trim(), contains('ava-update-channel-smoke.apk'));
    }
  });
}
