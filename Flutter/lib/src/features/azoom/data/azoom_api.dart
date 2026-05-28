import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../../auth/application/company_scope.dart';
import '../../auth/data/auth_api.dart';

final azoomApiProvider = Provider<AzoomApi>((ref) {
  return AzoomApi(ref.watch(dioProvider), ref.watch(activeCompanyProvider));
});

class AzoomApi {
  const AzoomApi(this._dio, this._activeCompany);

  final Dio _dio;
  final String? _activeCompany;

  Future<AzoomChannelsDto> channels(String accessToken) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/azoom/channels',
      options: _authOptions(accessToken),
    );
    return AzoomChannelsDto.fromJson(response.data ?? const {});
  }

  Future<AzoomVoiceJoinDto> joinVoice({
    required String accessToken,
    required String channelId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/azoom/voice-channels/$channelId/join',
      options: _authOptions(accessToken),
    );
    return AzoomVoiceJoinDto.fromJson(response.data ?? const {});
  }

  Future<AzoomVoiceChannelDto> leaveVoice({
    required String accessToken,
    required String channelId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/azoom/voice-channels/$channelId/leave',
      options: _authOptions(accessToken),
    );
    return AzoomVoiceChannelDto.fromJson(response.data ?? const {});
  }

  Future<AzoomVoiceChannelDto> updateVoiceStatus({
    required String accessToken,
    required String channelId,
    bool? muted,
    bool? deafened,
    bool? cameraEnabled,
    bool? screenSharing,
  }) async {
    final data = <String, dynamic>{};
    void addFlag(String key, bool? value) {
      if (value != null) {
        data[key] = value;
      }
    }

    addFlag('muted', muted);
    addFlag('deafened', deafened);
    addFlag('cameraEnabled', cameraEnabled);
    addFlag('screenSharing', screenSharing);

    final response = await _dio.put<Map<String, dynamic>>(
      '/api/azoom/voice-channels/$channelId/status',
      data: data,
      options: _authOptions(accessToken),
    );
    return AzoomVoiceChannelDto.fromJson(response.data ?? const {});
  }

  Future<AzoomLiveKitTokenDto> liveKitToken({
    required String accessToken,
    required String channelId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/azoom/voice-channels/$channelId/livekit-token',
      options: _authOptions(accessToken),
    );
    return AzoomLiveKitTokenDto.fromJson(response.data ?? const {});
  }

  Future<List<AzoomMeetingTranscriptSummaryDto>> meetingTranscripts({
    required String accessToken,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/azoom/meeting-transcripts',
      options: _authOptions(accessToken),
    );
    return [
      for (final item in response.data ?? const [])
        AzoomMeetingTranscriptSummaryDto.fromJson(
          (item as Map).cast<String, dynamic>(),
        ),
    ];
  }

  Future<AzoomWorkspaceDto> workspace({required String accessToken}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/azoom/workspace',
      options: _authOptions(accessToken),
    );
    return AzoomWorkspaceDto.fromJson(response.data ?? const {});
  }

  Future<List<AzoomInviteCandidateDto>> inviteCandidates({
    required String accessToken,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/azoom/invite-candidates',
      options: _authOptions(accessToken),
    );
    return [
      for (final item in response.data ?? const [])
        AzoomInviteCandidateDto.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  Future<List<AzoomCompanyUserDto>> companyUsers({
    required String accessToken,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/users',
      options: _authOptions(accessToken),
    );
    return [
      for (final item in response.data ?? const [])
        AzoomCompanyUserDto.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  Future<AzoomWorkspaceDto> inviteMembers({
    required String accessToken,
    required List<String> accountIds,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/azoom/invite-members',
      data: {'accountIds': accountIds},
      options: _authOptions(accessToken),
    );
    return AzoomWorkspaceDto.fromJson(response.data ?? const {});
  }

  Future<AzoomVoiceChannelDto> updateChannelAccess({
    required String accessToken,
    required String channelId,
    required String accessMode,
    required List<String> allowedDepartments,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/azoom/voice-channels/$channelId/access',
      data: {
        'accessMode': accessMode,
        'allowedDepartments': allowedDepartments,
      },
      options: _authOptions(accessToken),
    );
    return AzoomVoiceChannelDto.fromJson(response.data ?? const {});
  }

  Future<AzoomVoiceEffectDto> triggerFirework({
    required String accessToken,
    required String channelId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/azoom/voice-channels/$channelId/effects/firework',
      options: _authOptions(accessToken),
    );
    return AzoomVoiceEffectDto.fromJson(response.data ?? const {});
  }

  Future<AzoomMeetingTranscriptDto> meetingTranscript({
    required String accessToken,
    required String transcriptId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/azoom/meeting-transcripts/$transcriptId',
      options: _authOptions(accessToken),
    );
    return AzoomMeetingTranscriptDto.fromJson(response.data ?? const {});
  }

  Future<AzoomNotivaSessionDto> startNotiva({
    required String accessToken,
    required String channelId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/azoom/voice-channels/$channelId/notiva/start',
      options: _authOptions(accessToken),
    );
    return AzoomNotivaSessionDto.fromJson(response.data ?? const {});
  }

  Future<AzoomMeetingTranscriptDto> finishNotiva({
    required String accessToken,
    required String channelId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/azoom/voice-channels/$channelId/notiva/finish',
      options: _authOptions(accessToken),
    );
    return AzoomMeetingTranscriptDto.fromJson(response.data ?? const {});
  }

  Future<AzoomNotivaAudioDto> uploadNotivaRealtimeAudio({
    required String accessToken,
    required String channelId,
    required String filePath,
    String? speakerUserId,
    String? speakerName,
    String? speakerEmail,
  }) {
    return _uploadNotivaAudio(
      accessToken: accessToken,
      channelId: channelId,
      filePath: filePath,
      endpoint: 'realtime-audio',
      speakerUserId: speakerUserId,
      speakerName: speakerName,
      speakerEmail: speakerEmail,
    );
  }

  Future<AzoomNotivaAudioDto> uploadNotivaBatchAudio({
    required String accessToken,
    required String channelId,
    required String filePath,
    String? speakerUserId,
    String? speakerName,
    String? speakerEmail,
  }) {
    return _uploadNotivaAudio(
      accessToken: accessToken,
      channelId: channelId,
      filePath: filePath,
      endpoint: 'batch-audio',
      speakerUserId: speakerUserId,
      speakerName: speakerName,
      speakerEmail: speakerEmail,
    );
  }

  Future<AzoomNotivaAudioDto> _uploadNotivaAudio({
    required String accessToken,
    required String channelId,
    required String filePath,
    required String endpoint,
    String? speakerUserId,
    String? speakerName,
    String? speakerEmail,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
      if (speakerUserId != null && speakerUserId.isNotEmpty)
        'speakerUserId': speakerUserId,
      if (speakerName != null && speakerName.isNotEmpty)
        'speakerName': speakerName,
      if (speakerEmail != null && speakerEmail.isNotEmpty)
        'speakerEmail': speakerEmail,
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/azoom/voice-channels/$channelId/notiva/$endpoint',
      data: formData,
      options: _authOptions(
        accessToken,
        sendTimeout: const Duration(minutes: 2),
        receiveTimeout: endpoint == 'batch-audio'
            ? const Duration(minutes: 20)
            : const Duration(minutes: 10),
      ),
    );
    return AzoomNotivaAudioDto.fromJson(response.data ?? const {});
  }

  Options _authOptions(
    String accessToken, {
    Duration? sendTimeout,
    Duration? receiveTimeout,
  }) {
    return Options(
      headers: {
        'Authorization': 'Bearer $accessToken',
        if (_activeCompany != null && _activeCompany.isNotEmpty)
          avaCompanyHeader: _activeCompany,
      },
      sendTimeout: sendTimeout,
      receiveTimeout: receiveTimeout,
    );
  }
}

class AzoomVoiceRealtimeClient {
  AzoomVoiceRealtimeClient({
    required this.websocketUrl,
    required this.accessToken,
    required this.roomNames,
  });

  final String websocketUrl;
  final String accessToken;
  final List<String> roomNames;

  final _states = StreamController<AzoomVoiceChannelDto>.broadcast();
  StompClient? _client;
  final List<StompUnsubscribe> _unsubscribes = [];

  Stream<AzoomVoiceChannelDto> get states => _states.stream;

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
          _unsubscribes
            ..forEach((unsubscribe) => unsubscribe())
            ..clear();
          for (final roomName in roomNames.toSet()) {
            final topic = roomName.trim();
            if (topic.isEmpty) {
              continue;
            }
            final unsubscribe = _client?.subscribe(
              destination: '/topic/azoom/voice/$topic',
              callback: (frame) {
                final body = frame.body;
                if (body == null || body.isEmpty) {
                  return;
                }
                final json = jsonDecode(body);
                if (json is Map) {
                  _states.add(
                    AzoomVoiceChannelDto.fromJson(json.cast<String, dynamic>()),
                  );
                }
              },
            );
            if (unsubscribe != null) {
              _unsubscribes.add(unsubscribe);
            }
          }
        },
        onWebSocketError: (error) {
          _states.addError(error);
        },
        onStompError: (frame) {
          _states.addError(frame.body ?? 'STOMP error');
        },
      ),
    )..activate();
  }

  void dispose() {
    for (final unsubscribe in _unsubscribes) {
      unsubscribe();
    }
    _unsubscribes.clear();
    _client?.deactivate();
    _client = null;
    _states.close();
  }
}

class AzoomNotivaRealtimeClient {
  AzoomNotivaRealtimeClient({
    required this.websocketUrl,
    required this.accessToken,
    required this.roomName,
  });

  final String websocketUrl;
  final String accessToken;
  final String roomName;

  final _events = StreamController<AzoomNotivaEventDto>.broadcast();
  StompClient? _client;
  StompUnsubscribe? _unsubscribe;

  Stream<AzoomNotivaEventDto> get events => _events.stream;

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
            destination: '/topic/azoom/notiva/$roomName',
            callback: (frame) {
              final body = frame.body;
              if (body == null || body.isEmpty) {
                return;
              }
              final json = jsonDecode(body);
              if (json is Map) {
                _events.add(
                  AzoomNotivaEventDto.fromJson(json.cast<String, dynamic>()),
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

class AzoomVoiceEffectRealtimeClient {
  AzoomVoiceEffectRealtimeClient({
    required this.websocketUrl,
    required this.accessToken,
    required this.roomNames,
  });

  final String websocketUrl;
  final String accessToken;
  final List<String> roomNames;

  final _events = StreamController<AzoomVoiceEffectDto>.broadcast();
  StompClient? _client;
  final List<StompUnsubscribe> _unsubscribes = [];

  Stream<AzoomVoiceEffectDto> get events => _events.stream;

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
          _unsubscribes
            ..forEach((unsubscribe) => unsubscribe())
            ..clear();
          for (final roomName in roomNames.toSet()) {
            final topic = roomName.trim();
            if (topic.isEmpty) {
              continue;
            }
            final unsubscribe = _client?.subscribe(
              destination: '/topic/azoom/voice-effects/$topic',
              callback: (frame) {
                final body = frame.body;
                if (body == null || body.isEmpty) {
                  return;
                }
                final json = jsonDecode(body);
                if (json is Map) {
                  _events.add(
                    AzoomVoiceEffectDto.fromJson(json.cast<String, dynamic>()),
                  );
                }
              },
            );
            if (unsubscribe != null) {
              _unsubscribes.add(unsubscribe);
            }
          }
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
    for (final unsubscribe in _unsubscribes) {
      unsubscribe();
    }
    _unsubscribes.clear();
    _client?.deactivate();
    _client = null;
    _events.close();
  }
}

class AzoomChannelsDto {
  const AzoomChannelsDto({
    required this.companyName,
    required this.liveKitEnabled,
    required this.liveKitUrl,
    required this.voiceChannels,
  });

  factory AzoomChannelsDto.fromJson(Map<String, dynamic> json) {
    return AzoomChannelsDto(
      companyName: json['companyName'] as String? ?? 'ABBA-S',
      liveKitEnabled: json['liveKitEnabled'] as bool? ?? false,
      liveKitUrl: json['liveKitUrl'] as String? ?? '',
      voiceChannels: [
        for (final item in json['voiceChannels'] as List<dynamic>? ?? const [])
          AzoomVoiceChannelDto.fromJson((item as Map).cast<String, dynamic>()),
      ],
    );
  }

  final String companyName;
  final bool liveKitEnabled;
  final String liveKitUrl;
  final List<AzoomVoiceChannelDto> voiceChannels;
}

class AzoomWorkspaceDto {
  const AzoomWorkspaceDto({
    required this.id,
    required this.companyName,
    required this.companySlug,
    required this.name,
    required this.members,
  });

  factory AzoomWorkspaceDto.fromJson(Map<String, dynamic> json) {
    return AzoomWorkspaceDto(
      id: json['id'] as String? ?? '',
      companyName: json['companyName'] as String? ?? '',
      companySlug: json['companySlug'] as String? ?? '',
      name: json['name'] as String? ?? '',
      members: [
        for (final item in json['members'] as List<dynamic>? ?? const [])
          AzoomMemberDto.fromJson((item as Map).cast<String, dynamic>()),
      ],
    );
  }

  final String id;
  final String companyName;
  final String companySlug;
  final String name;
  final List<AzoomMemberDto> members;
}

class AzoomMemberDto {
  const AzoomMemberDto({
    required this.accountId,
    required this.email,
    required this.displayName,
    required this.role,
  });

  factory AzoomMemberDto.fromJson(Map<String, dynamic> json) {
    return AzoomMemberDto(
      accountId: json['accountId'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      role: json['role'] as String? ?? 'MEMBER',
    );
  }

  final String accountId;
  final String email;
  final String displayName;
  final String role;
}

class AzoomInviteCandidateDto {
  const AzoomInviteCandidateDto({
    required this.accountId,
    required this.email,
    required this.displayName,
    required this.department,
    required this.position,
    required this.avatarColor,
    required this.avatarImageUrl,
  });

  factory AzoomInviteCandidateDto.fromJson(Map<String, dynamic> json) {
    return AzoomInviteCandidateDto(
      accountId: json['accountId'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      department: json['department'] as String? ?? '',
      position: json['position'] as String? ?? '',
      avatarColor: json['avatarColor'] as String? ?? '#7AA06A',
      avatarImageUrl: json['avatarImageUrl'] as String? ?? '',
    );
  }

  final String accountId;
  final String email;
  final String displayName;
  final String department;
  final String position;
  final String avatarColor;
  final String avatarImageUrl;
}

class AzoomCompanyUserDto {
  const AzoomCompanyUserDto({
    required this.accountId,
    required this.email,
    required this.displayName,
    required this.department,
    required this.position,
    required this.avatarColor,
    required this.avatarImageUrl,
  });

  factory AzoomCompanyUserDto.fromJson(Map<String, dynamic> json) {
    return AzoomCompanyUserDto(
      accountId: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName:
          (json['displayName'] as String?) ?? (json['name'] as String? ?? ''),
      department: json['department'] as String? ?? '',
      position: json['position'] as String? ?? '',
      avatarColor: json['avatarColor'] as String? ?? '#7AA06A',
      avatarImageUrl: json['avatarImageUrl'] as String? ?? '',
    );
  }

  final String accountId;
  final String email;
  final String displayName;
  final String department;
  final String position;
  final String avatarColor;
  final String avatarImageUrl;
}

class AzoomVoiceEffectDto {
  const AzoomVoiceEffectDto({
    required this.type,
    required this.channelId,
    required this.roomName,
    required this.senderUserId,
    required this.occurredAt,
  });

  factory AzoomVoiceEffectDto.fromJson(Map<String, dynamic> json) {
    return AzoomVoiceEffectDto(
      type: json['type'] as String? ?? '',
      channelId: json['channelId'] as String? ?? '',
      roomName: json['roomName'] as String? ?? '',
      senderUserId: json['senderUserId'] as String? ?? '',
      occurredAt: DateTime.tryParse(json['occurredAt'] as String? ?? ''),
    );
  }

  final String type;
  final String channelId;
  final String roomName;
  final String senderUserId;
  final DateTime? occurredAt;
}

class AzoomVoiceChannelDto {
  const AzoomVoiceChannelDto({
    required this.id,
    required this.name,
    required this.roomName,
    required this.startedAt,
    required this.serverNow,
    required this.receivedAt,
    required this.accessMode,
    required this.allowedDepartments,
    required this.canJoin,
    required this.participants,
  });

  factory AzoomVoiceChannelDto.fromJson(Map<String, dynamic> json) {
    final receivedAt = DateTime.now();
    return AzoomVoiceChannelDto(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      roomName: json['roomName'] as String? ?? '',
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
      serverNow: DateTime.tryParse(json['serverNow'] as String? ?? ''),
      receivedAt: receivedAt,
      accessMode: json['accessMode'] as String? ?? 'ALL',
      allowedDepartments: [
        for (final item
            in json['allowedDepartments'] as List<dynamic>? ?? const [])
          item.toString(),
      ],
      canJoin: json['canJoin'] as bool? ?? true,
      participants: [
        for (final item in json['participants'] as List<dynamic>? ?? const [])
          AzoomVoiceParticipantDto.fromJson(
            (item as Map).cast<String, dynamic>(),
          ),
      ],
    );
  }

  final String id;
  final String name;
  final String roomName;
  final DateTime? startedAt;
  final DateTime? serverNow;
  final DateTime? receivedAt;
  final String accessMode;
  final List<String> allowedDepartments;
  final bool canJoin;
  final List<AzoomVoiceParticipantDto> participants;

  AzoomVoiceChannelDto copyWith({
    DateTime? startedAt,
    DateTime? serverNow,
    DateTime? receivedAt,
    String? accessMode,
    List<String>? allowedDepartments,
    bool? canJoin,
    List<AzoomVoiceParticipantDto>? participants,
  }) {
    return AzoomVoiceChannelDto(
      id: id,
      name: name,
      roomName: roomName,
      startedAt: startedAt ?? this.startedAt,
      serverNow: serverNow ?? this.serverNow,
      receivedAt: receivedAt ?? this.receivedAt,
      accessMode: accessMode ?? this.accessMode,
      allowedDepartments: allowedDepartments ?? this.allowedDepartments,
      canJoin: canJoin ?? this.canJoin,
      participants: participants ?? this.participants,
    );
  }
}

class AzoomVoiceParticipantDto {
  const AzoomVoiceParticipantDto({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.nickname,
    required this.status,
    required this.avatarColor,
    required this.avatarImageUrl,
    required this.joinedAt,
    required this.muted,
    required this.deafened,
    required this.cameraEnabled,
    required this.screenSharing,
  });

  factory AzoomVoiceParticipantDto.fromJson(Map<String, dynamic> json) {
    return AzoomVoiceParticipantDto(
      userId: json['userId'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      status: json['status'] as String? ?? '',
      avatarColor: json['avatarColor'] as String? ?? '#7AA06A',
      avatarImageUrl: json['avatarImageUrl'] as String? ?? '',
      joinedAt: DateTime.tryParse(json['joinedAt'] as String? ?? ''),
      muted: json['muted'] as bool? ?? false,
      deafened: json['deafened'] as bool? ?? false,
      cameraEnabled: json['cameraEnabled'] as bool? ?? false,
      screenSharing: json['screenSharing'] as bool? ?? false,
    );
  }

  final String userId;
  final String email;
  final String displayName;
  final String nickname;
  final String status;
  final String avatarColor;
  final String avatarImageUrl;
  final DateTime? joinedAt;
  final bool muted;
  final bool deafened;
  final bool cameraEnabled;
  final bool screenSharing;
}

class AzoomVoiceJoinDto {
  const AzoomVoiceJoinDto({required this.channel, required this.liveKit});

  factory AzoomVoiceJoinDto.fromJson(Map<String, dynamic> json) {
    return AzoomVoiceJoinDto(
      channel: json['channel'] is Map
          ? AzoomVoiceChannelDto.fromJson(
              (json['channel'] as Map).cast<String, dynamic>(),
            )
          : const AzoomVoiceChannelDto(
              id: '',
              name: '',
              roomName: '',
              startedAt: null,
              serverNow: null,
              receivedAt: null,
              accessMode: 'ALL',
              allowedDepartments: [],
              canJoin: true,
              participants: [],
            ),
      liveKit: json['liveKit'] is Map
          ? AzoomLiveKitTokenDto.fromJson(
              (json['liveKit'] as Map).cast<String, dynamic>(),
            )
          : const AzoomLiveKitTokenDto.disabled(),
    );
  }

  final AzoomVoiceChannelDto channel;
  final AzoomLiveKitTokenDto liveKit;
}

class AzoomLiveKitTokenDto {
  const AzoomLiveKitTokenDto({
    required this.enabled,
    required this.url,
    required this.token,
    required this.roomName,
    required this.reason,
  });

  const AzoomLiveKitTokenDto.disabled()
    : enabled = false,
      url = '',
      token = '',
      roomName = '',
      reason = '';

  factory AzoomLiveKitTokenDto.fromJson(Map<String, dynamic> json) {
    return AzoomLiveKitTokenDto(
      enabled: json['enabled'] as bool? ?? false,
      url: json['url'] as String? ?? '',
      token: json['token'] as String? ?? '',
      roomName: json['roomName'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
    );
  }

  final bool enabled;
  final String url;
  final String token;
  final String roomName;
  final String reason;
}

class AzoomMeetingTranscriptSummaryDto {
  const AzoomMeetingTranscriptSummaryDto({
    required this.id,
    required this.channelId,
    required this.channelName,
    required this.roomName,
    required this.kind,
    required this.status,
    required this.titleTimestamp,
    required this.startedAt,
    required this.endedAt,
    required this.utteranceCount,
  });

  factory AzoomMeetingTranscriptSummaryDto.fromJson(Map<String, dynamic> json) {
    return AzoomMeetingTranscriptSummaryDto(
      id: json['id'] as String? ?? '',
      channelId: json['channelId'] as String? ?? '',
      channelName: json['channelName'] as String? ?? '',
      roomName: json['roomName'] as String? ?? '',
      kind: json['kind'] as String? ?? 'REALTIME',
      status: json['status'] as String? ?? 'READY',
      titleTimestamp: json['titleTimestamp'] as String? ?? '',
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
      endedAt: DateTime.tryParse(json['endedAt'] as String? ?? ''),
      utteranceCount: json['utteranceCount'] as int? ?? 0,
    );
  }

  final String id;
  final String channelId;
  final String channelName;
  final String roomName;
  final String kind;
  final String status;
  final String titleTimestamp;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int utteranceCount;
}

class AzoomMeetingTranscriptDto {
  const AzoomMeetingTranscriptDto({
    required this.id,
    required this.companyName,
    required this.companySlug,
    required this.channelId,
    required this.channelName,
    required this.roomName,
    required this.kind,
    required this.status,
    required this.titleTimestamp,
    required this.audioFilePath,
    required this.startedAt,
    required this.endedAt,
    required this.utterances,
  });

  const AzoomMeetingTranscriptDto.empty()
    : id = '',
      companyName = '',
      companySlug = '',
      channelId = '',
      channelName = '',
      roomName = '',
      kind = 'REALTIME',
      status = 'READY',
      titleTimestamp = '',
      audioFilePath = '',
      startedAt = null,
      endedAt = null,
      utterances = const [];

  factory AzoomMeetingTranscriptDto.fromJson(Map<String, dynamic> json) {
    return AzoomMeetingTranscriptDto(
      id: json['id'] as String? ?? '',
      companyName: json['companyName'] as String? ?? '',
      companySlug: json['companySlug'] as String? ?? '',
      channelId: json['channelId'] as String? ?? '',
      channelName: json['channelName'] as String? ?? '',
      roomName: json['roomName'] as String? ?? '',
      kind: json['kind'] as String? ?? 'REALTIME',
      status: json['status'] as String? ?? 'READY',
      titleTimestamp: json['titleTimestamp'] as String? ?? '',
      audioFilePath: json['audioFilePath'] as String? ?? '',
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
      endedAt: DateTime.tryParse(json['endedAt'] as String? ?? ''),
      utterances: [
        for (final item in json['utterances'] as List<dynamic>? ?? const [])
          AzoomMeetingUtteranceDto.fromJson(
            (item as Map).cast<String, dynamic>(),
          ),
      ],
    );
  }

  final String id;
  final String companyName;
  final String companySlug;
  final String channelId;
  final String channelName;
  final String roomName;
  final String kind;
  final String status;
  final String titleTimestamp;
  final String audioFilePath;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<AzoomMeetingUtteranceDto> utterances;
}

class AzoomMeetingUtteranceDto {
  const AzoomMeetingUtteranceDto({
    required this.id,
    required this.sequenceNo,
    required this.speakerUserId,
    required this.speakerName,
    required this.speakerEmail,
    required this.content,
    required this.startedAt,
    required this.endedAt,
  });

  factory AzoomMeetingUtteranceDto.fromJson(Map<String, dynamic> json) {
    return AzoomMeetingUtteranceDto(
      id: json['id'] as String? ?? '',
      sequenceNo: json['sequenceNo'] as int? ?? 0,
      speakerUserId: json['speakerUserId'] as String? ?? '',
      speakerName: json['speakerName'] as String? ?? '',
      speakerEmail: json['speakerEmail'] as String? ?? '',
      content: json['content'] as String? ?? '',
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
      endedAt: DateTime.tryParse(json['endedAt'] as String? ?? ''),
    );
  }

  final String id;
  final int sequenceNo;
  final String speakerUserId;
  final String speakerName;
  final String speakerEmail;
  final String content;
  final DateTime? startedAt;
  final DateTime? endedAt;
}

class AzoomNotivaSessionDto {
  const AzoomNotivaSessionDto({
    required this.roomName,
    required this.realtimeTranscript,
  });

  factory AzoomNotivaSessionDto.fromJson(Map<String, dynamic> json) {
    return AzoomNotivaSessionDto(
      roomName: json['roomName'] as String? ?? '',
      realtimeTranscript: json['realtimeTranscript'] is Map
          ? AzoomMeetingTranscriptDto.fromJson(
              (json['realtimeTranscript'] as Map).cast<String, dynamic>(),
            )
          : const AzoomMeetingTranscriptDto.empty(),
    );
  }

  final String roomName;
  final AzoomMeetingTranscriptDto realtimeTranscript;
}

class AzoomNotivaAudioDto {
  const AzoomNotivaAudioDto({
    required this.sourceFileName,
    required this.transcript,
  });

  factory AzoomNotivaAudioDto.fromJson(Map<String, dynamic> json) {
    return AzoomNotivaAudioDto(
      sourceFileName: json['sourceFileName'] as String? ?? '',
      transcript: json['transcript'] is Map
          ? AzoomMeetingTranscriptDto.fromJson(
              (json['transcript'] as Map).cast<String, dynamic>(),
            )
          : AzoomMeetingTranscriptDto.empty(),
    );
  }

  final String sourceFileName;
  final AzoomMeetingTranscriptDto transcript;
}

class AzoomNotivaEventDto {
  const AzoomNotivaEventDto({
    required this.type,
    required this.roomName,
    required this.transcript,
  });

  factory AzoomNotivaEventDto.fromJson(Map<String, dynamic> json) {
    return AzoomNotivaEventDto(
      type: json['type'] as String? ?? '',
      roomName: json['roomName'] as String? ?? '',
      transcript: json['transcript'] is Map
          ? AzoomMeetingTranscriptDto.fromJson(
              (json['transcript'] as Map).cast<String, dynamic>(),
            )
          : const AzoomMeetingTranscriptDto(
              id: '',
              companyName: '',
              companySlug: '',
              channelId: '',
              channelName: '',
              roomName: '',
              kind: 'REALTIME',
              status: 'READY',
              titleTimestamp: '',
              audioFilePath: '',
              startedAt: null,
              endedAt: null,
              utterances: [],
            ),
    );
  }

  final String type;
  final String roomName;
  final AzoomMeetingTranscriptDto transcript;
}
