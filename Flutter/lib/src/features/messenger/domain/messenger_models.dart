import 'package:flutter/material.dart';

enum MessengerTab { friends, chats, avaAi, more }

class PersonProfile {
  const PersonProfile({
    required this.name,
    required this.color,
    this.id,
    this.nickname,
    this.phoneNumber,
    this.email,
    this.companyName,
    this.position,
    this.role,
    this.department,
    this.birthDate,
    this.imageUrl,
    this.status,
    this.statusMessage,
    this.profileBackgroundColor,
    this.profileBackgroundImageUrl,
    this.blocked = false,
  });

  final String? id;
  final String name;
  final String? nickname;
  final String? phoneNumber;
  final Color color;
  final String? email;
  final String? companyName;
  final String? position;
  final String? role;
  final String? department;
  final DateTime? birthDate;
  final String? imageUrl;
  final String? status;
  final String? statusMessage;
  final Color? profileBackgroundColor;
  final String? profileBackgroundImageUrl;
  final bool blocked;

  String get identityKey => id ?? email ?? name;
}

class UserGroup {
  const UserGroup({required this.title, required this.users});

  final String title;
  final List<PersonProfile> users;
}

class ChatFolder {
  const ChatFolder({
    required this.id,
    required this.name,
    required this.icon,
    this.roomIds = const [],
    this.isFavorite = false,
  });

  final String id;
  final String name;
  final String icon;
  final List<String> roomIds;
  final bool isFavorite;

  ChatFolder copyWith({
    String? id,
    String? name,
    String? icon,
    List<String>? roomIds,
    bool? isFavorite,
  }) {
    return ChatFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      roomIds: roomIds ?? this.roomIds,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.title,
    required this.preview,
    required this.time,
    required this.members,
    this.avatarImageUrl,
    this.previewIsSpoiler = false,
    this.lastActivityAt,
    this.participantCount,
    this.unreadCount = 0,
    this.isPinned = false,
    this.pinnedAt,
    this.isDraft = false,
    this.isMuted = false,
    this.notice,
  });

  final String id;
  final String title;
  final String preview;
  final String time;
  final List<PersonProfile> members;
  final String? avatarImageUrl;
  final bool previewIsSpoiler;
  final DateTime? lastActivityAt;
  final int? participantCount;
  final int unreadCount;
  final bool isPinned;
  final DateTime? pinnedAt;
  final bool isDraft;
  final bool isMuted;
  final ChatNotice? notice;

  int get displayParticipantCount => participantCount ?? members.length;
  bool get isSelfChat => id.startsWith('self-');
  bool get isDirectChat =>
      !isSelfChat &&
      (id.startsWith('direct-') ||
          displayParticipantCount == 2 ||
          (participantCount == null && members.length == 1));

  ChatRoom copyWith({
    String? id,
    String? title,
    String? preview,
    String? time,
    List<PersonProfile>? members,
    String? avatarImageUrl,
    bool? previewIsSpoiler,
    DateTime? lastActivityAt,
    int? participantCount,
    int? unreadCount,
    bool? isPinned,
    DateTime? pinnedAt,
    bool clearPinnedAt = false,
    bool? isDraft,
    bool? isMuted,
    ChatNotice? notice,
  }) {
    return ChatRoom(
      id: id ?? this.id,
      title: title ?? this.title,
      preview: preview ?? this.preview,
      time: time ?? this.time,
      members: members ?? this.members,
      avatarImageUrl: avatarImageUrl ?? this.avatarImageUrl,
      previewIsSpoiler: previewIsSpoiler ?? this.previewIsSpoiler,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      participantCount: participantCount ?? this.participantCount,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
      pinnedAt: clearPinnedAt ? null : pinnedAt ?? this.pinnedAt,
      isDraft: isDraft ?? this.isDraft,
      isMuted: isMuted ?? this.isMuted,
      notice: notice ?? this.notice,
    );
  }
}

class ChatNotice {
  const ChatNotice({
    required this.senderName,
    required this.content,
    this.messageId,
    this.senderId,
    this.sentAt,
  });

  final String? messageId;
  final String? senderId;
  final String senderName;
  final String content;
  final DateTime? sentAt;
}

class ChatMessage {
  const ChatMessage({
    required this.sender,
    required this.text,
    required this.time,
    required this.isMine,
    this.id,
    this.senderId,
    this.sentAt,
    this.unreadCount = 0,
    this.isSystem = false,
    this.isSilent = false,
    this.isSpoiler = false,
    this.spoilerRevealed = false,
    this.attachment,
  });

  final PersonProfile sender;
  final String text;
  final String time;
  final bool isMine;
  final String? id;
  final String? senderId;
  final DateTime? sentAt;
  final int unreadCount;
  final bool isSystem;
  final bool isSilent;
  final bool isSpoiler;
  final bool spoilerRevealed;
  final ChatAttachment? attachment;

  ChatMessage copyWith({
    int? unreadCount,
    bool? spoilerRevealed,
    ChatAttachment? attachment,
  }) {
    return ChatMessage(
      sender: sender,
      text: text,
      time: time,
      isMine: isMine,
      id: id,
      senderId: senderId,
      sentAt: sentAt,
      unreadCount: unreadCount ?? this.unreadCount,
      isSystem: isSystem,
      isSilent: isSilent,
      isSpoiler: isSpoiler,
      spoilerRevealed: spoilerRevealed ?? this.spoilerRevealed,
      attachment: attachment ?? this.attachment,
    );
  }
}

class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.fileName,
    required this.contentType,
    required this.size,
    required this.downloadUrl,
    this.groupId = '',
    this.localPath,
    this.cachedAt,
    this.transferBytes = 0,
    this.transferTotalBytes = 0,
    this.transferInProgress = false,
    this.transferFailed = false,
    this.transferUpload = false,
  });

  final String id;
  final String fileName;
  final String contentType;
  final int size;
  final String downloadUrl;
  final String groupId;
  final String? localPath;
  final DateTime? cachedAt;
  final int transferBytes;
  final int transferTotalBytes;
  final bool transferInProgress;
  final bool transferFailed;
  final bool transferUpload;

  bool get isImage {
    final content = contentType.toLowerCase();
    if (content.startsWith('image/')) {
      return true;
    }
    final lowerName = fileName.toLowerCase();
    return lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.png') ||
        lowerName.endsWith('.gif') ||
        lowerName.endsWith('.bmp') ||
        lowerName.endsWith('.webp') ||
        lowerName.endsWith('.heic') ||
        lowerName.endsWith('.heif') ||
        lowerName.endsWith('.tif') ||
        lowerName.endsWith('.tiff');
  }

  bool get isVideo {
    final content = contentType.toLowerCase();
    if (content.startsWith('video/')) {
      return true;
    }
    final lowerName = fileName.toLowerCase();
    return lowerName.endsWith('.mp4') ||
        lowerName.endsWith('.m4v') ||
        lowerName.endsWith('.mov') ||
        lowerName.endsWith('.avi') ||
        lowerName.endsWith('.mkv') ||
        lowerName.endsWith('.webm') ||
        lowerName.endsWith('.wmv') ||
        lowerName.endsWith('.mpg') ||
        lowerName.endsWith('.mpeg') ||
        lowerName.endsWith('.3gp') ||
        lowerName.endsWith('.3gpp');
  }

  bool get hasFreshLocalFile {
    final path = localPath;
    final cached = cachedAt;
    if (path == null || path.isEmpty || cached == null) {
      return false;
    }
    return DateTime.now().difference(cached) < const Duration(hours: 1);
  }

  ChatAttachment copyWith({
    String? localPath,
    DateTime? cachedAt,
    int? transferBytes,
    int? transferTotalBytes,
    bool? transferInProgress,
    bool? transferFailed,
    bool? transferUpload,
    bool clearTransfer = false,
  }) {
    return ChatAttachment(
      id: id,
      fileName: fileName,
      contentType: contentType,
      size: size,
      downloadUrl: downloadUrl,
      groupId: groupId,
      localPath: localPath ?? this.localPath,
      cachedAt: cachedAt ?? this.cachedAt,
      transferBytes: clearTransfer ? 0 : transferBytes ?? this.transferBytes,
      transferTotalBytes: clearTransfer
          ? 0
          : transferTotalBytes ?? this.transferTotalBytes,
      transferInProgress: clearTransfer
          ? false
          : transferInProgress ?? this.transferInProgress,
      transferFailed: clearTransfer
          ? false
          : transferFailed ?? this.transferFailed,
      transferUpload: clearTransfer
          ? false
          : transferUpload ?? this.transferUpload,
    );
  }
}
