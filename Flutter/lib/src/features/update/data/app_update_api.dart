import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_config.dart';
import '../../../config/app_version.dart';
import '../../auth/data/auth_api.dart';

final appUpdateApiProvider = Provider<AppUpdateApi>((ref) {
  return AppUpdateApi(ref.watch(dioProvider), ref.watch(appConfigProvider));
});

class AppUpdateApi {
  const AppUpdateApi(this._dio, this._config);

  final Dio _dio;
  final AppConfig _config;

  Future<AppUpdateManifestDto> windowsLatest() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/app-updates/windows/latest',
      queryParameters: {'currentVersion': AppVersion.name},
    );
    return AppUpdateManifestDto.fromJson(response.data ?? const {});
  }

  String absoluteDownloadUrl(String downloadUrl) {
    if (downloadUrl.startsWith('http://') ||
        downloadUrl.startsWith('https://')) {
      return downloadUrl;
    }
    final base = _config.apiBaseUrl.endsWith('/')
        ? _config.apiBaseUrl.substring(0, _config.apiBaseUrl.length - 1)
        : _config.apiBaseUrl;
    final path = downloadUrl.startsWith('/') ? downloadUrl : '/$downloadUrl';
    return '$base$path';
  }
}

class AppUpdateManifestDto {
  const AppUpdateManifestDto({
    required this.platform,
    required this.currentVersion,
    required this.latestVersion,
    required this.updateAvailable,
    required this.required,
    required this.fileName,
    required this.downloadUrl,
    required this.sha256,
    required this.sizeBytes,
    required this.releaseNotes,
  });

  factory AppUpdateManifestDto.fromJson(Map<String, dynamic> json) {
    return AppUpdateManifestDto(
      platform: json['platform'] as String? ?? 'windows',
      currentVersion: json['currentVersion'] as String? ?? AppVersion.name,
      latestVersion: json['latestVersion'] as String? ?? AppVersion.name,
      updateAvailable: json['updateAvailable'] as bool? ?? false,
      required: json['required'] as bool? ?? false,
      fileName: json['fileName'] as String? ?? '',
      downloadUrl: json['downloadUrl'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      releaseNotes: json['releaseNotes'] as String? ?? '',
    );
  }

  final String platform;
  final String currentVersion;
  final String latestVersion;
  final bool updateAvailable;
  final bool required;
  final String fileName;
  final String downloadUrl;
  final String sha256;
  final int sizeBytes;
  final String releaseNotes;
}
