import 'dart:io' as io;

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

  Future<AppUpdateManifestDto?> latestForCurrentPlatform() async {
    final platform = currentUpdatePlatform;
    if (platform == null) {
      return null;
    }
    return latest(platform);
  }

  Future<AppUpdateManifestDto> latest(String platform) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/app-updates/$platform/latest',
      queryParameters: {'currentVersion': AppVersion.name},
    );
    return AppUpdateManifestDto.fromJson(response.data ?? const {});
  }

  Future<AppUpdateManifestDto> windowsLatest() => latest('windows');

  Future<AppUpdateReleaseDto?> currentRelease() async {
    final platform = currentUpdatePlatform;
    if (platform == null) {
      return null;
    }
    return release(platform, AppVersion.name);
  }

  Future<AppUpdateReleaseDto> release(String platform, String version) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/app-updates/$platform/releases/$version',
    );
    return AppUpdateReleaseDto.fromJson(response.data ?? const {});
  }

  String? get currentUpdatePlatform {
    if (io.Platform.isWindows) {
      return 'windows';
    }
    if (io.Platform.isMacOS) {
      return 'macos';
    }
    if (io.Platform.isAndroid) {
      return 'android';
    }
    return null;
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

class AppUpdateReleaseDto {
  const AppUpdateReleaseDto({
    required this.platform,
    required this.version,
    required this.fileName,
    required this.required,
    required this.releaseNotes,
    required this.sha256,
    required this.sizeBytes,
    required this.packageAvailable,
  });

  factory AppUpdateReleaseDto.fromJson(Map<String, dynamic> json) {
    return AppUpdateReleaseDto(
      platform: json['platform'] as String? ?? 'windows',
      version: json['version'] as String? ?? AppVersion.name,
      fileName: json['fileName'] as String? ?? '',
      required: json['required'] as bool? ?? false,
      releaseNotes: json['releaseNotes'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      packageAvailable: json['packageAvailable'] as bool? ?? false,
    );
  }

  final String platform;
  final String version;
  final String fileName;
  final bool required;
  final String releaseNotes;
  final String sha256;
  final int sizeBytes;
  final bool packageAvailable;
}
