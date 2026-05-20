import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/company_scope.dart';
import '../../auth/data/auth_api.dart';

final adminApiProvider = Provider<AdminApi>((ref) {
  return AdminApi(ref.watch(dioProvider), ref.watch(activeCompanyProvider));
});

class AdminApi {
  const AdminApi(this._dio, [this._activeCompany]);

  final Dio _dio;
  final String? _activeCompany;

  Future<AdminOverviewDto> overview(String accessToken) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/admin/overview',
      options: _options(accessToken),
    );
    return AdminOverviewDto.fromJson(response.data ?? const {});
  }

  Future<List<AdminUserDto>> users(String accessToken) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/admin/users',
      options: _options(accessToken),
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map((item) => AdminUserDto.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  Future<List<AdminUserDto>> pendingApprovals(String accessToken) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/admin/users/pending-approvals',
      options: _options(accessToken),
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map((item) => AdminUserDto.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  Future<AdminUserDto> approveUser({
    required String accessToken,
    required String userId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/admin/users/$userId/approve',
      options: _options(accessToken),
    );
    return AdminUserDto.fromJson(response.data ?? const {});
  }

  Future<AdminUserDto> updateUser({
    required String accessToken,
    required String userId,
    String? displayName,
    String? role,
    bool? enabled,
    String? companyName,
    String? department,
    String? position,
  }) async {
    final data = <String, dynamic>{};
    if (displayName != null) {
      data['displayName'] = displayName;
    }
    if (role != null) {
      data['role'] = role;
    }
    if (enabled != null) {
      data['enabled'] = enabled;
    }
    if (companyName != null) {
      data['companyName'] = companyName;
    }
    if (department != null) {
      data['department'] = department;
    }
    if (position != null) {
      data['position'] = position;
    }
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/admin/users/$userId',
      data: data,
      options: _options(accessToken),
    );
    return AdminUserDto.fromJson(response.data ?? const {});
  }

  Future<List<AdminSettingDto>> settings(String accessToken) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/admin/settings',
      options: _options(accessToken),
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map((item) => AdminSettingDto.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  Future<AdminSettingDto> upsertSetting({
    required String accessToken,
    required String key,
    required String value,
    String description = '',
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/admin/settings',
      data: {'key': key, 'value': value, 'description': description},
      options: _options(accessToken),
    );
    return AdminSettingDto.fromJson(response.data ?? const {});
  }

  Future<List<AdminAuditLogDto>> auditLogs(String accessToken) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/admin/audit-logs',
      options: _options(accessToken),
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map((item) => AdminAuditLogDto.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  Future<List<AdminSystemLogDto>> systemLogs(String accessToken) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/admin/system-logs',
      options: _options(accessToken),
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map((item) => AdminSystemLogDto.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  Options _options(String accessToken) {
    return Options(
      headers: {
        'Authorization': 'Bearer $accessToken',
        if (_activeCompany != null && _activeCompany.isNotEmpty)
          avaCompanyHeader: _activeCompany,
      },
    );
  }
}

class AdminOverviewDto {
  const AdminOverviewDto({
    required this.totalUsers,
    required this.enabledUsers,
    required this.disabledUsers,
    required this.chatRooms,
    required this.chatMessages,
    required this.unreadNotifications,
  });

  factory AdminOverviewDto.fromJson(Map<String, dynamic> json) {
    int number(String key) {
      final value = json[key];
      return value is num ? value.toInt() : 0;
    }

    return AdminOverviewDto(
      totalUsers: number('totalUsers'),
      enabledUsers: number('enabledUsers'),
      disabledUsers: number('disabledUsers'),
      chatRooms: number('chatRooms'),
      chatMessages: number('chatMessages'),
      unreadNotifications: number('unreadNotifications'),
    );
  }

  final int totalUsers;
  final int enabledUsers;
  final int disabledUsers;
  final int chatRooms;
  final int chatMessages;
  final int unreadNotifications;
}

class AdminUserDto {
  const AdminUserDto({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.enabled,
    required this.companyName,
    required this.department,
    required this.position,
    required this.status,
    required this.createdAt,
  });

  factory AdminUserDto.fromJson(Map<String, dynamic> json) {
    return AdminUserDto(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      role: json['role'] as String? ?? 'USER',
      enabled: json['enabled'] as bool? ?? false,
      companyName: json['companyName'] as String? ?? '',
      department: json['department'] as String? ?? '',
      position: json['position'] as String? ?? '',
      status: json['status'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }

  final String id;
  final String email;
  final String displayName;
  final String role;
  final bool enabled;
  final String companyName;
  final String department;
  final String position;
  final String status;
  final DateTime? createdAt;
}

class AdminSettingDto {
  const AdminSettingDto({
    required this.key,
    required this.value,
    required this.description,
    required this.updatedAt,
  });

  factory AdminSettingDto.fromJson(Map<String, dynamic> json) {
    return AdminSettingDto(
      key: json['key'] as String? ?? '',
      value: json['value'] as String? ?? '',
      description: json['description'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }

  final String key;
  final String value;
  final String description;
  final DateTime? updatedAt;
}

class AdminAuditLogDto {
  const AdminAuditLogDto({
    required this.action,
    required this.actorEmail,
    required this.resourceType,
    required this.resourceId,
    required this.metadata,
    required this.createdAt,
  });

  factory AdminAuditLogDto.fromJson(Map<String, dynamic> json) {
    return AdminAuditLogDto(
      action: json['action'] as String? ?? '',
      actorEmail: json['actorEmail'] as String? ?? '',
      resourceType: json['resourceType'] as String? ?? '',
      resourceId: json['resourceId'] as String? ?? '',
      metadata: json['metadata'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }

  final String action;
  final String actorEmail;
  final String resourceType;
  final String resourceId;
  final String metadata;
  final DateTime? createdAt;
}

class AdminSystemLogDto {
  const AdminSystemLogDto({
    required this.requestId,
    required this.accountEmail,
    required this.method,
    required this.path,
    required this.queryString,
    required this.status,
    required this.durationMs,
    required this.ipAddress,
    required this.errorMessage,
    required this.createdAt,
  });

  factory AdminSystemLogDto.fromJson(Map<String, dynamic> json) {
    return AdminSystemLogDto(
      requestId: json['requestId'] as String? ?? '',
      accountEmail: json['accountEmail'] as String? ?? '',
      method: json['method'] as String? ?? '',
      path: json['path'] as String? ?? '',
      queryString: json['queryString'] as String? ?? '',
      status: json['status'] is num ? (json['status'] as num).toInt() : 0,
      durationMs: json['durationMs'] is num
          ? (json['durationMs'] as num).toInt()
          : 0,
      ipAddress: json['ipAddress'] as String? ?? '',
      errorMessage: json['errorMessage'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }

  final String requestId;
  final String accountEmail;
  final String method;
  final String path;
  final String queryString;
  final int status;
  final int durationMs;
  final String ipAddress;
  final String errorMessage;
  final DateTime? createdAt;
}
