import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/company_scope.dart';
import '../../auth/data/auth_api.dart';

final avaAiApiProvider = Provider<AvaAiApi>((ref) {
  return AvaAiApi(ref.watch(dioProvider), ref.watch(activeCompanyProvider));
});

class AvaAiApi {
  const AvaAiApi(this._dio, this._activeCompany);

  final Dio _dio;
  final String? _activeCompany;

  Future<List<AvaAiMessageDto>> messages(String accessToken) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/ai/messages',
      options: _authOptions(accessToken),
    );

    return [
      for (final item in response.data ?? const [])
        AvaAiMessageDto.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  Future<AvaAiChatExchangeDto> send({
    required String accessToken,
    required String content,
    List<String> workspacePaths = const [],
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/ai/messages',
      data: {
        'content': content,
        if (workspacePaths.isNotEmpty) 'workspacePaths': workspacePaths,
      },
      options: _authOptions(accessToken),
    );

    return AvaAiChatExchangeDto.fromJson(response.data ?? const {});
  }

  Future<void> resetMessages(String accessToken) async {
    await _dio.post<void>(
      '/api/ai/messages/reset',
      options: _authOptions(accessToken),
    );
  }

  Future<List<AvaAiWorkspaceItemDto>> workspaceFiles({
    required String accessToken,
    String path = '',
    String query = '',
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/ai/workspace/files',
      queryParameters: {
        if (path.isNotEmpty) 'path': path,
        if (query.isNotEmpty) 'query': query,
      },
      options: _authOptions(accessToken),
    );
    return [
      for (final item in response.data ?? const [])
        AvaAiWorkspaceItemDto.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  Future<AvaAiWorkspaceItemDto> readWorkspaceFile({
    required String accessToken,
    required String path,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/ai/workspace/files/content',
      queryParameters: {'path': path},
      options: _authOptions(accessToken),
    );
    return AvaAiWorkspaceItemDto.fromJson(response.data ?? const {});
  }

  Future<void> downloadWorkspaceFile({
    required String accessToken,
    required String path,
    required String savePath,
  }) async {
    await _dio.download(
      '/api/ai/workspace/files/preview',
      savePath,
      queryParameters: {'path': path},
      options: _authOptions(accessToken),
    );
  }

  Future<AvaAiWorkspaceItemDto> createWorkspaceFile({
    required String accessToken,
    required String path,
    required String content,
    bool isDirectory = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/ai/workspace/files',
      data: {'path': path, 'content': content, 'directory': isDirectory},
      options: _authOptions(accessToken),
    );
    return AvaAiWorkspaceItemDto.fromJson(response.data ?? const {});
  }

  Future<AvaAiWorkspaceItemDto> updateWorkspaceFile({
    required String accessToken,
    required String path,
    String? newPath,
    String? content,
  }) async {
    final data = <String, dynamic>{'path': path, 'directory': false};
    if (newPath != null) {
      data['newPath'] = newPath;
    }
    if (content != null) {
      data['content'] = content;
    }
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/ai/workspace/files',
      data: data,
      options: _authOptions(accessToken),
    );
    return AvaAiWorkspaceItemDto.fromJson(response.data ?? const {});
  }

  Future<AvaAiWorkspaceItemDto> deleteWorkspaceFile({
    required String accessToken,
    required String path,
  }) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/api/ai/workspace/files',
      queryParameters: {'path': path},
      options: _authOptions(accessToken),
    );
    return AvaAiWorkspaceItemDto.fromJson(response.data ?? const {});
  }

  Future<List<AvaAiWorkspaceItemDto>> uploadWorkspaceFiles({
    required String accessToken,
    required List<String> filePaths,
  }) async {
    final response = await _dio.post<List<dynamic>>(
      '/api/ai/workspace/uploads',
      data: FormData.fromMap({
        'files': [
          for (final path in filePaths)
            await MultipartFile.fromFile(path, filename: _fileName(path)),
        ],
      }),
      options: Options(
        headers: {'Authorization': 'Bearer $accessToken'},
        contentType: 'multipart/form-data',
        sendTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 5),
      ),
    );
    return [
      for (final item in response.data ?? const [])
        AvaAiWorkspaceItemDto.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  Future<AvaAiWorkspaceSendResultDto> sendWorkspaceToChat({
    required String accessToken,
    String roomCode = '',
    String targetName = '',
    String message = '',
    required List<String> paths,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/ai/workspace/send-to-chat',
      data: {
        if (roomCode.isNotEmpty) 'roomCode': roomCode,
        if (targetName.isNotEmpty) 'targetName': targetName,
        if (message.isNotEmpty) 'message': message,
        'paths': paths,
      },
      options: _authOptions(accessToken),
    );
    return AvaAiWorkspaceSendResultDto.fromJson(response.data ?? const {});
  }

  Future<AvaAiCalendarWorkspaceDto> calendarWorkspace({
    required String accessToken,
    String mode = 'today',
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/ai/calendar/workspace',
      queryParameters: {'mode': mode},
      options: _authOptions(accessToken),
    );
    return AvaAiCalendarWorkspaceDto.fromJson(response.data ?? const {});
  }

  Future<List<AvaAiNotionPageDto>> notionSearch({
    required String accessToken,
    String query = '',
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/ai/notion/search',
      queryParameters: {if (query.isNotEmpty) 'query': query},
      options: _authOptions(accessToken),
    );
    return [
      for (final item in response.data ?? const [])
        AvaAiNotionPageDto.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  Future<AvaAiNotionPageDto> notionPage({
    required String accessToken,
    required String id,
    String object = 'page',
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/ai/notion/pages/$id',
      queryParameters: {'object': object},
      options: _authOptions(accessToken),
    );
    return AvaAiNotionPageDto.fromJson(response.data ?? const {});
  }

  Future<AvaAiNotionCommandDto> notionCommand({
    required String accessToken,
    required String command,
    String activePageId = '',
    String activePageObject = '',
    bool approved = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/ai/notion/command',
      data: {
        'command': command,
        if (activePageId.isNotEmpty) 'activePageId': activePageId,
        if (activePageObject.isNotEmpty) 'activePageObject': activePageObject,
        'approved': approved,
      },
      options: _authOptions(accessToken),
    );
    return AvaAiNotionCommandDto.fromJson(response.data ?? const {});
  }

  Future<AvaAiNotionCommandDto> uploadNotionFiles({
    required String accessToken,
    required String targetId,
    required List<String> filePaths,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/ai/notion/uploads',
      data: FormData.fromMap({
        'targetId': targetId,
        'approved': true,
        'files': [
          for (final path in filePaths)
            await MultipartFile.fromFile(path, filename: _fileName(path)),
        ],
      }),
      options: Options(
        headers: {
          'Authorization': 'Bearer $accessToken',
          if (_activeCompany != null && _activeCompany.isNotEmpty)
            avaCompanyHeader: _activeCompany,
        },
        contentType: 'multipart/form-data',
        sendTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 5),
      ),
    );
    return AvaAiNotionCommandDto.fromJson(response.data ?? const {});
  }

  Options _authOptions(String accessToken) {
    return Options(
      headers: {
        'Authorization': 'Bearer $accessToken',
        if (_activeCompany != null && _activeCompany.isNotEmpty)
          avaCompanyHeader: _activeCompany,
      },
      receiveTimeout: const Duration(minutes: 4),
    );
  }
}

String _fileName(String path) {
  return path.split(RegExp(r'[\\/]')).last;
}

class AvaAiChatExchangeDto {
  const AvaAiChatExchangeDto({
    required this.userMessage,
    required this.assistantMessage,
    required this.workspaceItems,
    required this.workspaceStatus,
    required this.agentTask,
    required this.calendarWorkspace,
  });

  factory AvaAiChatExchangeDto.fromJson(Map<String, dynamic> json) {
    return AvaAiChatExchangeDto(
      userMessage: AvaAiMessageDto.fromJson(
        (json['userMessage'] as Map? ?? const {}).cast<String, dynamic>(),
      ),
      assistantMessage: AvaAiMessageDto.fromJson(
        (json['assistantMessage'] as Map? ?? const {}).cast<String, dynamic>(),
      ),
      workspaceItems: [
        for (final item in json['workspaceItems'] as List<dynamic>? ?? const [])
          AvaAiWorkspaceItemDto.fromJson((item as Map).cast<String, dynamic>()),
      ],
      workspaceStatus: json['workspaceStatus'] as String? ?? '',
      agentTask: json['agentTask'] is Map
          ? AvaAiAgentTaskDto.fromJson(
              (json['agentTask'] as Map).cast<String, dynamic>(),
            )
          : null,
      calendarWorkspace: json['calendarWorkspace'] is Map
          ? AvaAiCalendarWorkspaceDto.fromJson(
              (json['calendarWorkspace'] as Map).cast<String, dynamic>(),
            )
          : AvaAiCalendarWorkspaceDto.empty(),
    );
  }

  final AvaAiMessageDto userMessage;
  final AvaAiMessageDto assistantMessage;
  final List<AvaAiWorkspaceItemDto> workspaceItems;
  final String workspaceStatus;
  final AvaAiAgentTaskDto? agentTask;
  final AvaAiCalendarWorkspaceDto calendarWorkspace;
}

class AvaAiCalendarWorkspaceDto {
  const AvaAiCalendarWorkspaceDto({
    required this.handled,
    required this.mutation,
    required this.requiresClarification,
    required this.mode,
    required this.status,
    required this.selectedEventId,
    required this.summary,
    required this.events,
    required this.conflicts,
    required this.availability,
    required this.metadata,
  });

  factory AvaAiCalendarWorkspaceDto.empty() {
    return const AvaAiCalendarWorkspaceDto(
      handled: false,
      mutation: false,
      requiresClarification: false,
      mode: '',
      status: '',
      selectedEventId: '',
      summary: null,
      events: [],
      conflicts: [],
      availability: [],
      metadata: {},
    );
  }

  factory AvaAiCalendarWorkspaceDto.fromJson(Map<String, dynamic> json) {
    return AvaAiCalendarWorkspaceDto(
      handled: json['handled'] as bool? ?? false,
      mutation: json['mutation'] as bool? ?? false,
      requiresClarification: json['requiresClarification'] as bool? ?? false,
      mode: json['mode'] as String? ?? '',
      status: json['status'] as String? ?? '',
      selectedEventId: json['selectedEventId'] as String? ?? '',
      summary: json['summary'] is Map
          ? AvaAiCalendarSummaryDto.fromJson(
              (json['summary'] as Map).cast<String, dynamic>(),
            )
          : null,
      events: [
        for (final item in json['events'] as List<dynamic>? ?? const [])
          AvaAiCalendarEventCardDto.fromJson(
            (item as Map).cast<String, dynamic>(),
          ),
      ],
      conflicts: [
        for (final item in json['conflicts'] as List<dynamic>? ?? const [])
          AvaAiCalendarConflictDto.fromJson(
            (item as Map).cast<String, dynamic>(),
          ),
      ],
      availability: [
        for (final item in json['availability'] as List<dynamic>? ?? const [])
          AvaAiCalendarAvailabilityDto.fromJson(
            (item as Map).cast<String, dynamic>(),
          ),
      ],
      metadata: (json['metadata'] as Map? ?? const {}).cast<String, dynamic>(),
    );
  }

  final bool handled;
  final bool mutation;
  final bool requiresClarification;
  final String mode;
  final String status;
  final String selectedEventId;
  final AvaAiCalendarSummaryDto? summary;
  final List<AvaAiCalendarEventCardDto> events;
  final List<AvaAiCalendarConflictDto> conflicts;
  final List<AvaAiCalendarAvailabilityDto> availability;
  final Map<String, dynamic> metadata;

  bool get hasSignal =>
      handled ||
      events.isNotEmpty ||
      conflicts.isNotEmpty ||
      availability.isNotEmpty ||
      status.trim().isNotEmpty;

  AvaAiCalendarEventCardDto? selectedEvent([String overrideId = '']) {
    final id = overrideId.isNotEmpty ? overrideId : selectedEventId;
    if (id.isEmpty) {
      return events.isEmpty ? null : events.first;
    }
    for (final event in events) {
      if (event.id == id) {
        return event;
      }
    }
    return events.isEmpty ? null : events.first;
  }

  AvaAiCalendarWorkspaceDto copyWith({String? selectedEventId}) {
    return AvaAiCalendarWorkspaceDto(
      handled: handled,
      mutation: mutation,
      requiresClarification: requiresClarification,
      mode: mode,
      status: status,
      selectedEventId: selectedEventId ?? this.selectedEventId,
      summary: summary,
      events: events,
      conflicts: conflicts,
      availability: availability,
      metadata: metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'handled': handled,
      'mutation': mutation,
      'requiresClarification': requiresClarification,
      'mode': mode,
      'status': status,
      'selectedEventId': selectedEventId,
      if (summary != null) 'summary': summary!.toJson(),
      'events': [for (final event in events) event.toJson()],
      'conflicts': [for (final conflict in conflicts) conflict.toJson()],
      'availability': [
        for (final suggestion in availability) suggestion.toJson(),
      ],
      'metadata': metadata,
    };
  }
}

class AvaAiCalendarSummaryDto {
  const AvaAiCalendarSummaryDto({
    required this.title,
    required this.rangeStart,
    required this.rangeEnd,
    required this.totalCount,
    required this.countsByStatus,
  });

  factory AvaAiCalendarSummaryDto.fromJson(Map<String, dynamic> json) {
    return AvaAiCalendarSummaryDto(
      title: json['title'] as String? ?? '',
      rangeStart: DateTime.tryParse(json['rangeStart'] as String? ?? ''),
      rangeEnd: DateTime.tryParse(json['rangeEnd'] as String? ?? ''),
      totalCount: json['totalCount'] as int? ?? 0,
      countsByStatus: {
        for (final entry
            in (json['countsByStatus'] as Map? ?? const {}).entries)
          entry.key.toString(): (entry.value as num?)?.toInt() ?? 0,
      },
    );
  }

  final String title;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final int totalCount;
  final Map<String, int> countsByStatus;

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      if (rangeStart != null) 'rangeStart': rangeStart!.toIso8601String(),
      if (rangeEnd != null) 'rangeEnd': rangeEnd!.toIso8601String(),
      'totalCount': totalCount,
      'countsByStatus': countsByStatus,
    };
  }
}

class AvaAiCalendarEventCardDto {
  const AvaAiCalendarEventCardDto({
    required this.id,
    required this.title,
    required this.description,
    required this.startAt,
    required this.endAt,
    required this.allDay,
    required this.location,
    required this.status,
    required this.statusLabel,
    required this.categoryName,
    required this.teamId,
    required this.teamLabel,
    required this.importance,
    required this.importanceLabel,
    required this.color,
    required this.hasAzoom,
    required this.hasChat,
    required this.hasFiles,
    required this.hasNotion,
    required this.memo,
  });

  factory AvaAiCalendarEventCardDto.fromJson(Map<String, dynamic> json) {
    return AvaAiCalendarEventCardDto(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      startAt: DateTime.tryParse(json['startAt'] as String? ?? ''),
      endAt: DateTime.tryParse(json['endAt'] as String? ?? ''),
      allDay: json['allDay'] as bool? ?? false,
      location: json['location'] as String? ?? '',
      status: json['status'] as String? ?? '',
      statusLabel: json['statusLabel'] as String? ?? '',
      categoryName: json['categoryName'] as String? ?? '',
      teamId: json['teamId'] as String? ?? '',
      teamLabel: json['teamLabel'] as String? ?? '',
      importance: json['importance'] as String? ?? 'NORMAL',
      importanceLabel: json['importanceLabel'] as String? ?? '',
      color: json['color'] as String? ?? '',
      hasAzoom: json['hasAzoom'] as bool? ?? false,
      hasChat: json['hasChat'] as bool? ?? false,
      hasFiles: json['hasFiles'] as bool? ?? false,
      hasNotion: json['hasNotion'] as bool? ?? false,
      memo: json['memo'] as String? ?? '',
    );
  }

  final String id;
  final String title;
  final String description;
  final DateTime? startAt;
  final DateTime? endAt;
  final bool allDay;
  final String location;
  final String status;
  final String statusLabel;
  final String categoryName;
  final String teamId;
  final String teamLabel;
  final String importance;
  final String importanceLabel;
  final String color;
  final bool hasAzoom;
  final bool hasChat;
  final bool hasFiles;
  final bool hasNotion;
  final String memo;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      if (startAt != null) 'startAt': startAt!.toIso8601String(),
      if (endAt != null) 'endAt': endAt!.toIso8601String(),
      'allDay': allDay,
      'location': location,
      'status': status,
      'statusLabel': statusLabel,
      'categoryName': categoryName,
      'teamId': teamId,
      'teamLabel': teamLabel,
      'importance': importance,
      'importanceLabel': importanceLabel,
      'color': color,
      'hasAzoom': hasAzoom,
      'hasChat': hasChat,
      'hasFiles': hasFiles,
      'hasNotion': hasNotion,
      'memo': memo,
    };
  }
}

class AvaAiCalendarConflictDto {
  const AvaAiCalendarConflictDto({
    required this.eventId,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.reason,
    required this.ownerName,
  });

  factory AvaAiCalendarConflictDto.fromJson(Map<String, dynamic> json) {
    return AvaAiCalendarConflictDto(
      eventId: json['eventId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      startAt: DateTime.tryParse(json['startAt'] as String? ?? ''),
      endAt: DateTime.tryParse(json['endAt'] as String? ?? ''),
      reason: json['reason'] as String? ?? '',
      ownerName: json['ownerName'] as String? ?? '',
    );
  }

  final String eventId;
  final String title;
  final DateTime? startAt;
  final DateTime? endAt;
  final String reason;
  final String ownerName;

  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'title': title,
      if (startAt != null) 'startAt': startAt!.toIso8601String(),
      if (endAt != null) 'endAt': endAt!.toIso8601String(),
      'reason': reason,
      'ownerName': ownerName,
    };
  }
}

class AvaAiCalendarAvailabilityDto {
  const AvaAiCalendarAvailabilityDto({
    required this.startAt,
    required this.endAt,
    required this.score,
  });

  factory AvaAiCalendarAvailabilityDto.fromJson(Map<String, dynamic> json) {
    return AvaAiCalendarAvailabilityDto(
      startAt: DateTime.tryParse(json['startAt'] as String? ?? ''),
      endAt: DateTime.tryParse(json['endAt'] as String? ?? ''),
      score: json['score'] as int? ?? 0,
    );
  }

  final DateTime? startAt;
  final DateTime? endAt;
  final int score;

  Map<String, dynamic> toJson() {
    return {
      if (startAt != null) 'startAt': startAt!.toIso8601String(),
      if (endAt != null) 'endAt': endAt!.toIso8601String(),
      'score': score,
    };
  }
}

class AvaAiAgentTaskDto {
  const AvaAiAgentTaskDto({
    required this.id,
    required this.status,
    required this.mode,
    required this.riskLevel,
    required this.goal,
    required this.currentStep,
    required this.summary,
    required this.verificationSummary,
    required this.failureReason,
    required this.steps,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AvaAiAgentTaskDto.fromJson(Map<String, dynamic> json) {
    return AvaAiAgentTaskDto(
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      mode: json['mode'] as String? ?? '',
      riskLevel: json['riskLevel'] as String? ?? '',
      goal: json['goal'] as String? ?? '',
      currentStep: json['currentStep'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      verificationSummary: json['verificationSummary'] as String? ?? '',
      failureReason: json['failureReason'] as String? ?? '',
      steps: [
        for (final item in json['steps'] as List<dynamic>? ?? const [])
          AvaAiAgentStepDto.fromJson((item as Map).cast<String, dynamic>()),
      ],
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }

  final String id;
  final String status;
  final String mode;
  final String riskLevel;
  final String goal;
  final String currentStep;
  final String summary;
  final String verificationSummary;
  final String failureReason;
  final List<AvaAiAgentStepDto> steps;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get statusLabel {
    return switch (status.toLowerCase()) {
      'done' => '완료',
      'recovered' => '복구 완료',
      'failed' => '실패',
      'waiting_approval' => '승인 필요',
      'verifying' => '검증 중',
      'running' => '실행 중',
      'planning' => '계획 중',
      'skipped' => '건너뜀',
      _ => status.isEmpty ? '대기' : status,
    };
  }

  String get statusLine {
    final detail = summary.isNotEmpty
        ? summary
        : verificationSummary.isNotEmpty
        ? verificationSummary
        : currentStep;
    final stepCount = steps.isEmpty ? '' : ' / ${steps.length}단계';
    return [
      '에이전트 $statusLabel$stepCount',
      if (mode.isNotEmpty) mode,
      if (detail.isNotEmpty) detail,
    ].join(' · ');
  }
}

class AvaAiAgentStepDto {
  const AvaAiAgentStepDto({
    required this.id,
    required this.stepIndex,
    required this.toolName,
    required this.status,
    required this.description,
    required this.resultSummary,
    required this.verificationSummary,
    required this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AvaAiAgentStepDto.fromJson(Map<String, dynamic> json) {
    return AvaAiAgentStepDto(
      id: json['id'] as String? ?? '',
      stepIndex: json['stepIndex'] as int? ?? 0,
      toolName: json['toolName'] as String? ?? '',
      status: json['status'] as String? ?? '',
      description: json['description'] as String? ?? '',
      resultSummary: json['resultSummary'] as String? ?? '',
      verificationSummary: json['verificationSummary'] as String? ?? '',
      errorMessage: json['errorMessage'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }

  final String id;
  final int stepIndex;
  final String toolName;
  final String status;
  final String description;
  final String resultSummary;
  final String verificationSummary;
  final String errorMessage;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class AvaAiMessageDto {
  const AvaAiMessageDto({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    required this.references,
  });

  factory AvaAiMessageDto.fromJson(Map<String, dynamic> json) {
    return AvaAiMessageDto(
      id: json['id'] as String? ?? '',
      role: json['role'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      references: [
        for (final item in json['references'] as List<dynamic>? ?? const [])
          AvaAiReferenceDto.fromJson((item as Map).cast<String, dynamic>()),
      ],
    );
  }

  final String id;
  final String role;
  final String content;
  final DateTime? createdAt;
  final List<AvaAiReferenceDto> references;

  bool get isUser => role.toLowerCase() == 'user';
}

class AvaAiReferenceDto {
  const AvaAiReferenceDto({
    required this.id,
    required this.questionPreview,
    required this.answerPreview,
    required this.createdAt,
  });

  factory AvaAiReferenceDto.fromJson(Map<String, dynamic> json) {
    return AvaAiReferenceDto(
      id: json['id'] as String? ?? '',
      questionPreview: json['questionPreview'] as String? ?? '',
      answerPreview: json['answerPreview'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }

  final String id;
  final String questionPreview;
  final String answerPreview;
  final DateTime? createdAt;
}

class AvaAiWorkspaceItemDto {
  const AvaAiWorkspaceItemDto({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.path,
    required this.url,
    required this.imageUrl,
    required this.content,
    required this.size,
    required this.updatedAt,
    required this.roomCode,
  });

  factory AvaAiWorkspaceItemDto.fromJson(Map<String, dynamic> json) {
    return AvaAiWorkspaceItemDto(
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      path: json['path'] as String? ?? '',
      url: json['url'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      content: json['content'] as String? ?? '',
      size: json['size'] as int?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      roomCode: json['roomCode'] as String? ?? '',
    );
  }

  final String type;
  final String title;
  final String subtitle;
  final String path;
  final String url;
  final String imageUrl;
  final String content;
  final int? size;
  final DateTime? updatedAt;
  final String roomCode;

  bool get isSendableFile =>
      path.isNotEmpty &&
      (type == 'file' || type == 'chat_file' || type == 'chat_image');

  bool get isDirectory => type == 'directory';

  bool get isWorkspaceFile => type == 'file';

  bool get isWorkspacePath => type == 'file' || type == 'directory';
}

class AvaAiWorkspaceSendResultDto {
  const AvaAiWorkspaceSendResultDto({
    required this.status,
    required this.items,
  });

  factory AvaAiWorkspaceSendResultDto.fromJson(Map<String, dynamic> json) {
    return AvaAiWorkspaceSendResultDto(
      status: json['status'] as String? ?? '',
      items: [
        for (final item in json['items'] as List<dynamic>? ?? const [])
          AvaAiWorkspaceItemDto.fromJson((item as Map).cast<String, dynamic>()),
      ],
    );
  }

  final String status;
  final List<AvaAiWorkspaceItemDto> items;
}

class AvaAiNotionCommandDto {
  const AvaAiNotionCommandDto({
    required this.answer,
    required this.status,
    required this.results,
    required this.requiresApproval,
    required this.approvalTitle,
    required this.approvalDescription,
    required this.executionMode,
    this.activePage,
  });

  factory AvaAiNotionCommandDto.fromJson(Map<String, dynamic> json) {
    final activePageJson = json['activePage'];
    return AvaAiNotionCommandDto(
      answer: json['answer'] as String? ?? '',
      status: json['status'] as String? ?? '',
      activePage: activePageJson is Map
          ? AvaAiNotionPageDto.fromJson(activePageJson.cast<String, dynamic>())
          : null,
      results: [
        for (final item in json['results'] as List<dynamic>? ?? const [])
          AvaAiNotionPageDto.fromJson((item as Map).cast<String, dynamic>()),
      ],
      requiresApproval: json['requiresApproval'] as bool? ?? false,
      approvalTitle: json['approvalTitle'] as String? ?? '',
      approvalDescription: json['approvalDescription'] as String? ?? '',
      executionMode: json['executionMode'] as String? ?? '',
    );
  }

  final String answer;
  final String status;
  final AvaAiNotionPageDto? activePage;
  final List<AvaAiNotionPageDto> results;
  final bool requiresApproval;
  final String approvalTitle;
  final String approvalDescription;
  final String executionMode;
}

class AvaAiNotionPageDto {
  const AvaAiNotionPageDto({
    required this.id,
    required this.object,
    required this.title,
    required this.subtitle,
    required this.url,
    required this.icon,
    required this.coverUrl,
    required this.content,
    required this.properties,
    required this.blocks,
    required this.children,
    required this.updatedAt,
  });

  factory AvaAiNotionPageDto.fromJson(Map<String, dynamic> json) {
    return AvaAiNotionPageDto(
      id: json['id'] as String? ?? '',
      object: json['object'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      url: json['url'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      coverUrl: json['coverUrl'] as String? ?? '',
      content: json['content'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      properties: [
        for (final item in json['properties'] as List<dynamic>? ?? const [])
          AvaAiNotionPropertyDto.fromJson(
            (item as Map).cast<String, dynamic>(),
          ),
      ],
      blocks: [
        for (final item in json['blocks'] as List<dynamic>? ?? const [])
          AvaAiNotionBlockDto.fromJson((item as Map).cast<String, dynamic>()),
      ],
      children: [
        for (final item in json['children'] as List<dynamic>? ?? const [])
          AvaAiNotionPageDto.fromJson((item as Map).cast<String, dynamic>()),
      ],
    );
  }

  final String id;
  final String object;
  final String title;
  final String subtitle;
  final String url;
  final String icon;
  final String coverUrl;
  final String content;
  final DateTime? updatedAt;
  final List<AvaAiNotionPropertyDto> properties;
  final List<AvaAiNotionBlockDto> blocks;
  final List<AvaAiNotionPageDto> children;
}

class AvaAiNotionPropertyDto {
  const AvaAiNotionPropertyDto({
    required this.name,
    required this.type,
    required this.value,
    required this.color,
  });

  factory AvaAiNotionPropertyDto.fromJson(Map<String, dynamic> json) {
    return AvaAiNotionPropertyDto(
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      value: json['value'] as String? ?? '',
      color: json['color'] as String? ?? '',
    );
  }

  final String name;
  final String type;
  final String value;
  final String color;
}

class AvaAiNotionBlockDto {
  const AvaAiNotionBlockDto({
    required this.id,
    required this.type,
    required this.text,
    required this.depth,
    required this.checked,
    required this.url,
    required this.icon,
    required this.color,
    required this.cells,
    required this.children,
    this.database,
  });

  factory AvaAiNotionBlockDto.fromJson(Map<String, dynamic> json) {
    return AvaAiNotionBlockDto(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      text: json['text'] as String? ?? '',
      depth: json['depth'] as int? ?? 0,
      checked: json['checked'] as bool? ?? false,
      url: json['url'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      color: json['color'] as String? ?? '',
      cells: [
        for (final row in json['cells'] as List<dynamic>? ?? const [])
          [
            for (final cell in row as List<dynamic>? ?? const [])
              cell.toString(),
          ],
      ],
      children: [
        for (final item in json['children'] as List<dynamic>? ?? const [])
          AvaAiNotionBlockDto.fromJson((item as Map).cast<String, dynamic>()),
      ],
      database: json['database'] is Map
          ? AvaAiNotionPageDto.fromJson(
              (json['database'] as Map).cast<String, dynamic>(),
            )
          : null,
    );
  }

  final String id;
  final String type;
  final String text;
  final int depth;
  final bool checked;
  final String url;
  final String icon;
  final String color;
  final List<List<String>> cells;
  final List<AvaAiNotionBlockDto> children;
  final AvaAiNotionPageDto? database;
}
