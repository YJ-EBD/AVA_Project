import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/presentation/auth_session_gate.dart';
import '../features/update/presentation/app_update_gate.dart';
import 'router.dart';

class AvaApp extends ConsumerWidget {
  const AvaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'AVA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF38BDF8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: router,
      builder: (context, child) {
        return AuthSessionGate(
          navigatorKey: appNavigatorKey,
          child: AppUpdateGate(
            navigatorKey: appNavigatorKey,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
