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
    );
  }

  final AvaAiMessageDto userMessage;
  final AvaAiMessageDto assistantMessage;
  final List<AvaAiWorkspaceItemDto> workspaceItems;
  final String workspaceStatus;
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
