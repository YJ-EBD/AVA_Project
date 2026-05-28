import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/signup_page.dart';
import '../features/ai/presentation/ava_ai_page.dart';
import '../features/home/presentation/home_page.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: appNavigatorKey,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const LoginPage()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupPage()),
      GoRoute(
        path: '/messenger',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/ava-ai-quick',
        name: 'avaAiQuick',
        builder: (context, state) => const AvaAiPage(quickPopup: true),
      ),
      GoRoute(
        path: '/ava-stock',
        name: 'avaStock',
        builder: (context, state) => const HomePage.avaStock(),
      ),
      GoRoute(
        path: '/calendar',
        name: 'calendar',
        builder: (context, state) => const HomePage.calendar(),
      ),
    ],
  );
});
