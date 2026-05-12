import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppConfig {
  const AppConfig({required this.apiBaseUrl, required this.websocketUrl});

  static const fromEnvironment = AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'AVA_API_BASE_URL',
      defaultValue: 'http://localhost:8080',
    ),
    websocketUrl: String.fromEnvironment(
      'AVA_WS_URL',
      defaultValue: 'ws://localhost:8080/ws',
    ),
  );

  final String apiBaseUrl;
  final String websocketUrl;
}

final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment;
});
