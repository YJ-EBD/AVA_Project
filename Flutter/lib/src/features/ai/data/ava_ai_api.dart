import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_api.dart';

final avaAiApiProvider = Provider<AvaAiApi>((ref) {
  return AvaAiApi(ref.watch(dioProvider));
});

class AvaAiApi {
  const AvaAiApi(this._dio);

  final Dio _dio;

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
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/ai/messages',
      data: {'content': content},
      options: _authOptions(accessToken),
    );

    return AvaAiChatExchangeDto.fromJson(response.data ?? const {});
  }

  Options _authOptions(String accessToken) {
    return Options(
      headers: {'Authorization': 'Bearer $accessToken'},
      receiveTimeout: const Duration(minutes: 4),
    );
  }
}

class AvaAiChatExchangeDto {
  const AvaAiChatExchangeDto({
    required this.userMessage,
    required this.assistantMessage,
  });

  factory AvaAiChatExchangeDto.fromJson(Map<String, dynamic> json) {
    return AvaAiChatExchangeDto(
      userMessage: AvaAiMessageDto.fromJson(
        (json['userMessage'] as Map? ?? const {}).cast<String, dynamic>(),
      ),
      assistantMessage: AvaAiMessageDto.fromJson(
        (json['assistantMessage'] as Map? ?? const {}).cast<String, dynamic>(),
      ),
    );
  }

  final AvaAiMessageDto userMessage;
  final AvaAiMessageDto assistantMessage;
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
