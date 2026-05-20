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
    bool forceLogin = false,
  }) async {
    state = const AsyncLoading();
    try {
      final session = await ref
          .watch(authApiProvider)
          .login(
            email: email,
            password: password,
            autoLogin: autoLogin,
            forceLogin: forceLogin,
          );
      final store = ref.watch(authSessionStoreProvider);
      if (autoLogin) {
        await store.write(session);
      } else {
        await store.clear();
      }
      state = AsyncData(AuthState(session: session));
    } on DuplicateLoginRequiredException catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    } on PendingApprovalRequiredException catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    } on Object catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<String> signup({
    required String email,
    required String password,
    required String displayName,
    required String companyName,
    required String department,
    required String emailVerificationCode,
    String? nickname,
    String? phoneNumber,
    String? contactEmail,
    String? gender,
    DateTime? birthDate,
  }) async {
    state = const AsyncLoading();
    try {
      final result = await ref
          .watch(authApiProvider)
          .signup(
            email: email,
            password: password,
            displayName: displayName,
            companyName: companyName,
            department: department,
            emailVerificationCode: emailVerificationCode,
            nickname: nickname,
            phoneNumber: phoneNumber,
            contactEmail: contactEmail,
            gender: gender,
            birthDate: birthDate,
          );
      await ref.watch(authSessionStoreProvider).clear();
      state = const AsyncData(AuthState());
      return result.message.isEmpty ? '관리자 승인 후 로그인 가능합니다.' : result.message;
    } on Object catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
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

  Future<void> forceLogoutLocally() async {
    await ref.watch(authSessionStoreProvider).clear();
    state = const AsyncData(AuthState());
  }
}
