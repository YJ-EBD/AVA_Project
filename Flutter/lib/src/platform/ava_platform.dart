import 'dart:io';

import 'package:flutter/foundation.dart';

@visibleForTesting
TargetPlatform? debugAvaTargetPlatformOverride;

TargetPlatform? get _debugPlatformOverride {
  if (debugAvaTargetPlatformOverride != null) {
    return debugAvaTargetPlatformOverride;
  }
  TargetPlatform? override;
  assert(() {
    override = debugDefaultTargetPlatformOverride;
    return true;
  }());
  return override;
}

bool _isDesktopPlatform(TargetPlatform platform) {
  return platform == TargetPlatform.windows ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.linux;
}

bool _isMobilePlatform(TargetPlatform platform) {
  return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
}

bool get isAvaDesktopUiRuntime {
  final debugOverride = _debugPlatformOverride;
  if (debugOverride != null) {
    return _isDesktopPlatform(debugOverride);
  }
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return true;
  }
  return _isDesktopPlatform(defaultTargetPlatform);
}

bool get isAvaMobileUiRuntime {
  final debugOverride = _debugPlatformOverride;
  if (debugOverride != null) {
    return _isMobilePlatform(debugOverride);
  }
  if (Platform.isAndroid || Platform.isIOS) {
    return true;
  }
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return false;
  }
  return _isMobilePlatform(defaultTargetPlatform);
}

TargetPlatform get avaVisualTargetPlatform {
  if (isAvaDesktopUiRuntime) {
    return TargetPlatform.windows;
  }
  if (isAvaMobileUiRuntime) {
    return TargetPlatform.android;
  }
  return defaultTargetPlatform;
}
