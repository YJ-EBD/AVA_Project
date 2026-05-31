import 'dart:io';

import 'package:ava_flutter/src/platform/ava_platform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('maps macOS desktop UI to Windows visuals', () {
    if (Platform.isMacOS) {
      expect(isAvaDesktopUiRuntime, isTrue);
      expect(avaVisualTargetPlatform, TargetPlatform.windows);
    }
  });

  test('maps debug iOS mobile UI to Android visuals', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    expect(isAvaMobileUiRuntime, isTrue);
    expect(avaVisualTargetPlatform, TargetPlatform.android);
  });
}
