import 'package:flutter/services.dart';

class AzoomVoicePlatform {
  const AzoomVoicePlatform._();

  static const _channel = MethodChannel('ava/azoom_voice');
  static Future<void> Function(String action)? _actionHandler;
  static bool _handlerConfigured = false;

  static void setActionHandler(Future<void> Function(String action)? handler) {
    _actionHandler = handler;
    _ensureHandler();
  }

  static Future<void> startSession({
    required String apiBaseUrl,
    required String accessToken,
    required String channelId,
    required String channelName,
    required String participantName,
    required String avatarColor,
    required String avatarImageUrl,
    required bool muted,
    required bool deafened,
    required bool cameraEnabled,
    required bool screenSharing,
    required bool overlayEnabled,
  }) async {
    await _invoke('startSession', {
      'apiBaseUrl': apiBaseUrl,
      'accessToken': accessToken,
      'channelId': channelId,
      'channelName': channelName,
      'participantName': participantName,
      'avatarColor': avatarColor,
      'avatarImageUrl': avatarImageUrl,
      'muted': muted,
      'deafened': deafened,
      'cameraEnabled': cameraEnabled,
      'screenSharing': screenSharing,
      'overlayEnabled': overlayEnabled,
    });
  }

  static Future<void> updateSession({
    required String channelName,
    required String participantName,
    required String avatarColor,
    required String avatarImageUrl,
    required bool muted,
    required bool deafened,
    required bool cameraEnabled,
    required bool screenSharing,
    required bool overlayEnabled,
  }) async {
    await _invoke('updateSession', {
      'channelName': channelName,
      'participantName': participantName,
      'avatarColor': avatarColor,
      'avatarImageUrl': avatarImageUrl,
      'muted': muted,
      'deafened': deafened,
      'cameraEnabled': cameraEnabled,
      'screenSharing': screenSharing,
      'overlayEnabled': overlayEnabled,
    });
  }

  static Future<void> stopSession() async {
    await _invoke('stopSession');
  }

  static Future<bool> areNotificationsEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('areNotificationsEnabled') ??
          true;
    } on MissingPluginException {
      return true;
    }
  }

  static Future<bool> areVoiceNotificationsEnabled() async {
    try {
      return await _channel.invokeMethod<bool>(
            'areVoiceNotificationsEnabled',
          ) ??
          true;
    } on MissingPluginException {
      return true;
    }
  }

  static Future<void> openNotificationSettings() async {
    await _invoke('openNotificationSettings');
  }

  static Future<void> openVoiceNotificationSettings() async {
    await _invoke('openVoiceNotificationSettings');
  }

  static Future<void> requestOverlayPermission() async {
    await _invoke('requestOverlayPermission');
  }

  static void _ensureHandler() {
    if (_handlerConfigured) {
      return;
    }
    _handlerConfigured = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'azoomVoiceAction') {
        return null;
      }
      final args = (call.arguments as Map?)?.cast<Object?, Object?>();
      final action = args?['action'] as String? ?? '';
      final handler = _actionHandler;
      if (handler != null && action.isNotEmpty) {
        await handler(action);
      }
      return null;
    });
  }

  static Future<void> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Non-Android targets and tests do not provide this native service.
    }
  }
}
