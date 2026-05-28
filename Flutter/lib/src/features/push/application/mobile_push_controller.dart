import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../../../config/app_config.dart';
import '../../../platform/window_control.dart';
import '../../auth/data/auth_models.dart';
import '../data/push_api.dart';

const String _mobilePushDeviceIdKey = 'ava.mobile_push.device_id.v2';
const String _lastEventAtPrefix = 'ava.self_push.last_event_at.v1';

@visibleForTesting
String mobilePushEventRoomIdForTest(MobilePushEventDto event) {
  return _mobilePushEventRoomId(event);
}

@visibleForTesting
bool shouldSuppressActiveChatRoomPushForTest({
  required MobilePushEventDto event,
  required String activeChatRoomId,
  required AppLifecycleState? lifecycleState,
}) {
  return _shouldSuppressActiveChatRoomPushEvent(
    event: event,
    activeChatRoomId: activeChatRoomId,
    lifecycleState: lifecycleState,
  );
}

String _mobilePushEventRoomId(MobilePushEventDto event) {
  return (event.roomId ??
          event.data['roomCode'] ??
          event.data['roomId'] ??
          event.sourceId ??
          '')
      .trim();
}

bool _shouldSuppressActiveChatRoomPushEvent({
  required MobilePushEventDto event,
  required String activeChatRoomId,
  required AppLifecycleState? lifecycleState,
}) {
  if (event.type != 'chat_message' || activeChatRoomId.isEmpty) {
    return false;
  }
  if (lifecycleState != null && lifecycleState != AppLifecycleState.resumed) {
    return false;
  }
  final roomId = _mobilePushEventRoomId(event);
  return roomId.isNotEmpty && roomId == activeChatRoomId;
}

final mobilePushControllerProvider = Provider<MobilePushController>((ref) {
  final controller = MobilePushController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

class MobilePushBootstrap {
  const MobilePushBootstrap._();

  static Future<bool> ensureInitialized() async {
    return Platform.isAndroid || Platform.isIOS;
  }
}

class MobilePushController {
  MobilePushController(this._ref);

  static const MethodChannel _nativeChannel = MethodChannel('ava/self_push');

  final Ref _ref;
  String? _sessionToken;
  String? _sessionUserId;
  String _activeChatRoomId = '';
  DateTime? _lastSyncAt;
  StompClient? _client;
  StompUnsubscribe? _unsubscribe;

  Future<void> sync(AuthSession? session) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    if (session == null || session.accessToken.isEmpty) {
      await setActiveChatRoom(null);
      await _stopNativePush();
      _stopRealtime();
      _sessionToken = null;
      _sessionUserId = null;
      _lastSyncAt = null;
      return;
    }

    final now = DateTime.now();
    final sameSession = _sessionToken == session.accessToken;
    if (sameSession &&
        _lastSyncAt != null &&
        now.difference(_lastSyncAt!) < const Duration(seconds: 20)) {
      return;
    }
    _sessionToken = session.accessToken;
    _sessionUserId = session.user.id;
    _lastSyncAt = now;

    await _requestNotificationPermission();
    final deviceId = await _deviceId();
    unawaited(
      _ref
          .read(pushApiProvider)
          .heartbeat(accessToken: session.accessToken, deviceId: deviceId)
          .catchError((Object _) {}),
    );

    if (Platform.isAndroid) {
      await _startNativePush(session, deviceId);
      await _sendActiveChatRoomToNative(_activeChatRoomId);
      await _showBacklog(session);
      return;
    }

    _startDartRealtime(session);
    await _showBacklog(session);
  }

  Future<void> setActiveChatRoom(String? roomId) async {
    final normalized = roomId?.trim() ?? '';
    if (_activeChatRoomId == normalized) {
      return;
    }
    _activeChatRoomId = normalized;
    await _sendActiveChatRoomToNative(normalized);
  }

  Future<void> _sendActiveChatRoomToNative(String roomId) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _nativeChannel.invokeMethod<void>('setActiveChatRoom', {
        'roomId': roomId,
      });
    } on Object {
      // Active-room suppression is a foreground-only polish path.
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final status = await Permission.notification.status;
      if (!status.isGranted && !status.isLimited) {
        await Permission.notification.request();
      }
    } on Object {
      // Android 12L and older do not have a runtime notification permission.
    }
  }

  Future<void> _startNativePush(AuthSession session, String deviceId) async {
    try {
      final config = _ref.read(appConfigProvider);
      await _nativeChannel.invokeMethod<void>('start', {
        'apiBaseUrl': config.apiBaseUrl,
        'websocketUrl': config.websocketUrl,
        'accessToken': session.accessToken,
        'refreshToken': session.refreshToken,
        'userId': session.user.id,
        'deviceId': deviceId,
      });
    } on Object {
      _startDartRealtime(session);
    }
  }

  Future<void> _stopNativePush() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _nativeChannel.invokeMethod<void>('stop');
    } on Object {
      // Stopping push must never block logout.
    }
  }

  void _startDartRealtime(AuthSession session) {
    if (_client != null && _sessionToken == session.accessToken) {
      return;
    }
    _stopRealtime();
    final headers = {'Authorization': 'Bearer ${session.accessToken}'};
    final client = StompClient(
      config: StompConfig(
        url: _ref.read(appConfigProvider).websocketUrl,
        stompConnectHeaders: headers,
        webSocketConnectHeaders: headers,
        reconnectDelay: const Duration(seconds: 3),
        connectionTimeout: const Duration(seconds: 8),
        onConnect: (_) {
          _unsubscribe = _client?.subscribe(
            destination: '/user/queue/mobile-push',
            callback: (frame) {
              final body = frame.body;
              if (body == null || body.isEmpty) {
                return;
              }
              final json = jsonDecode(body);
              if (json is Map) {
                unawaited(
                  _showEvent(
                    MobilePushEventDto.fromJson(json.cast<String, dynamic>()),
                  ),
                );
              }
            },
          );
        },
        onWebSocketError: (_) {},
        onStompError: (_) {},
      ),
    );
    _client = client..activate();
  }

  void _stopRealtime() {
    _unsubscribe?.call();
    _unsubscribe = null;
    _client?.deactivate();
    _client = null;
  }

  Future<void> _showBacklog(AuthSession session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _lastEventAtKey(session.user.id);
      final rawAfter = prefs.getString(key);
      final after = DateTime.tryParse(rawAfter ?? '');
      if (after == null) {
        await prefs.setString(key, DateTime.now().toUtc().toIso8601String());
        return;
      }
      final events = await _ref
          .read(pushApiProvider)
          .events(accessToken: session.accessToken, after: after, limit: 30);
      for (final event in events) {
        await _showEvent(event);
      }
    } on Object {
      // Live websocket delivery remains the primary path.
    }
  }

  Future<void> _showEvent(MobilePushEventDto event) async {
    if (!_isDisplayable(event)) {
      await _rememberEvent(event);
      return;
    }
    if (_shouldSuppressActiveChatRoom(event)) {
      await _rememberEvent(event);
      return;
    }
    final roomId = _mobilePushEventRoomId(event);
    await WindowControl.showChatNotification(
      roomId: roomId.isEmpty ? event.id : roomId,
      roomTitle: event.roomTitle ?? event.title,
      senderName: event.senderName ?? event.title,
      senderNickname: event.senderNickname ?? event.senderName ?? event.title,
      avatarColor: event.avatarColor ?? '#0B63CE',
      body: event.body,
    );
    await _rememberEvent(event);
  }

  bool _isDisplayable(MobilePushEventDto event) {
    return event.type == 'chat_message' ||
        event.type == 'notification' ||
        event.type == 'azoom';
  }

  bool _shouldSuppressActiveChatRoom(MobilePushEventDto event) {
    return _shouldSuppressActiveChatRoomPushEvent(
      event: event,
      activeChatRoomId: _activeChatRoomId,
      lifecycleState: WidgetsBinding.instance.lifecycleState,
    );
  }

  Future<void> _rememberEvent(MobilePushEventDto event) async {
    final createdAt = event.createdAt;
    final userId = _sessionUserId;
    if (createdAt == null || userId == null || userId.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastEventAtKey(userId),
      createdAt.toUtc().toIso8601String(),
    );
  }

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_mobilePushDeviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final value =
        '${defaultTargetPlatform.name}-${DateTime.now().microsecondsSinceEpoch}';
    await prefs.setString(_mobilePushDeviceIdKey, value);
    return value;
  }

  String _lastEventAtKey(String userId) => '$_lastEventAtPrefix.$userId';

  void dispose() {
    _stopRealtime();
  }
}
