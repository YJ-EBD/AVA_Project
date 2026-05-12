import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_api.dart';
import '../data/auth_models.dart';
import '../data/auth_session_store.dart';

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthState {
  const AuthState({this.session});

  final AuthSession? session;

  bool get isAuthenticated => session != null;
}

class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final store = ref.watch(authSessionStoreProvider);
    final stored = await store.read();
    if (stored == null || stored.refreshToken.isEmpty) {
      return const AuthState();
    }

    try {
      final refreshed = await ref
          .watch(authApiProvider)
          .refresh(stored.refreshToken);
      await store.write(refreshed);
      return AuthState(session: refreshed);
    } on Object {
      await store.clear();
      return const AuthState();
    }
  }

  Future<void> login({
    required String email,
    required String password,
    required bool autoLogin,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final session = await ref
          .watch(authApiProvider)
          .login(email: email, password: password, autoLogin: autoLogin);
      final store = ref.watch(authSessionStoreProvider);
      if (autoLogin) {
        await store.write(session);
      } else {
        await store.clear();
      }
      return AuthState(session: session);
    });
  }

  Future<void> signup({
    required String email,
    required String password,
    required String displayName,
    required String department,
    String? nickname,
    String? phoneNumber,
    DateTime? birthDate,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final session = await ref
          .watch(authApiProvider)
          .signup(
            email: email,
            password: password,
            displayName: displayName,
            department: department,
            nickname: nickname,
            phoneNumber: phoneNumber,
            birthDate: birthDate,
          );
      await ref.watch(authSessionStoreProvider).write(session);
      return AuthState(session: session);
    });
  }

  Future<void> logout() async {
    final session = state.value?.session;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (session != null) {
        await ref.watch(authApiProvider).logout(session.accessToken);
      }
      await ref.watch(authSessionStoreProvider).clear();
      return const AuthState();
    });
  }
}
