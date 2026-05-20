import 'dart:async';
import 'dart:convert';

import 'package:stomp_dart_client/stomp_dart_client.dart';

class AuthRealtimeClient {
  AuthRealtimeClient({
    required this.websocketUrl,
    required this.accessToken,
  });

  final String websocketUrl;
  final String accessToken;

  final _events = StreamController<AuthRealtimeEventDto>.broadcast();
  StompClient? _client;
  StompUnsubscribe? _unsubscribe;

  Stream<AuthRealtimeEventDto> get events => _events.stream;

  void connect() {
    final headers = {'Authorization': 'Bearer $accessToken'};
    _client = StompClient(
      config: StompConfig(
        url: websocketUrl,
        stompConnectHeaders: headers,
        webSocketConnectHeaders: headers,
        reconnectDelay: const Duration(seconds: 3),
        connectionTimeout: const Duration(seconds: 8),
        onConnect: (_) {
          _unsubscribe = _client?.subscribe(
            destination: '/user/queue/auth-events',
            callback: (frame) {
              final body = frame.body;
              if (body == null || body.isEmpty) {
                return;
              }
              final json = jsonDecode(body);
              if (json is Map) {
                _events.add(
                  AuthRealtimeEventDto.fromJson(
                    json.cast<String, dynamic>(),
                  ),
                );
              }
            },
          );
        },
        onWebSocketError: (error) {
          _events.addError(error);
        },
        onStompError: (frame) {
          _events.addError(frame.body ?? 'STOMP error');
        },
      ),
    )..activate();
  }

  void dispose() {
    _unsubscribe?.call();
    _unsubscribe = null;
    _client?.deactivate();
    _client = null;
    _events.close();
  }
}

class AuthRealtimeEventDto {
  const AuthRealtimeEventDto({
    required this.type,
    required this.reason,
    required this.message,
    required this.occurredAt,
  });

  factory AuthRealtimeEventDto.fromJson(Map<String, dynamic> json) {
    return AuthRealtimeEventDto(
      type: json['type'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      message: json['message'] as String? ?? '',
      occurredAt: DateTime.tryParse(json['occurredAt'] as String? ?? ''),
    );
  }

  final String type;
  final String reason;
  final String message;
  final DateTime? occurredAt;
}
