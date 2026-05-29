import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/app_config.dart';
import '../../../platform/window_control.dart';
import '../../../shared/ava_dialog.dart';
import '../../push/application/mobile_push_controller.dart';
import '../application/auth_controller.dart';
import '../data/auth_api.dart';
import '../data/auth_models.dart';
import '../data/auth_realtime_client.dart';

class AuthSessionGate extends ConsumerStatefulWidget {
  const AuthSessionGate({
    required this.navigatorKey,
    required this.child,
    super.key,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<AuthSessionGate> createState() => _AuthSessionGateState();
}

class _AuthSessionGateState extends ConsumerState<AuthSessionGate> {
  AuthRealtimeClient? _client;
  StreamSubscription<AuthRealtimeEventDto>? _subscription;
  Timer? _sessionCheckTimer;
  String? _activeAccessToken;
  bool _handlingForcedLogout = false;

  @override
  void dispose() {
    _disposeRealtime();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AuthState>>(authControllerProvider, (previous, next) {
      _syncSession(next.value?.session);
    });

    final session = ref.watch(authControllerProvider).value?.session;
    _syncSession(session);

    return widget.child;
  }

  void _syncSession(AuthSession? session) {
    final accessToken = session?.accessToken;
    if (accessToken == _activeAccessToken) {
      return;
    }
    _disposeRealtime();
    _activeAccessToken = accessToken;
    unawaited(ref.read(mobilePushControllerProvider).sync(session));
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }

    final websocketUrl = ref.read(appConfigProvider).websocketUrl;
    final client = AuthRealtimeClient(
      websocketUrl: websocketUrl,
      accessToken: accessToken,
    );
    _client = client;
    _subscription = client.events.listen((event) {
      if (event.type == 'forced_logout') {
        unawaited(
          _handleForcedLogout(
            event.message.isEmpty ? '다른 기기에서 로그인하여 로그아웃되었습니다.' : event.message,
          ),
        );
      }
    });
    client.connect();
    _sessionCheckTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_checkCurrentSession(accessToken));
    });
  }

  Future<void> _checkCurrentSession(String accessToken) async {
    if (_handlingForcedLogout || accessToken != _activeAccessToken) {
      return;
    }
    try {
      await ref.read(authApiProvider).validateSession(accessToken);
    } on Object catch (error) {
      if (isSessionInvalidatedError(error)) {
        await _handleForcedLogout('다른 기기에서 로그인하여 로그아웃되었습니다.');
      }
    }
  }

  Future<void> _handleForcedLogout(String message) async {
    if (_handlingForcedLogout || !mounted) {
      return;
    }
    _handlingForcedLogout = true;
    _disposeRealtime();
    await WindowControl.showAuthWindow();
    await ref.read(authControllerProvider.notifier).forceLogoutLocally();

    if (!mounted) {
      return;
    }
    final navigationContext = widget.navigatorKey.currentContext ?? context;
    if (navigationContext.mounted) {
      navigationContext.go('/');
    }

    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 160));
    if (!mounted) {
      return;
    }
    final dialogContext = widget.navigatorKey.currentContext ?? context;
    if (!dialogContext.mounted) {
      return;
    }

    await showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) {
        return AvaDialog(
          title: '로그아웃되었습니다',
          subtitle: '계정 보호를 위해 현재 세션이 종료되었습니다.',
          icon: const Icon(
            Icons.lock_outline_rounded,
            color: Color(0xFF4F65C8),
            size: 24,
          ),
          actions: [
            AvaDialogButton(
              label: '확인',
              filled: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
          child: Text(
            message,
            style: const TextStyle(
              color: Color(0xFF102040),
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
    _handlingForcedLogout = false;
  }

  void _disposeRealtime() {
    _sessionCheckTimer?.cancel();
    _sessionCheckTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _client?.dispose();
    _client = null;
  }
}
