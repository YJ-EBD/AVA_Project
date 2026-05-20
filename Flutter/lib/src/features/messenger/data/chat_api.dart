import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/application/company_scope.dart';
import '../../../features/auth/data/auth_api.dart';

final chatApiProvider = Provider<ChatApi>((ref) {
  return ChatApi(ref.watch(dioProvider), ref.watch(activeCompanyProvider));
});

class ChatApi {
  const ChatApi(this._dio, this._activeCompany);

  final Dio _dio;
  final String? _activeCompany;

  Future<List<ChatRoomDto>> rooms(String accessToken) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/chat/rooms',
      options: _authOptions(accessToken),
    );

    return [
      for (final item in response.data ?? const [])
        ChatRoomDto.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  Future<List<UserProfileDto>> users(String accessToken) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/users',
      options: _authOptions(accessToken),
    );

    return [
      for (final item in response.data ?? const [])
        UserProfileDto.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  Future<List<UserProfileDto>> searchEmployees({
    required String accessToken,
    String? name,
    String? phoneNumber,
    String? email,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/users/company/employees/search',
      queryParameters: {
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (phoneNumber != null && phoneNumber.trim().isNotEmpty)
          'phoneNumber': phoneNumber.trim(),
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      },
      options: _authOptions(accessToken),
    );

    return [
      for (final item in response.data ?? const [])
        UserProfileDto.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  Future<UserProfileDto> addCompanyEmployee({
    required String accessToken,
    String? targetUserId,
    String? email,
    String? name,
    String? phoneNumber,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/users/company/employees',
      data: {
        if (targetUserId != null && targetUserId.isNotEmpty)
          'targetUserId': targetUserId,
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (phoneNumber != null && phoneNumber.trim().isNotEmpty)
          'phoneNumber': phoneNumber.trim(),
      },
      options: _authOptions(accessToken),
    );

    return UserProfileDto.fromJson(response.data ?? const {});
  }

  Future<UserProfileDto> blockCompanyEmployee({
    required String accessToken,
    String? targetUserId,
    String? email,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/users/company/blocked-employees',
      data: {
        if (targetUserId != null && targetUserId.isNotEmpty)
          'targetUserId': targetUserId,
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      },
      options: _authOptions(accessToken),
    );

    return UserProfileDto.fromJson(response.data ?? const {});
  }

  Future<UserProfileDto> unblockCompanyEmployee({
    required String accessToken,
    String? targetUserId,
    String? email,
  }) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/api/users/company/blocked-employees',
      data: {
        if (targetUserId != null && targetUserId.isNotEmpty)
          'targetUserId': targetUserId,
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      },
      options: _authOptions(accessToken),
    );

    return UserProfileDto.fromJson(response.data ?? const {});
  }

  Future<List<ChatFolderDto>> chatFolders(String accessToken) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/users/me/chat-folders',
      options: _authOptions(accessToken),
    );

    return [
      for (final item in response.data ?? const [])
        ChatFolderDto.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  Future<List<ChatFolderDto>> saveChatFolders({
    required String accessToken,
    required List<ChatFolderDto> folders,
  }) async {
    final response = await _dio.put<List<dynamic>>(
      '/api/users/me/chat-folders',
      data: {
        'folders': [for (final folder in folders) folder.toJson()],
      },
      options: _authOptions(accessToken),
    );

    return [
      for (final item in response.data ?? const [])
        ChatFolderDto.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  Future<List<String>> chatFolderOrder(String accessToken) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/users/me/chat-folder-order',
      options: _authOptions(accessToken),
    );

    return [
      for (final item in response.data ?? const [])
        if (item is String && item.isNotEmpty) item,
    ];
  }

  Future<List<String>> saveChatFolderOrder({
    required String accessToken,
    required List<String> filterIds,
  }) async {
    final response = await _dio.put<List<dynamic>>(
      '/api/users/me/chat-folder-order',
      data: {'filterIds': filterIds},
      options: _authOptions(accessToken),
    );

    return [
      for (final item in response.data ?? const [])
        if (item is String && item.isNotEmpty) item,
    ];
  }

  Future<List<String>> quietChatRooms(String accessToken) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/users/me/quiet-chat-rooms',
      options: _authOptions(accessToken),
    );

    return [
      for (final item in response.data ?? const [])
        if (item is String && item.isNotEmpty) item,
    ];
  }

  Future<List<String>> saveQuietChatRooms({
    required String accessToken,
    required List<String> roomIds,
  }) async {
    final response = await _dio.put<List<dynamic>>(
      '/api/users/me/quiet-chat-rooms',
      data: {'roomIds': roomIds},
      options: _authOptions(accessToken),
    );

    return [
      for (final item in response.data ?? const [])
        if (item is String && item.isNotEmpty) item,
    ];
  }

  Future<List<ChatMessageDto>> messages({
    required String accessToken,
    required String roomCode,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/chat/rooms/$roomCode/messages',
      options: _authOptions(accessToken),
    );

    return [
      for (final item in response.data ?? const [])
        ChatMessageDto.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  Future<ChatMessageDto> send({
    required String accessToken,
    required String roomCode,
    required String content,
    bool silent = false,
    bool spoiler = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/chat/rooms/$roomCode/messages',
      data: {'content': content, 'silent': silent, 'spoiler': spoiler},
      options: _authOptions(accessToken),
    );

    return ChatMessageDto.fromJson(response.data ?? const {});
  }

  Future<ChatMessageDto> uploadAttachment({
    required String accessToken,
    required String roomCode,
    required String filePath,
    required String fileName,
    String? groupId,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/chat/rooms/$roomCode/attachments',
      data: FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
        if (groupId != null && groupId.isNotEmpty) 'groupId': groupId,
      }),
      options: Options(
        headers: {'Authorization': 'Bearer $accessToken'},
        contentType: 'multipart/form-data',
        sendTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 5),
      ),
      onSendProgress: onSendProgress,
    );

    return ChatMessageDto.fromJson(response.data ?? const {});
  }

  Future<void> downloadAttachment({
    required String accessToken,
    required String downloadUrl,
    required String savePath,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    await _dio.download(
      downloadUrl,
      savePath,
      options: Options(
        headers: {'Authorization': 'Bearer $accessToken'},
        receiveTimeout: const Duration(minutes: 10),
      ),
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<ChatReadStateDto> markRead({
    required String accessToken,
    required String roomCode,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/chat/rooms/$roomCode/read',
      options: _authOptions(accessToken),
    );

    return ChatReadStateDto.fromJson(response.data ?? const {});
  }

  Future<ChatRoomLeaveDto> leaveRoom({
    required String accessToken,
    required String roomCode,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/chat/rooms/$roomCode/leave',
      options: _authOptions(accessToken),
    );

    return ChatRoomLeaveDto.fromJson(response.data ?? const {});
  }

  Future<ChatRoomDto> setNotice({
    required String accessToken,
    required String roomCode,
    required String senderName,
    required String content,
    String? messageId,
    String? senderId,
    DateTime? sentAt,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/chat/rooms/$roomCode/notice',
      data: {
        if (messageId != null && messageId.isNotEmpty) 'messageId': messageId,
        if (senderId != null && senderId.isNotEmpty) 'senderId': senderId,
        'senderName': senderName,
        'content': content,
        if (sentAt != null) 'sentAt': sentAt.toUtc().toIso8601String(),
      },
      options: _authOptions(accessToken),
    );

    return ChatRoomDto.fromJson(response.data ?? const {});
  }

  Future<ChatRoomDto> setPinned({
    required String accessToken,
    required String roomCode,
    required bool pinned,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/chat/rooms/$roomCode/pin',
      data: {'pinned': pinned},
      options: _authOptions(accessToken),
    );

    return ChatRoomDto.fromJson(response.data ?? const {});
  }

  Future<ChatRoomDto> startDirectRoom({
    required String accessToken,
    required String targetName,
    String? targetUserId,
    String? targetEmail,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/chat/direct-rooms',
      data: {
        if (targetUserId != null && targetUserId.isNotEmpty)
          'targetUserId': targetUserId,
        'targetName': targetName,
        if (targetEmail != null && targetEmail.isNotEmpty)
          'targetEmail': targetEmail,
      },
      options: _authOptions(accessToken),
    );

    return ChatRoomDto.fromJson(response.data ?? const {});
  }

  Future<ChatRoomDto> startGroupRoom({
    required String accessToken,
    required List<String> targetUserIds,
    String? title,
    String? avatarImageUrl,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/chat/group-rooms',
      data: {
        'targetUserIds': targetUserIds,
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        if (avatarImageUrl != null && avatarImageUrl.trim().isNotEmpty)
          'avatarImageUrl': avatarImageUrl.trim(),
      },
      options: _authOptions(accessToken),
    );

    return ChatRoomDto.fromJson(response.data ?? const {});
  }

  Future<ChatRoomDto> startSelfRoom({required String accessToken}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/chat/self-room',
      options: _authOptions(accessToken),
    );

    return ChatRoomDto.fromJson(response.data ?? const {});
  }

  Future<UserProfileDto> updateProfile({
    required String accessToken,
    String? nickname,
    String? statusMessage,
    String? avatarImageUrl,
    String? profileBackgroundColor,
    String? profileBackgroundImageUrl,
  }) async {
    final data = <String, dynamic>{};
    if (nickname != null) {
      data['nickname'] = nickname;
    }
    if (statusMessage != null) {
      data['statusMessage'] = statusMessage;
    }
    if (avatarImageUrl != null) {
      data['avatarImageUrl'] = avatarImageUrl;
    }
    if (profileBackgroundColor != null) {
      data['profileBackgroundColor'] = profileBackgroundColor;
    }
    if (profileBackgroundImageUrl != null) {
      data['profileBackgroundImageUrl'] = profileBackgroundImageUrl;
    }

    final response = await _dio.put<Map<String, dynamic>>(
      '/api/users/me/profile',
      data: data,
      options: _authOptions(accessToken),
    );

    return UserProfileDto.fromJson(response.data ?? const {});
  }

  Options _authOptions(String accessToken) {
    return Options(
      headers: {
        'Authorization': 'Bearer $accessToken',
        if (_activeCompany != null && _activeCompany.isNotEmpty)
          avaCompanyHeader: _activeCompany,
      },
    );
  }
}

class ChatFolderDto {
  const ChatFolderDto({
    required this.id,
    required this.name,
    required this.icon,
    required this.roomIds,
    required this.favorite,
  });

  factory ChatFolderDto.fromJson(Map<String, dynamic> json) {
    return ChatFolderDto(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      roomIds: [
        for (final item in json['roomIds'] as List<dynamic>? ?? const [])
          if (item is String && item.isNotEmpty) item,
      ],
      favorite:
          json['favorite'] as bool? ?? json['isFavorite'] as bool? ?? false,
    );
  }

  final String id;
  final String name;
  final String icon;
  final List<String> roomIds;
  final bool favorite;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'roomIds': roomIds,
      'favorite': favorite,
    };
  }
}

class ChatRoomDto {
  const ChatRoomDto({
    required this.code,
    required this.title,
    required this.type,
    required this.participantCount,
    required this.pinned,
    required this.pinnedAt,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.lastMessageSpoiler,
    required this.avatarImageUrl,
    required this.notice,
    required this.members,
    required this.unreadCount,
  });

  const ChatRoomDto.empty()
    : code = '',
      title = '',
      type = 'GROUP',
      participantCount = 0,
      pinned = false,
      pinnedAt = null,
      lastMessage = '',
      lastMessageAt = null,
      lastMessageSpoiler = false,
      avatarImageUrl = '',
      notice = null,
      members = const [],
      unreadCount = 0;

  factory ChatRoomDto.fromJson(Map<String, dynamic> json) {
    return ChatRoomDto(
      code: json['code'] as String? ?? '',
      title: json['title'] as String? ?? '',
      type: json['type'] as String? ?? 'GROUP',
      participantCount: (json['participantCount'] as num?)?.toInt() ?? 0,
      pinned: json['pinned'] as bool? ?? false,
      pinnedAt: DateTime.tryParse(json['pinnedAt'] as String? ?? ''),
      lastMessage: json['lastMessage'] as String? ?? '',
      lastMessageAt: DateTime.tryParse(json['lastMessageAt'] as String? ?? ''),
      lastMessageSpoiler: json['lastMessageSpoiler'] as bool? ?? false,
      avatarImageUrl: json['avatarImageUrl'] as String? ?? '',
      notice: json['notice'] is Map
          ? ChatNoticeDto.fromJson(
              (json['notice'] as Map).cast<String, dynamic>(),
            )
          : null,
      members: [
        for (final item in json['members'] as List<dynamic>? ?? const [])
          UserProfileDto.fromJson((item as Map).cast<String, dynamic>()),
      ],
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  final String code;
  final String title;
  final String type;
  final int participantCount;
  final bool pinned;
  final DateTime? pinnedAt;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final bool lastMessageSpoiler;
  final String avatarImageUrl;
  final ChatNoticeDto? notice;
  final List<UserProfileDto> members;
  final int unreadCount;
}

class UserProfileDto {
  const UserProfileDto({
    required this.id,
    required this.email,
    required this.name,
    required this.displayName,
    required this.nickname,
    required this.phoneNumber,
    required this.role,
    required this.companyName,
    required this.position,
    required this.department,
    required this.birthDate,
    required this.status,
    required this.avatarColor,
    required this.statusMessage,
    required this.avatarImageUrl,
    required this.profileBackgroundColor,
    required this.profileBackgroundImageUrl,
    required this.blocked,
  });

  factory UserProfileDto.fromJson(Map<String, dynamic> json) {
    final name =
        json['name'] as String? ?? json['displayName'] as String? ?? '';
    return UserProfileDto(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      name: name,
      displayName: json['displayName'] as String? ?? name,
      nickname: json['nickname'] as String? ?? '',
      phoneNumber: json['phoneNumber'] as String? ?? '',
      role: json['role'] as String? ?? 'USER',
      companyName: json['companyName'] as String? ?? 'ABBA-S',
      position: json['position'] as String? ?? '',
      department: json['department'] as String? ?? '미지정',
      birthDate: DateTime.tryParse(json['birthDate'] as String? ?? ''),
      status: json['status'] as String? ?? '온라인',
      avatarColor: json['avatarColor'] as String? ?? '#7AA06A',
      statusMessage: json['statusMessage'] as String? ?? '',
      avatarImageUrl: json['avatarImageUrl'] as String? ?? '',
      profileBackgroundColor:
          json['profileBackgroundColor'] as String? ?? '#7AA06A',
      profileBackgroundImageUrl:
          json['profileBackgroundImageUrl'] as String? ?? '',
      blocked: json['blocked'] as bool? ?? false,
    );
  }

  final String id;
  final String email;
  final String name;
  final String displayName;
  final String nickname;
  final String phoneNumber;
  final String role;
  final String companyName;
  final String position;
  final String department;
  final DateTime? birthDate;
  final String status;
  final String avatarColor;
  final String statusMessage;
  final String avatarImageUrl;
  final String profileBackgroundColor;
  final String profileBackgroundImageUrl;
  final bool blocked;
}

class ChatNoticeDto {
  const ChatNoticeDto({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.sentAt,
  });

  factory ChatNoticeDto.fromJson(Map<String, dynamic> json) {
    return ChatNoticeDto(
      messageId: json['messageId'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      senderName: json['senderName'] as String? ?? '',
      content: json['content'] as String? ?? '',
      sentAt: DateTime.tryParse(json['sentAt'] as String? ?? ''),
    );
  }

  final String messageId;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime? sentAt;
}

class ChatMessageDto {
  const ChatMessageDto({
    required this.id,
    required this.roomCode,
    required this.senderId,
    required this.senderName,
    required this.senderNickname,
    required this.senderAvatarColor,
    required this.senderAvatarImageUrl,
    required this.content,
    required this.sentAt,
    required this.unreadCount,
    required this.systemMessage,
    required this.silent,
    required this.spoiler,
    required this.attachment,
  });

  factory ChatMessageDto.fromJson(Map<String, dynamic> json) {
    return ChatMessageDto(
      id: json['id'] as String? ?? '',
      roomCode: json['roomCode'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      senderName: json['senderName'] as String? ?? '',
      senderNickname: json['senderNickname'] as String? ?? '',
      senderAvatarColor: json['senderAvatarColor'] as String? ?? '',
      senderAvatarImageUrl: json['senderAvatarImageUrl'] as String? ?? '',
      content: json['content'] as String? ?? '',
      sentAt: DateTime.tryParse(json['sentAt'] as String? ?? ''),
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      systemMessage: json['systemMessage'] as bool? ?? false,
      silent: json['silent'] as bool? ?? false,
      spoiler: json['spoiler'] as bool? ?? false,
      attachment: json['attachment'] is Map
          ? ChatAttachmentDto.fromJson(
              (json['attachment'] as Map).cast<String, dynamic>(),
            )
          : null,
    );
  }

  final String id;
  final String roomCode;
  final String senderId;
  final String senderName;
  final String senderNickname;
  final String senderAvatarColor;
  final String senderAvatarImageUrl;
  final String content;
  final DateTime? sentAt;
  final int unreadCount;
  final bool systemMessage;
  final bool silent;
  final bool spoiler;
  final ChatAttachmentDto? attachment;
}

class ChatAttachmentDto {
  const ChatAttachmentDto({
    required this.id,
    required this.fileName,
    required this.contentType,
    required this.size,
    required this.downloadUrl,
    required this.groupId,
  });

  factory ChatAttachmentDto.fromJson(Map<String, dynamic> json) {
    return ChatAttachmentDto(
      id: json['id'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      contentType: json['contentType'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      downloadUrl: json['downloadUrl'] as String? ?? '',
      groupId: json['groupId'] as String? ?? '',
    );
  }

  final String id;
  final String fileName;
  final String contentType;
  final int size;
  final String downloadUrl;
  final String groupId;
}

class ChatRoomLeaveDto {
  const ChatRoomLeaveDto({
    required this.room,
    required this.message,
    required this.leaverEmail,
    required this.deleted,
  });

  factory ChatRoomLeaveDto.fromJson(Map<String, dynamic> json) {
    return ChatRoomLeaveDto(
      room: json['room'] is Map
          ? ChatRoomDto.fromJson((json['room'] as Map).cast<String, dynamic>())
          : const ChatRoomDto.empty(),
      message: json['message'] is Map
          ? ChatMessageDto.fromJson(
              (json['message'] as Map).cast<String, dynamic>(),
            )
          : null,
      leaverEmail: json['leaverEmail'] as String? ?? '',
      deleted: json['deleted'] as bool? ?? false,
    );
  }

  final ChatRoomDto room;
  final ChatMessageDto? message;
  final String leaverEmail;
  final bool deleted;
}

class ChatReadStateDto {
  const ChatReadStateDto({required this.roomCode, required this.messages});

  factory ChatReadStateDto.fromJson(Map<String, dynamic> json) {
    return ChatReadStateDto(
      roomCode: json['roomCode'] as String? ?? '',
      messages: [
        for (final item in json['messages'] as List<dynamic>? ?? const [])
          ChatMessageReadStateDto.fromJson(
            (item as Map).cast<String, dynamic>(),
          ),
      ],
    );
  }

  final String roomCode;
  final List<ChatMessageReadStateDto> messages;
}

class ChatMessageReadStateDto {
  const ChatMessageReadStateDto({
    required this.messageId,
    required this.unreadCount,
  });

  factory ChatMessageReadStateDto.fromJson(Map<String, dynamic> json) {
    return ChatMessageReadStateDto(
      messageId: json['messageId'] as String? ?? '',
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  final String messageId;
  final int unreadCount;
}

String formatChatClockTime(DateTime? dateTime) {
  if (dateTime == null) {
    return '';
  }

  final local = dateTime.toLocal();
  final period = local.hour < 12 ? '오전' : '오후';
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  return '$period $hour:${local.minute.toString().padLeft(2, '0')}';
}

String formatChatDateLabel(DateTime? dateTime) {
  if (dateTime == null) {
    return '';
  }

  const weekdays = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
  final local = dateTime.toLocal();
  return '${local.year}년 ${local.month}월 ${local.day}일 ${weekdays[local.weekday - 1]}';
}

String formatChatTime(DateTime? dateTime) {
  if (dateTime == null) {
    return '';
  }

  final local = dateTime.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return formatChatClockTime(local);
  }

  return '${local.month}/${local.day}';
}
