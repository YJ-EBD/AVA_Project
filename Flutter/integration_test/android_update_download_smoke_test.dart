import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('downloads and saves the advertised Android APK update', (
    tester,
  ) async {
    if (!Platform.isAndroid) {
      return;
    }
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    const channel = MethodChannel('ava/android_update');
    final dio = Dio(BaseOptions(baseUrl: 'http://10.0.2.2:8080'));
    final manifestResponse = await dio.get<Map<String, dynamic>>(
      '/api/app-updates/android/latest',
      queryParameters: {'currentVersion': '0.1.307'},
    );
    final manifest = manifestResponse.data ?? const <String, dynamic>{};
    expect(manifest['updateAvailable'], isTrue);
    final fileName = manifest['fileName'] as String;
    final downloadUrl = manifest['downloadUrl'] as String;
    final expectedHash = manifest['sha256'] as String;

    final basePath = await channel.invokeMethod<String>(
      'updateDownloadDirectory',
    );
    final workingDir = Directory('${basePath!.trim()}/ava_updates');
    await workingDir.create(recursive: true);
    final apk = File('${workingDir.path}/$fileName');
    await dio.download(downloadUrl, apk.path);
    expect(await apk.length(), manifest['sizeBytes']);

    final actualHash = await crypto.sha256.bind(apk.openRead()).first;
    expect(actualHash.toString(), expectedHash);

    final location = await channel.invokeMethod<String>('saveApkToDownloads', {
      'path': apk.path,
      'fileName': fileName,
    });
    expect(location, isNotNull);
    expect(location!.trim(), contains(fileName));
  });
}
