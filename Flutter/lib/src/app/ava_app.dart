import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/auth/data/auth_api.dart';
import '../features/auth/presentation/auth_session_gate.dart';
import '../features/update/presentation/app_update_gate.dart';
import '../platform/ava_platform.dart';
import '../platform/window_control.dart';
import '../shared/ava_dialog.dart';
import 'router.dart';

class AvaApp extends ConsumerWidget {
  const AvaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final visualPlatform = avaVisualTargetPlatform;

    return MaterialApp.router(
      title: 'AVA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        platform: visualPlatform,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.light,
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        platform: visualPlatform,
        useMaterial3: true,
      ),
      routerConfig: router,
      builder: (context, child) {
        return _AvaTrayLifecycleGate(
          child: AuthSessionGate(
            navigatorKey: appNavigatorKey,
            child: AppUpdateGate(
              navigatorKey: appNavigatorKey,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}

class _AvaTrayLifecycleGate extends ConsumerStatefulWidget {
  const _AvaTrayLifecycleGate({required this.child});

  final Widget child;

  @override
  ConsumerState<_AvaTrayLifecycleGate> createState() =>
      _AvaTrayLifecycleGateState();
}

class _AvaTrayLifecycleGateState extends ConsumerState<_AvaTrayLifecycleGate> {
  final TextEditingController _passwordController = TextEditingController();
  bool _locked = false;
  bool _unlocking = false;
  bool _quickAvaAiOpen = false;
  bool? _lastQuickAvaAiEnabled;
  String _lockError = '';

  bool get _supportsNativeTrayMenu => Platform.isWindows || Platform.isMacOS;
  bool get _supportsNativeQuickAvaAi => Platform.isWindows || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    if (_supportsNativeTrayMenu) {
      WindowControl.setTrayActionHandler(_handleTrayAction);
    }
    if (_supportsNativeQuickAvaAi) {
      WindowControl.setQuickAvaAiHandler(_openQuickAvaAi);
    }
  }

  @override
  void dispose() {
    WindowControl.setTrayActionHandler(null);
    WindowControl.setQuickAvaAiHandler(null);
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).value?.session;
    _syncQuickAvaAiEnabled(session != null);
    if (session == null && _locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _locked = false;
            _lockError = '';
            _passwordController.clear();
          });
        }
      });
    }

    return Stack(
      children: [
        widget.child,
        if (_locked && session != null)
          Positioned.fill(
            child: _AvaLockOverlay(
              displayName: session.user.displayName,
              passwordController: _passwordController,
              unlocking: _unlocking,
              error: _lockError,
              onUnlock: _unlock,
              onLogout: _logoutFromLock,
            ),
          ),
      ],
    );
  }

  void _syncQuickAvaAiEnabled(bool enabled) {
    if (!_supportsNativeQuickAvaAi || _lastQuickAvaAiEnabled == enabled) {
      return;
    }
    _lastQuickAvaAiEnabled = enabled;
    unawaited(WindowControl.setQuickAvaAiEnabled(enabled));
  }

  Future<void> _handleTrayAction(String action) async {
    switch (action) {
      case 'open':
        await WindowControl.showMessengerWindow();
        if (_quickAvaAiOpen) {
          _quickAvaAiOpen = false;
          final context = appNavigatorKey.currentContext;
          final session = ref.read(authControllerProvider).value?.session;
          if (context != null && context.mounted && session != null) {
            context.go('/messenger');
            await WidgetsBinding.instance.endOfFrame;
            await WindowControl.expandMessenger();
            await WindowControl.showMessengerWindow();
          }
        }
        break;
      case 'lock':
        await WindowControl.showMessengerWindow();
        _lock();
        break;
      case 'logout':
        await WindowControl.showAuthWindow();
        await _logout();
        break;
    }
  }

  Future<void> _openQuickAvaAi() async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null) {
      _quickAvaAiOpen = false;
      final context = appNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        context.go('/');
      }
      await WindowControl.showAuthWindow();
      return;
    }
    final context = appNavigatorKey.currentContext;
    if (context == null || !context.mounted) {
      await WindowControl.showQuickAvaAiWindow();
      return;
    }
    _quickAvaAiOpen = true;
    context.go('/ava-ai-quick');
    await WidgetsBinding.instance.endOfFrame;
    await WindowControl.showQuickAvaAiWindow();
  }

  void _lock() {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null) {
      final context = appNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        context.go('/');
      }
      unawaited(WindowControl.showAuthWindow());
      return;
    }
    setState(() {
      _locked = true;
      _lockError = '';
      _passwordController.clear();
    });
  }

  Future<void> _unlock() async {
    final session = ref.read(authControllerProvider).value?.session;
    final password = _passwordController.text;
    if (session == null) {
      setState(() => _locked = false);
      return;
    }
    if (password.isEmpty || _unlocking) {
      setState(() => _lockError = '비밀번호를 입력해주세요.');
      return;
    }
    setState(() {
      _unlocking = true;
      _lockError = '';
    });
    try {
      await ref
          .read(authApiProvider)
          .verifyPassword(accessToken: session.accessToken, password: password);
      if (!mounted) {
        return;
      }
      setState(() {
        _locked = false;
        _unlocking = false;
        _lockError = '';
        _passwordController.clear();
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _unlocking = false;
        _lockError = '비밀번호가 올바르지 않습니다.';
      });
    }
  }

  Future<void> _logoutFromLock() async {
    await _logout();
  }

  Future<void> _logout() async {
    _quickAvaAiOpen = false;
    await WindowControl.showAuthWindow();
    setState(() {
      _locked = false;
      _lockError = '';
      _passwordController.clear();
    });
    await ref.read(authControllerProvider.notifier).logout();
    final context = appNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      context.go('/');
    }
  }
}

class _AvaLockOverlay extends StatelessWidget {
  const _AvaLockOverlay({
    required this.displayName,
    required this.passwordController,
    required this.unlocking,
    required this.error,
    required this.onUnlock,
    required this.onLogout,
  });

  final String displayName;
  final TextEditingController passwordController;
  final bool unlocking;
  final String error;
  final Future<void> Function() onUnlock;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE9F1F8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: AvaDialog(
            title: '잠금모드',
            subtitle: displayName.isEmpty
                ? 'AVA가 잠겨 있습니다.'
                : '$displayName님, 비밀번호를 입력해주세요.',
            icon: const Icon(
              Icons.lock_outline_rounded,
              color: Color(0xFF4F65C8),
              size: 24,
            ),
            actions: [
              AvaDialogButton(
                label: '로그아웃',
                onPressed: () => unawaited(onLogout()),
              ),
              AvaDialogButton(
                label: unlocking ? '확인 중' : '열기',
                filled: true,
                onPressed: unlocking ? null : () => unawaited(onUnlock()),
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: passwordController,
                  autofocus: true,
                  obscureText: true,
                  enabled: !unlocking,
                  onSubmitted: (_) => unlocking ? null : unawaited(onUnlock()),
                  decoration: const InputDecoration(
                    labelText: '비밀번호',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    error,
                    style: const TextStyle(
                      color: Color(0xFFC62828),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
