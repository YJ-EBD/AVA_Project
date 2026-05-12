import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_config.dart';
import 'auth_models.dart';

final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  return Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );
});

final authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(dioProvider));
});

class AuthApi {
  const AuthApi(this._dio);

  final Dio _dio;

  Future<AuthSession> login({
    required String email,
    required String password,
    required bool autoLogin,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/auth/login',
      data: {
        'email': email,
        'password': password,
        'rememberMe': autoLogin,
        'autoLogin': autoLogin,
      },
    );

    return AuthSession.fromJson(response.data ?? const {});
  }

  Future<AuthSession> signup({
    required String email,
    required String password,
    required String displayName,
    required String department,
    String? nickname,
    String? phoneNumber,
    DateTime? birthDate,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/auth/signup',
      data: {
        'email': email,
        'password': password,
        'displayName': displayName,
        if (nickname != null && nickname.isNotEmpty) 'nickname': nickname,
        if (phoneNumber != null && phoneNumber.isNotEmpty)
          'phoneNumber': phoneNumber,
        'department': department,
        if (birthDate != null)
          'birthDate':
              '${birthDate.year.toString().padLeft(4, '0')}-${birthDate.month.toString().padLeft(2, '0')}-${birthDate.day.toString().padLeft(2, '0')}',
      },
    );

    return AuthSession.fromJson(response.data ?? const {});
  }

  Future<AuthSession> refresh(String refreshToken) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/auth/refresh',
      data: {'refreshToken': refreshToken},
    );

    return AuthSession.fromJson(response.data ?? const {});
  }

  Future<void> logout(String accessToken) async {
    await _dio.post<void>(
      '/api/auth/logout',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
  }

  Future<void> updatePresence({
    required String accessToken,
    required String status,
  }) async {
    await _dio.put<void>(
      '/api/users/me/presence',
      data: {'status': status},
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
  }
}

String authErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.connectionError) {
      return 'Spring Boot 서버에 연결할 수 없습니다.';
    }
  }

  return '요청을 처리하지 못했습니다.';
}
