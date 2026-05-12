import 'dart:async';
import 'dart:convert';

import 'package:stomp_dart_client/stomp_dart_client.dart';

import 'chat_api.dart';

class ChatRealtimeClient {
  ChatRealtimeClient({
    required this.websocketUrl,
    required this.accessToken,
    required this.roomCode,
  });

  final String websocketUrl;
  final String accessToken;
  final String roomCode;

  final _messages = StreamController<ChatMessageDto>.broadcast();
  final _readStates = StreamController<ChatReadStateDto>.broadcast();
  final _typingEvents = StreamController<ChatTypingEventDto>.broadcast();
  StompClient? _client;
  final List<StompUnsubscribe> _unsubscribes = [];

  Stream<ChatMessageDto> get messages => _messages.stream;
  Stream<ChatReadStateDto> get readStates => _readStates.stream;
  Stream<ChatTypingEventDto> get typingEvents => _typingEvents.stream;

  bool get isConnected => _client?.connected ?? false;

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
          _subscribe(
            '/topic/rooms/$roomCode',
            (json) => _messages.add(ChatMessageDto.fromJson(json)),
          );
          _subscribe(
            '/topic/rooms/$roomCode/read-state',
            (json) => _readStates.add(ChatReadStateDto.fromJson(json)),
          );
          _subscribe(
            '/topic/rooms/$roomCode/typing',
            (json) => _typingEvents.add(ChatTypingEventDto.fromJson(json)),
          );
        },
        onWebSocketError: (error) {
          _messages.addError(error);
        },
        onStompError: (frame) {
          _messages.addError(frame.body ?? 'STOMP error');
        },
      ),
    )..activate();
  }

  void _subscribe(
    String destination,
    void Function(Map<String, dynamic> json) onData,
  ) {
    final unsubscribe = _client?.subscribe(
      destination: destination,
      callback: (frame) {
        final body = frame.body;
        if (body == null || body.isEmpty) {
          return;
        }
        final json = jsonDecode(body);
        if (json is Map) {
          onData(json.cast<String, dynamic>());
        }
      },
    );
    if (unsubscribe != null) {
      _unsubscribes.add(unsubscribe);
    }
  }

  bool send(String content, {bool silent = false, bool spoiler = false}) {
    final client = _client;
    if (client == null || !client.connected) {
      return false;
    }

    client.send(
      destination: '/app/rooms/$roomCode/send',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: jsonEncode({
        'content': content,
        'silent': silent,
        'spoiler': spoiler,
      }),
    );
    return true;
  }

  bool sendTyping(bool typing) {
    final client = _client;
    if (client == null || !client.connected) {
      return false;
    }

    client.send(
      destination: '/app/rooms/$roomCode/typing',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: jsonEncode({'typing': typing}),
    );
    return true;
  }

  void dispose() {
    for (final unsubscribe in _unsubscribes) {
      unsubscribe();
    }
    _unsubscribes.clear();
    _client?.deactivate();
    _client = null;
    _messages.close();
    _readStates.close();
    _typingEvents.close();
  }
}

class ChatInboxRealtimeClient {
  ChatInboxRealtimeClient({
    required this.websocketUrl,
    required this.accessToken,
  });

  final String websocketUrl;
  final String accessToken;

  final _events = StreamController<ChatRealtimeEventDto>.broadcast();
  StompClient? _client;
  StompUnsubscribe? _unsubscribe;

  Stream<ChatRealtimeEventDto> get events => _events.stream;

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
            destination: '/user/queue/chat-events',
            callback: (frame) {
              final body = frame.body;
              if (body == null || body.isEmpty) {
                return;
              }
              final json = jsonDecode(body);
              if (json is Map) {
                _events.add(
                  ChatRealtimeEventDto.fromJson(json.cast<String, dynamic>()),
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

class ChatRealtimeEventDto {
  const ChatRealtimeEventDto({
    required this.type,
    required this.room,
    required this.message,
  });

  factory ChatRealtimeEventDto.fromJson(Map<String, dynamic> json) {
    return ChatRealtimeEventDto(
      type: json['type'] as String? ?? '',
      room: json['room'] is Map
          ? ChatRoomDto.fromJson((json['room'] as Map).cast<String, dynamic>())
          : const ChatRoomDto.empty(),
      message: json['message'] is Map
          ? ChatMessageDto.fromJson(
              (json['message'] as Map).cast<String, dynamic>(),
            )
          : null,
    );
  }

  final String type;
  final ChatRoomDto room;
  final ChatMessageDto? message;
}

class ChatTypingEventDto {
  const ChatTypingEventDto({
    required this.roomCode,
    required this.userId,
    required this.displayName,
    required this.typing,
    required this.sentAt,
  });

  factory ChatTypingEventDto.fromJson(Map<String, dynamic> json) {
    return ChatTypingEventDto(
      roomCode: json['roomCode'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      typing: json['typing'] as bool? ?? false,
      sentAt: DateTime.tryParse(json['sentAt'] as String? ?? ''),
    );
  }

  final String roomCode;
  final String userId;
  final String displayName;
  final bool typing;
  final DateTime? sentAt;
}
