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
    bool forceLogin = false,
  }) async {
    late final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        '/api/auth/login',
        data: {
          'email': email,
          'password': password,
          'rememberMe': autoLogin,
          'autoLogin': autoLogin,
          'forceLogin': forceLogin,
        },
      );
    } on DioException catch (error) {
      if (_isDuplicateLogin(error)) {
        throw DuplicateLoginRequiredException(
          _messageFromResponse(error) ?? '다른 기기에서 로그인 중입니다.',
        );
      }
      if (_isPendingApproval(error)) {
        throw PendingApprovalRequiredException(
          _messageFromResponse(error) ?? '관리자 승인 후 로그인 가능합니다.',
        );
      }
      rethrow;
    }

    return AuthSession.fromJson(response.data ?? const {});
  }

  Future<SignupResult> signup({
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
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/auth/signup',
      data: {
        'email': email,
        'password': password,
        'displayName': displayName,
        'companyName': companyName,
        if (nickname != null && nickname.isNotEmpty) 'nickname': nickname,
        if (phoneNumber != null && phoneNumber.isNotEmpty)
          'phoneNumber': phoneNumber,
        if (contactEmail != null && contactEmail.isNotEmpty)
          'contactEmail': contactEmail,
        'emailVerificationCode': emailVerificationCode,
        if (gender != null && gender.isNotEmpty) 'gender': gender,
        'department': department,
        if (birthDate != null)
          'birthDate':
              '${birthDate.year.toString().padLeft(4, '0')}-${birthDate.month.toString().padLeft(2, '0')}-${birthDate.day.toString().padLeft(2, '0')}',
      },
    );

    return SignupResult.fromJson(response.data ?? const {});
  }

  Future<void> sendEmailVerificationCode(String email) async {
    await _dio.post<Map<String, dynamic>>(
      '/api/auth/email-verifications',
      data: {'email': email},
    );
  }

  Future<void> confirmEmailVerificationCode({
    required String email,
    required String code,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/api/auth/email-verifications/confirm',
      data: {'email': email, 'code': code},
    );
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

  Future<void> validateSession(String accessToken) async {
    await _dio.get<void>(
      '/api/auth/session',
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

bool _isDuplicateLogin(DioException error) {
  final data = error.response?.data;
  return error.response?.statusCode == 409 &&
      data is Map &&
      data['code'] == 'DUPLICATE_LOGIN';
}

bool _isPendingApproval(DioException error) {
  final data = error.response?.data;
  return error.response?.statusCode == 403 &&
      data is Map &&
      data['code'] == 'PENDING_APPROVAL';
}

String? _messageFromResponse(DioException error) {
  final data = error.response?.data;
  if (data is Map && data['message'] is String) {
    return data['message'] as String;
  }
  return null;
}

class DuplicateLoginRequiredException implements Exception {
  const DuplicateLoginRequiredException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PendingApprovalRequiredException implements Exception {
  const PendingApprovalRequiredException(this.message);

  final String message;

  @override
  String toString() => message;
}

bool isDuplicateLoginRequired(Object error) {
  return error is DuplicateLoginRequiredException;
}

bool isPendingApprovalRequired(Object error) {
  return error is PendingApprovalRequiredException;
}

bool isSessionInvalidatedError(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    return status == 401 || status == 403;
  }
  return false;
}

String authErrorMessage(Object error) {
  if (error is DuplicateLoginRequiredException) {
    return error.message;
  }
  if (error is PendingApprovalRequiredException) {
    return error.message;
  }
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
