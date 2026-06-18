// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

Future<void> main(List<String> args) async {
  final count =
      _intArg(args, '--count') ??
      int.tryParse(Platform.environment['AVA_CHAT_STRESS_COUNT'] ?? '') ??
      1000;
  final baseUrl =
      _stringArg(args, '--base-url') ??
      Platform.environment['AVA_CHAT_STRESS_BASE_URL'] ??
      'http://127.0.0.1:8080';
  final websocketUrl =
      _stringArg(args, '--ws-url') ??
      Platform.environment['AVA_CHAT_STRESS_WS_URL'] ??
      'ws://127.0.0.1:8080/ws';
  final timeoutMs =
      _intArg(args, '--timeout-ms') ??
      int.tryParse(Platform.environment['AVA_CHAT_STRESS_TIMEOUT_MS'] ?? '') ??
      5000;

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
    ),
  );

  final first = await _login(
    dio,
    email: 'admin@ava.admin',
    password: 'Ava1234!',
    label: 'admin',
  );
  final second = await _login(
    dio,
    email: 'ava.demo.qa.01@abba-s.local',
    password: 'Ava1234!',
    label: 'qa01',
  );
  final roomCode = await _directRoom(dio, first, second);

  final firstProbe = _RealtimeProbe(
    label: first.label,
    websocketUrl: websocketUrl,
    accessToken: first.accessToken,
    roomCode: roomCode,
  );
  final secondProbe = _RealtimeProbe(
    label: second.label,
    websocketUrl: websocketUrl,
    accessToken: second.accessToken,
    roomCode: roomCode,
  );

  final samples = <String, _MessageSample>{};
  final failures = <String>[];
  final allProbes = [firstProbe, secondProbe];
  for (final probe in allProbes) {
    probe.events.listen((event) {
      final sample = samples[event.content];
      if (sample == null) {
        return;
      }
      sample.mark(event);
    });
  }

  await Future.wait([firstProbe.connect(), secondProbe.connect()]);
  print(
    'CHAT_STRESS_START count=$count room=$roomCode base=$baseUrl ws=$websocketUrl',
  );

  final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final timeout = Duration(milliseconds: timeoutMs);
  for (var i = 1; i <= count; i += 1) {
    final sender = i.isOdd ? first : second;
    final receiver = i.isOdd ? second : first;
    final content = 'AVA_CHAT_STRESS_${runId}_${i.toString().padLeft(4, '0')}';
    final sample = _MessageSample(
      index: i,
      content: content,
      senderLabel: sender.label,
      receiverLabel: receiver.label,
    );
    samples[content] = sample;

    final restWatch = Stopwatch()..start();
    await _refreshIfNeeded(dio, sender);
    final response = await _postChatMessage(
      dio,
      sender,
      roomCode: roomCode,
      content: content,
    );
    restWatch.stop();
    sample.restMs = restWatch.elapsedMicroseconds / 1000;
    final data = response.data ?? const {};
    sample.messageId = data['id'] as String? ?? '';
    sample.restUnreadCount = (data['unreadCount'] as num?)?.toInt() ?? -1;
    if ((data['content'] as String? ?? '') != content) {
      failures.add('message $i REST content mismatch');
    }
    if (sample.restUnreadCount <= 0) {
      failures.add(
        'message $i REST unreadCount=${sample.restUnreadCount} expected > 0',
      );
    }

    final delivered = await _waitUntil(
      () => sample.hasRealtimeDelivery,
      timeout: timeout,
    );
    if (!delivered) {
      failures.add('message $i realtime delivery timeout: ${sample.missing}');
    }
    if ((i % 100) == 0 || i == count) {
      final stats = _LatencyStats(samples.values.take(i).toList());
      print(
        'CHAT_STRESS_PROGRESS sent=$i missing=${failures.length} '
        'recvTopicP95=${stats.receiverTopicP95.toStringAsFixed(1)}ms '
        'inboxP95=${stats.receiverInboxP95.toStringAsFixed(1)}ms '
        'pushP95=${stats.receiverPushP95.toStringAsFixed(1)}ms',
      );
    }
  }

  await Future<void>.delayed(const Duration(milliseconds: 300));
  final stats = _LatencyStats(samples.values.toList());
  await Future.wait([firstProbe.dispose(), secondProbe.dispose()]);

  print(
    'CHAT_STRESS_RESULT sent=$count failures=${failures.length} '
    'restP50=${stats.restP50.toStringAsFixed(1)}ms '
    'restP95=${stats.restP95.toStringAsFixed(1)}ms '
    'receiverTopicP50=${stats.receiverTopicP50.toStringAsFixed(1)}ms '
    'receiverTopicP95=${stats.receiverTopicP95.toStringAsFixed(1)}ms '
    'receiverTopicMax=${stats.receiverTopicMax.toStringAsFixed(1)}ms '
    'receiverInboxP50=${stats.receiverInboxP50.toStringAsFixed(1)}ms '
    'receiverInboxP95=${stats.receiverInboxP95.toStringAsFixed(1)}ms '
    'receiverInboxMax=${stats.receiverInboxMax.toStringAsFixed(1)}ms '
    'receiverPushP50=${stats.receiverPushP50.toStringAsFixed(1)}ms '
    'receiverPushP95=${stats.receiverPushP95.toStringAsFixed(1)}ms '
    'receiverPushMax=${stats.receiverPushMax.toStringAsFixed(1)}ms',
  );

  if (failures.isNotEmpty) {
    for (final failure in failures.take(20)) {
      stderr.writeln('CHAT_STRESS_FAILURE $failure');
    }
    if (failures.length > 20) {
      stderr.writeln('CHAT_STRESS_FAILURE ${failures.length - 20} more');
    }
    exitCode = 1;
  }
}

Future<_Account> _login(
  Dio dio, {
  required String email,
  required String password,
  required String label,
}) async {
  final response = await dio.post<Map<String, dynamic>>(
    '/api/auth/login',
    data: {
      'email': email,
      'password': password,
      'rememberMe': true,
      'autoLogin': false,
      'forceLogin': true,
    },
  );
  final payload = response.data ?? const {};
  final user = (payload['user'] as Map?)?.cast<String, dynamic>() ?? const {};
  final expiresInSeconds =
      (payload['expiresInSeconds'] as num?)?.toInt() ?? 1800;
  return _Account(
    label: label,
    id: user['id'] as String? ?? '',
    email: email,
    name: user['displayName'] as String? ?? label,
    accessToken: payload['accessToken'] as String? ?? '',
    refreshToken: payload['refreshToken'] as String? ?? '',
    accessTokenExpiresAt: DateTime.now().add(
      Duration(seconds: expiresInSeconds),
    ),
  );
}

Future<Response<Map<String, dynamic>>> _postChatMessage(
  Dio dio,
  _Account sender, {
  required String roomCode,
  required String content,
}) async {
  try {
    return await dio.post<Map<String, dynamic>>(
      '/api/chat/rooms/$roomCode/messages',
      data: {
        'content': content,
        'silent': false,
        'spoiler': false,
        'mentions': const [],
      },
      options: Options(headers: _authHeaders(sender.accessToken)),
    );
  } on DioException catch (error) {
    final statusCode = error.response?.statusCode;
    if (statusCode != 401 && statusCode != 403) {
      rethrow;
    }
    await _refreshAccount(dio, sender);
    return dio.post<Map<String, dynamic>>(
      '/api/chat/rooms/$roomCode/messages',
      data: {
        'content': content,
        'silent': false,
        'spoiler': false,
        'mentions': const [],
      },
      options: Options(headers: _authHeaders(sender.accessToken)),
    );
  }
}

Future<void> _refreshIfNeeded(Dio dio, _Account account) async {
  if (DateTime.now().isBefore(
    account.accessTokenExpiresAt.subtract(const Duration(minutes: 2)),
  )) {
    return;
  }
  await _refreshAccount(dio, account);
}

Future<void> _refreshAccount(Dio dio, _Account account) async {
  if (account.refreshToken.isEmpty) {
    return;
  }
  final response = await dio.post<Map<String, dynamic>>(
    '/api/auth/refresh',
    data: {'refreshToken': account.refreshToken},
  );
  final payload = response.data ?? const {};
  final accessToken = payload['accessToken'] as String? ?? '';
  final refreshToken = payload['refreshToken'] as String? ?? '';
  final expiresInSeconds =
      (payload['expiresInSeconds'] as num?)?.toInt() ?? 1800;
  if (accessToken.isNotEmpty) {
    account.accessToken = accessToken;
    account.accessTokenExpiresAt = DateTime.now().add(
      Duration(seconds: expiresInSeconds),
    );
  }
  if (refreshToken.isNotEmpty) {
    account.refreshToken = refreshToken;
  }
}

Future<String> _directRoom(Dio dio, _Account owner, _Account target) async {
  final response = await dio.post<Map<String, dynamic>>(
    '/api/chat/direct-rooms',
    data: {
      'targetUserId': target.id,
      'targetEmail': target.email,
      'targetName': target.name,
    },
    options: Options(headers: _authHeaders(owner.accessToken)),
  );
  final code = response.data?['code'] as String? ?? '';
  if (code.isEmpty) {
    throw StateError('Direct room creation returned an empty code.');
  }
  return code;
}

Map<String, String> _authHeaders(String accessToken) {
  return {'Authorization': 'Bearer $accessToken'};
}

Future<bool> _waitUntil(
  bool Function() predicate, {
  required Duration timeout,
}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < timeout) {
    if (predicate()) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return predicate();
}

String? _stringArg(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) {
    return null;
  }
  return args[index + 1];
}

int? _intArg(List<String> args, String name) {
  final value = _stringArg(args, name);
  return value == null ? null : int.tryParse(value);
}

class _Account {
  _Account({
    required this.label,
    required this.id,
    required this.email,
    required this.name,
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
  });

  final String label;
  final String id;
  final String email;
  final String name;
  String accessToken;
  String refreshToken;
  DateTime accessTokenExpiresAt;
}

class _RealtimeProbe {
  _RealtimeProbe({
    required this.label,
    required this.websocketUrl,
    required this.accessToken,
    required this.roomCode,
  });

  final String label;
  final String websocketUrl;
  final String accessToken;
  final String roomCode;

  final _events = StreamController<_RealtimeEvent>.broadcast();
  final _connected = Completer<void>();
  final _subscriptions = <StompUnsubscribe>[];
  StompClient? _client;

  Stream<_RealtimeEvent> get events => _events.stream;

  Future<void> connect() async {
    final headers = _authHeaders(accessToken);
    _client = StompClient(
      config: StompConfig(
        url: websocketUrl,
        stompConnectHeaders: headers,
        webSocketConnectHeaders: headers,
        reconnectDelay: const Duration(milliseconds: 700),
        connectionTimeout: const Duration(seconds: 4),
        onConnect: (_) {
          _subscribe('/topic/rooms/$roomCode', 'room-topic');
          _subscribe('/user/queue/chat-events', 'chat-event');
          _subscribe('/user/queue/mobile-push', 'mobile-push');
          if (!_connected.isCompleted) {
            _connected.complete();
          }
        },
        onWebSocketError: (error) {
          if (!_connected.isCompleted) {
            _connected.completeError(error);
          }
          _events.addError(error);
        },
        onStompError: (frame) {
          final error = frame.body ?? 'STOMP error';
          if (!_connected.isCompleted) {
            _connected.completeError(error);
          }
          _events.addError(error);
        },
      ),
    )..activate();
    await _connected.future.timeout(const Duration(seconds: 12));
  }

  void _subscribe(String destination, String source) {
    final unsubscribe = _client?.subscribe(
      destination: destination,
      callback: (frame) {
        final body = frame.body;
        if (body == null || body.isEmpty) {
          return;
        }
        final decoded = jsonDecode(body);
        if (decoded is! Map) {
          return;
        }
        final json = decoded.cast<String, dynamic>();
        final content = _contentFromFrame(source, json);
        if (content == null || content.isEmpty) {
          return;
        }
        _events.add(
          _RealtimeEvent(
            probeLabel: label,
            source: source,
            content: content,
            unreadCount: _unreadCountFromFrame(source, json),
          ),
        );
      },
    );
    if (unsubscribe != null) {
      _subscriptions.add(unsubscribe);
    }
  }

  Future<void> dispose() async {
    for (final unsubscribe in _subscriptions) {
      unsubscribe();
    }
    _subscriptions.clear();
    _client?.deactivate();
    _client = null;
    await _events.close();
  }
}

String? _contentFromFrame(String source, Map<String, dynamic> json) {
  if (source == 'room-topic') {
    return json['content'] as String?;
  }
  if (source == 'chat-event') {
    final message = (json['message'] as Map?)?.cast<String, dynamic>();
    return message?['content'] as String?;
  }
  if (source == 'mobile-push') {
    final data = (json['data'] as Map?)?.cast<String, dynamic>();
    return (data?['body'] as String?) ?? json['body'] as String?;
  }
  return null;
}

int? _unreadCountFromFrame(String source, Map<String, dynamic> json) {
  if (source == 'room-topic') {
    return (json['unreadCount'] as num?)?.toInt();
  }
  if (source == 'chat-event') {
    final message = (json['message'] as Map?)?.cast<String, dynamic>();
    return (message?['unreadCount'] as num?)?.toInt();
  }
  return null;
}

class _RealtimeEvent {
  const _RealtimeEvent({
    required this.probeLabel,
    required this.source,
    required this.content,
    required this.unreadCount,
  });

  final String probeLabel;
  final String source;
  final String content;
  final int? unreadCount;
}

class _MessageSample {
  _MessageSample({
    required this.index,
    required this.content,
    required this.senderLabel,
    required this.receiverLabel,
  }) : sentAt = DateTime.now();

  final int index;
  final String content;
  final String senderLabel;
  final String receiverLabel;
  final DateTime sentAt;

  String messageId = '';
  double? restMs;
  int restUnreadCount = -1;
  DateTime? senderTopicAt;
  DateTime? senderInboxAt;
  DateTime? receiverTopicAt;
  DateTime? receiverInboxAt;
  DateTime? receiverPushAt;
  int? senderTopicUnreadCount;
  int? receiverTopicUnreadCount;

  bool get hasRealtimeDelivery {
    return senderTopicAt != null &&
        receiverTopicAt != null &&
        receiverInboxAt != null &&
        receiverPushAt != null &&
        (senderTopicUnreadCount ?? 0) > 0 &&
        (receiverTopicUnreadCount ?? 0) > 0;
  }

  String get missing {
    final parts = <String>[];
    if (senderTopicAt == null) {
      parts.add('sender topic');
    }
    if (receiverTopicAt == null) {
      parts.add('receiver topic');
    }
    if (receiverInboxAt == null) {
      parts.add('receiver chat-event');
    }
    if (receiverPushAt == null) {
      parts.add('receiver mobile-push');
    }
    if ((senderTopicUnreadCount ?? 0) <= 0) {
      parts.add('sender unread count');
    }
    if ((receiverTopicUnreadCount ?? 0) <= 0) {
      parts.add('receiver unread count');
    }
    return parts.join(', ');
  }

  void mark(_RealtimeEvent event) {
    final now = DateTime.now();
    final sender = event.probeLabel == senderLabel;
    final receiver = event.probeLabel == receiverLabel;
    if (event.source == 'room-topic' && sender) {
      senderTopicAt ??= now;
      senderTopicUnreadCount ??= event.unreadCount;
    } else if (event.source == 'room-topic' && receiver) {
      receiverTopicAt ??= now;
      receiverTopicUnreadCount ??= event.unreadCount;
    } else if (event.source == 'chat-event' && sender) {
      senderInboxAt ??= now;
    } else if (event.source == 'chat-event' && receiver) {
      receiverInboxAt ??= now;
    } else if (event.source == 'mobile-push' && receiver) {
      receiverPushAt ??= now;
    }
  }

  double? latency(DateTime? time) {
    if (time == null) {
      return null;
    }
    return time.difference(sentAt).inMicroseconds / 1000;
  }
}

class _LatencyStats {
  _LatencyStats(List<_MessageSample> samples)
    : restP50 = _percentile(samples.map((sample) => sample.restMs), 0.50),
      restP95 = _percentile(samples.map((sample) => sample.restMs), 0.95),
      receiverTopicP50 = _percentile(
        samples.map((sample) => sample.latency(sample.receiverTopicAt)),
        0.50,
      ),
      receiverTopicP95 = _percentile(
        samples.map((sample) => sample.latency(sample.receiverTopicAt)),
        0.95,
      ),
      receiverTopicMax = _max(
        samples.map((sample) => sample.latency(sample.receiverTopicAt)),
      ),
      receiverInboxP50 = _percentile(
        samples.map((sample) => sample.latency(sample.receiverInboxAt)),
        0.50,
      ),
      receiverInboxP95 = _percentile(
        samples.map((sample) => sample.latency(sample.receiverInboxAt)),
        0.95,
      ),
      receiverInboxMax = _max(
        samples.map((sample) => sample.latency(sample.receiverInboxAt)),
      ),
      receiverPushP50 = _percentile(
        samples.map((sample) => sample.latency(sample.receiverPushAt)),
        0.50,
      ),
      receiverPushP95 = _percentile(
        samples.map((sample) => sample.latency(sample.receiverPushAt)),
        0.95,
      ),
      receiverPushMax = _max(
        samples.map((sample) => sample.latency(sample.receiverPushAt)),
      );

  final double restP50;
  final double restP95;
  final double receiverTopicP50;
  final double receiverTopicP95;
  final double receiverTopicMax;
  final double receiverInboxP50;
  final double receiverInboxP95;
  final double receiverInboxMax;
  final double receiverPushP50;
  final double receiverPushP95;
  final double receiverPushMax;
}

double _percentile(Iterable<double?> values, double percentile) {
  final sorted = values.whereType<double>().toList()..sort();
  if (sorted.isEmpty) {
    return double.nan;
  }
  final rawIndex = (sorted.length - 1) * percentile;
  final low = rawIndex.floor();
  final high = rawIndex.ceil();
  if (low == high) {
    return sorted[low];
  }
  final weight = rawIndex - low;
  return sorted[low] * (1 - weight) + sorted[high] * weight;
}

double _max(Iterable<double?> values) {
  final present = values.whereType<double>().toList();
  if (present.isEmpty) {
    return double.nan;
  }
  return present.reduce(math.max);
}
