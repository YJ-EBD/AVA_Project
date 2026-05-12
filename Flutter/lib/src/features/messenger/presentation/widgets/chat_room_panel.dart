import 'dart:async';
import 'dart:convert' show base64, utf8;
import 'dart:io' show Directory, File, Platform, Process;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../config/app_config.dart';
import '../../../../platform/window_control.dart';
import '../../../../shared/ava_toast.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../auth/data/auth_api.dart';
import '../../data/chat_api.dart';
import '../../data/chat_realtime_client.dart';
import '../../data/mock_messenger_data.dart';
import '../../domain/messenger_models.dart';
import '../messenger_page.dart';
import 'profile_avatar.dart';

const _chatBackground = Color(0xFFBFD3E3);
const _chatIconColor = Color(0xFF263238);
const _noticeBlue = Color(0xFF2387F2);

enum _SendMode { normal, quiet, spoiler }

class _SendOptions {
  const _SendOptions({this.mode = _SendMode.normal});

  final _SendMode mode;
  bool get silent => mode == _SendMode.quiet;
  bool get spoiler => mode == _SendMode.spoiler;
}

Map<String, Object?> _nativeMenuItem(
  String value,
  String label, {
  String? icon,
}) {
  final item = <String, Object?>{'value': value, 'label': label};
  if (icon != null) {
    item['icon'] = icon;
  }
  return item;
}

Map<String, Object?> _nativeMenuSeparator() => {'separator': true};

class _TypingParticipant {
  const _TypingParticipant({
    required this.displayName,
    required this.firstSeenAt,
  });

  final String displayName;
  final DateTime firstSeenAt;
}

class ChatRoomPanel extends ConsumerStatefulWidget {
  const ChatRoomPanel({required this.room, required this.onClose, super.key});

  final ChatRoom room;
  final VoidCallback onClose;

  @override
  ConsumerState<ChatRoomPanel> createState() => _ChatRoomPanelState();
}

class _ChatRoomPanelState extends ConsumerState<ChatRoomPanel> {
  late ChatRoom _room;
  late List<ChatMessage> _messages;
  ChatMessage? _noticeMessage;
  final Set<String> _messageIds = {};
  StreamSubscription<ChatMessageDto>? _realtimeSubscription;
  StreamSubscription<ChatReadStateDto>? _readStateSubscription;
  StreamSubscription<ChatTypingEventDto>? _typingSubscription;
  ChatRealtimeClient? _realtimeClient;
  final Map<String, _TypingParticipant> _typingParticipants = {};
  final Map<String, Timer> _typingExpiryTimers = {};
  bool _isLoadingMessages = false;
  bool _isFileDragActive = false;
  bool _isFileDropUploading = false;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _noticeMessage = _noticeFromRoom(_room);
    _messages = _initialMessagesFor(_room);
    _rememberMessageIds(_messages);
    WindowControl.setFileDropHandler(
      onDragState: _handleNativeFileDragState,
      onDrop: _handleNativeFileDrop,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRemoteMessages();
    });
  }

  @override
  void didUpdateWidget(covariant ChatRoomPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id == widget.room.id) {
      _room = widget.room;
      _noticeMessage = _noticeFromRoom(_room);
      return;
    }
    _stopRealtime();
    _clearTypingParticipants();
    _room = widget.room;
    _noticeMessage = _noticeFromRoom(_room);
    _messages = _initialMessagesFor(_room);
    _messageIds
      ..clear()
      ..addAll(_messages.map(_messageKey));
    _loadRemoteMessages();
  }

  List<ChatMessage> _initialMessagesFor(ChatRoom room) {
    final session = ref.read(authControllerProvider).value?.session;
    if (session != null && session.accessToken.isNotEmpty && !room.isDraft) {
      return const [];
    }
    return messagesFor(room);
  }

  @override
  void dispose() {
    _stopRealtime();
    _clearTypingParticipants();
    WindowControl.setFileDropHandler();
    unawaited(WindowControl.setMessengerOpacity(1));
    super.dispose();
  }

  Future<void> _loadRemoteMessages() async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      return;
    }
    if (_room.isDraft) {
      return;
    }

    setState(() {
      _isLoadingMessages = true;
    });

    try {
      final messages = await ref
          .read(chatApiProvider)
          .messages(accessToken: session.accessToken, roomCode: _room.id);
      if (!mounted) {
        return;
      }

      final mapped = [
        for (final message in messages)
          _messageFromDto(message, currentUserId: session.user.id),
      ];
      setState(() {
        _messages = mapped;
        _messageIds
          ..clear()
          ..addAll(mapped.map(_messageKey));
        _isLoadingMessages = false;
      });
      _startRealtime(session.accessToken, session.user.id);
      await _markRoomRead(session.accessToken);
    } on Object {
      if (mounted) {
        setState(() {
          _isLoadingMessages = false;
        });
      }
    }
  }

  Future<void> _sendMessage(
    String content, [
    _SendOptions options = const _SendOptions(),
  ]) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      final sentAt = DateTime.now();
      _appendLocalMessage(
        trimmed,
        sentAt,
        silent: options.silent,
        spoiler: options.spoiler,
      );
      ref
          .read(chatRoomsProvider.notifier)
          .messagePosted(
            _room.id,
            trimmed,
            sentAt,
            fallbackRoom: _room,
            spoiler: options.spoiler,
          );
      return;
    }

    final canSendRemote = await _resolveDraftRoom(
      accessToken: session.accessToken,
    );
    if (!canSendRemote) {
      final sentAt = DateTime.now();
      _appendLocalMessage(
        trimmed,
        sentAt,
        silent: options.silent,
        spoiler: options.spoiler,
      );
      ref
          .read(chatRoomsProvider.notifier)
          .messagePosted(
            _room.id,
            trimmed,
            sentAt,
            fallbackRoom: _room,
            spoiler: options.spoiler,
          );
      return;
    }

    final sentOverRealtime =
        _realtimeClient?.send(
          trimmed,
          silent: options.silent,
          spoiler: options.spoiler,
        ) ??
        false;
    DateTime? sentAt;
    if (!sentOverRealtime) {
      final message = await ref
          .read(chatApiProvider)
          .send(
            accessToken: session.accessToken,
            roomCode: _room.id,
            content: trimmed,
            silent: options.silent,
            spoiler: options.spoiler,
          );
      if (!mounted) {
        return;
      }
      sentAt = message.sentAt;
      _appendMessage(_messageFromDto(message, currentUserId: session.user.id));
    }

    ref
        .read(chatRoomsProvider.notifier)
        .messagePosted(
          _room.id,
          trimmed,
          sentAt ?? DateTime.now(),
          fallbackRoom: _room,
          spoiler: options.spoiler,
        );
  }

  Future<bool> _resolveDraftRoom({required String accessToken}) async {
    if (!_room.isDraft) {
      return true;
    }

    try {
      final targetEmail = _room.members.isEmpty
          ? null
          : _room.members.first.email;
      final targetUserId = _room.members.isEmpty
          ? null
          : _room.members.first.id;
      final chatApi = ref.read(chatApiProvider);
      final remoteRoom = _room.isSelfChat
          ? await chatApi.startSelfRoom(accessToken: accessToken)
          : await chatApi.startDirectRoom(
              accessToken: accessToken,
              targetName: _room.title,
              targetUserId: targetUserId,
              targetEmail: targetEmail,
            );
      if (!mounted || remoteRoom.code.isEmpty) {
        return false;
      }

      final resolvedRoom = ref
          .read(chatRoomsProvider.notifier)
          .roomFromRemoteRoom(remoteRoom, members: _room.members);
      setState(() {
        _room = resolvedRoom;
        _noticeMessage = _noticeFromRoom(resolvedRoom);
      });
      await _loadRemoteMessages();
      return true;
    } on Object {
      return false;
    }
  }

  void _startRealtime(String accessToken, String currentUserId) {
    _stopRealtime();
    final client = ChatRealtimeClient(
      websocketUrl: ref.read(appConfigProvider).websocketUrl,
      accessToken: accessToken,
      roomCode: _room.id,
    );
    _realtimeClient = client;
    _realtimeSubscription = client.messages.listen((message) {
      if (!mounted || message.roomCode != _room.id) {
        return;
      }
      _appendMessage(_messageFromDto(message, currentUserId: currentUserId));
      if (message.senderId != currentUserId) {
        _markRoomRead(accessToken);
      }
      ref
          .read(chatRoomsProvider.notifier)
          .messagePosted(
            _room.id,
            message.content,
            message.sentAt,
            fallbackRoom: _room,
            spoiler: message.spoiler,
          );
    }, onError: (_) {});
    _readStateSubscription = client.readStates.listen((readState) {
      if (!mounted || readState.roomCode != _room.id) {
        return;
      }
      _applyReadState(readState);
    }, onError: (_) {});
    _typingSubscription = client.typingEvents.listen((event) {
      if (!mounted || event.roomCode != _room.id) {
        return;
      }
      _handleTypingEvent(event, currentUserId);
    }, onError: (_) {});
    client.connect();
  }

  void _stopRealtime() {
    _realtimeClient?.sendTyping(false);
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _readStateSubscription?.cancel();
    _readStateSubscription = null;
    _typingSubscription?.cancel();
    _typingSubscription = null;
    _realtimeClient?.dispose();
    _realtimeClient = null;
  }

  Future<void> _markRoomRead(String accessToken) async {
    if (_room.isDraft || accessToken.isEmpty) {
      return;
    }
    try {
      final readState = await ref
          .read(chatApiProvider)
          .markRead(accessToken: accessToken, roomCode: _room.id);
      if (!mounted || readState.roomCode != _room.id) {
        return;
      }
      _applyReadState(readState);
      ref.read(chatRoomsProvider.notifier).markRead(_room.id);
    } on Object {
      // Read receipts are best-effort; message delivery should not be blocked.
    }
  }

  void _applyReadState(ChatReadStateDto readState) {
    final unreadById = {
      for (final message in readState.messages)
        message.messageId: message.unreadCount,
    };
    if (unreadById.isEmpty) {
      return;
    }
    setState(() {
      _messages = [
        for (final message in _messages)
          if (message.id != null && unreadById.containsKey(message.id))
            message.copyWith(unreadCount: unreadById[message.id])
          else
            message,
      ];
    });
  }

  void _handleTypingEvent(ChatTypingEventDto event, String currentUserId) {
    if (event.userId.isEmpty || event.userId == currentUserId) {
      return;
    }

    _typingExpiryTimers[event.userId]?.cancel();
    if (!event.typing) {
      _typingExpiryTimers.remove(event.userId);
      setState(() {
        _typingParticipants.remove(event.userId);
      });
      return;
    }

    final existing = _typingParticipants[event.userId];
    setState(() {
      _typingParticipants[event.userId] = _TypingParticipant(
        displayName: event.displayName.isEmpty
            ? '\uC0AC\uC6A9\uC790'
            : event.displayName,
        firstSeenAt: existing?.firstSeenAt ?? DateTime.now(),
      );
    });
    _typingExpiryTimers[event.userId] = Timer(const Duration(seconds: 4), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _typingParticipants.remove(event.userId);
      });
      _typingExpiryTimers.remove(event.userId);
    });
  }

  void _sendTypingStatus(bool typing) {
    _realtimeClient?.sendTyping(typing);
  }

  void _clearTypingParticipants() {
    for (final timer in _typingExpiryTimers.values) {
      timer.cancel();
    }
    _typingExpiryTimers.clear();
    _typingParticipants.clear();
  }

  String? get _typingLabel {
    if (_typingParticipants.isEmpty) {
      return null;
    }
    if (_room.isDirectChat || _room.isSelfChat) {
      return '';
    }
    final participants = _typingParticipants.values.toList()
      ..sort((a, b) => a.firstSeenAt.compareTo(b.firstSeenAt));
    final firstName = participants.first.displayName;
    final extraCount = participants.length - 1;
    return extraCount > 0 ? '$firstName \uC678 $extraCount\uBA85' : firstName;
  }

  bool get _canSendMessages =>
      _room.isDraft || _room.isSelfChat || _room.displayParticipantCount > 1;

  void _appendMessage(ChatMessage message) {
    final key = _messageKey(message);
    if (!_messageIds.add(key)) {
      final attachment = message.attachment;
      if (attachment != null &&
          (attachment.hasFreshLocalFile || attachment.transferInProgress)) {
        setState(() {
          _messages = [
            for (final existing in _messages)
              if (_messageKey(existing) == key)
                existing.copyWith(attachment: attachment)
              else
                existing,
          ];
        });
      }
      return;
    }
    setState(() {
      _messages = [..._messages, message];
    });
  }

  void _replaceMessage(String oldKey, ChatMessage replacement) {
    final newKey = _messageKey(replacement);
    var inserted = false;
    final nextMessages = <ChatMessage>[];
    for (final existing in _messages) {
      final existingKey = _messageKey(existing);
      if (existingKey == oldKey || existingKey == newKey) {
        if (!inserted) {
          nextMessages.add(replacement);
          inserted = true;
        }
      } else {
        nextMessages.add(existing);
      }
    }
    if (!inserted) {
      nextMessages.add(replacement);
    }
    setState(() {
      _messages = nextMessages;
      _messageIds
        ..clear()
        ..addAll(nextMessages.map(_messageKey));
    });
  }

  void _updateMessageAttachment(String key, ChatAttachment attachment) {
    if (!_messageIds.contains(key)) {
      return;
    }
    setState(() {
      _messages = [
        for (final message in _messages)
          if (_messageKey(message) == key)
            message.copyWith(attachment: attachment)
          else
            message,
      ];
    });
  }

  void _appendLocalMessage(
    String text,
    DateTime sentAt, {
    bool silent = false,
    bool spoiler = false,
  }) {
    _appendMessage(
      ChatMessage(
        sender: _currentUserProfile,
        text: text,
        time: formatChatClockTime(sentAt),
        isMine: true,
        sentAt: sentAt,
        isSilent: silent,
        isSpoiler: spoiler,
      ),
    );
  }

  void _rememberMessageIds(List<ChatMessage> messages) {
    _messageIds
      ..clear()
      ..addAll(messages.map(_messageKey));
  }

  ChatMessage _messageFromDto(
    ChatMessageDto message, {
    required String currentUserId,
  }) {
    final isMine = message.senderId == currentUserId;
    return ChatMessage(
      id: message.id,
      senderId: message.senderId,
      sender: isMine ? _currentUserProfile : _senderProfile(message),
      text: message.content,
      time: formatChatClockTime(message.sentAt),
      isMine: isMine,
      sentAt: message.sentAt,
      unreadCount: message.unreadCount,
      isSystem: message.systemMessage,
      isSilent: message.silent,
      isSpoiler: message.spoiler,
      attachment: _attachmentFromDto(message.attachment),
    );
  }

  ChatAttachment? _attachmentFromDto(ChatAttachmentDto? attachment) {
    if (attachment == null || attachment.id.isEmpty) {
      return null;
    }
    return ChatAttachment(
      id: attachment.id,
      fileName: attachment.fileName,
      contentType: attachment.contentType,
      size: attachment.size,
      downloadUrl: attachment.downloadUrl,
      groupId: attachment.groupId,
    );
  }

  Future<void> _showFileTransferDialog() async {
    if (!_canSendMessages) {
      return;
    }
    final files = await _pickAttachmentFiles(context);
    if (!mounted || files.isEmpty) {
      return;
    }
    final shouldSend = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black.withValues(alpha: 0.24),
      builder: (_) => _FileTransferDialog(files: files),
    );
    if (shouldSend != true || !mounted) {
      return;
    }
    await _sendAttachments(files);
  }

  Future<void> _handleNativeFileDragState(bool active) async {
    if (!mounted || _isFileDragActive == active) {
      return;
    }
    setState(() => _isFileDragActive = active);
  }

  Future<void> _handleNativeFileDrop(List<String> paths) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isFileDragActive = false;
    });
    if (!_canSendMessages) {
      showAvaToast(
        context,
        '\uD604\uC7AC \uCC44\uD305\uBC29\uC5D0\uB294 \uD30C\uC77C\uC744 \uBCF4\uB0BC \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.',
      );
      return;
    }
    final files = await _selectedUploadFilesFromPaths(paths);
    if (!mounted) {
      return;
    }
    if (files.isEmpty) {
      showAvaToast(
        context,
        '\uC5C5\uB85C\uB4DC\uD560 \uD30C\uC77C\uC744 \uC77D\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.',
      );
      return;
    }
    setState(() => _isFileDropUploading = true);
    try {
      await _sendAttachments(files);
    } finally {
      if (mounted) {
        setState(() => _isFileDropUploading = false);
      }
    }
  }

  Future<void> _sendAttachments(List<_SelectedUploadFile> files) async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      showAvaToast(context, '파일 전송은 로그인 후 사용할 수 있습니다.');
      return;
    }
    final canSendRemote = await _resolveDraftRoom(
      accessToken: session.accessToken,
    );
    if (!canSendRemote) {
      if (mounted) {
        showAvaToast(context, '파일을 보낼 수 없습니다.');
      }
      return;
    }

    final attachmentGroupId =
        'attach-${_room.id}-${DateTime.now().microsecondsSinceEpoch}';
    for (final file in files) {
      final isVideo = _isVideoFileName(file.name);
      final sentAt = DateTime.now();
      final pendingMessageId =
          'pending-${_room.id}-${sentAt.microsecondsSinceEpoch}-${file.name.hashCode}';
      ChatAttachment? pendingAttachment;
      if (isVideo) {
        pendingAttachment = ChatAttachment(
          id: pendingMessageId,
          fileName: file.name,
          contentType: _guessContentType(file.name),
          size: file.size,
          downloadUrl: '',
          groupId: attachmentGroupId,
          localPath: file.path,
          cachedAt: sentAt,
          transferBytes: 0,
          transferTotalBytes: file.size,
          transferInProgress: true,
          transferUpload: true,
        );
        _appendMessage(
          ChatMessage(
            id: pendingMessageId,
            senderId: session.user.id,
            sender: _currentUserProfile,
            text: file.name,
            time: formatChatClockTime(sentAt),
            isMine: true,
            sentAt: sentAt,
            attachment: pendingAttachment,
          ),
        );
      }

      try {
        final message = await ref
            .read(chatApiProvider)
            .uploadAttachment(
              accessToken: session.accessToken,
              roomCode: _room.id,
              filePath: file.path,
              fileName: file.name,
              groupId: attachmentGroupId,
              onSendProgress: isVideo
                  ? (sent, total) {
                      if (!mounted || pendingAttachment == null) {
                        return;
                      }
                      final transferTotal = total > 0 ? total : file.size;
                      pendingAttachment = pendingAttachment!.copyWith(
                        transferBytes: sent.clamp(0, transferTotal).toInt(),
                        transferTotalBytes: transferTotal,
                        transferInProgress: true,
                        transferFailed: false,
                        transferUpload: true,
                      );
                      _updateMessageAttachment(
                        pendingMessageId,
                        pendingAttachment!,
                      );
                    }
                  : null,
            );
        if (!mounted) {
          return;
        }
        final mapped = _messageFromDto(message, currentUserId: session.user.id);
        final attachment = mapped.attachment;
        final cachedPath = attachment == null
            ? null
            : isVideo
            ? file.path
            : await _cacheUploadedFileToDownloads(file);
        if (!mounted) {
          return;
        }
        final completedMessage = attachment == null || cachedPath == null
            ? mapped
            : mapped.copyWith(
                attachment: attachment.copyWith(
                  localPath: cachedPath,
                  cachedAt: DateTime.now(),
                  clearTransfer: true,
                ),
              );
        if (isVideo) {
          _replaceMessage(pendingMessageId, completedMessage);
        } else {
          _appendMessage(completedMessage);
        }
        ref
            .read(chatRoomsProvider.notifier)
            .messagePosted(
              _room.id,
              file.name,
              message.sentAt ?? DateTime.now(),
              fallbackRoom: _room,
            );
      } on Object catch (error) {
        if (!mounted) {
          return;
        }
        if (isVideo && pendingAttachment != null) {
          _updateMessageAttachment(
            pendingMessageId,
            pendingAttachment!.copyWith(
              transferInProgress: false,
              transferFailed: true,
              transferUpload: true,
            ),
          );
        }
        showAvaToast(context, authErrorMessage(error));
      }
    }
  }

  Future<void> _openImageViewer(
    List<ChatMessage> messages,
    int initialIndex,
  ) async {
    final imageMessages = [
      for (final message in messages)
        if (_isImageMessage(message)) message,
    ];
    if (imageMessages.isEmpty) {
      return;
    }

    final session = ref.read(authControllerProvider).value?.session;
    final items = <_ImageViewerItem>[];
    for (final message in imageMessages) {
      final attachment = message.attachment;
      if (attachment == null) {
        continue;
      }
      String? path;
      try {
        path = await _imageAttachmentPathInDownloads(
          attachment,
          accessToken: session?.accessToken,
        );
      } on Object {
        path = null;
      }
      if (!mounted) {
        return;
      }
      if (path != null) {
        items.add(_ImageViewerItem(path: path, name: attachment.fileName));
      }
    }

    if (items.isEmpty) {
      if (mounted) {
        showAvaToast(context, '이미지를 열 수 없습니다.');
      }
      return;
    }

    final safeInitialIndex = initialIndex.clamp(0, items.length - 1);
    final source = imageMessages[safeInitialIndex];
    final opened = await _showAvaImageViewer(
      items: items,
      initialIndex: safeInitialIndex,
      senderName: source.sender.name,
      sentAt: source.sentAt ?? DateTime.now(),
    );
    if (!opened && mounted) {
      showAvaToast(context, '이미지를 열 수 없습니다.');
    }
  }

  Future<String?> _imageAttachmentPathInDownloads(
    ChatAttachment attachment, {
    required String? accessToken,
  }) async {
    final localPath = attachment.localPath;
    final cachedAt = attachment.cachedAt;
    if (localPath != null &&
        localPath.isNotEmpty &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(hours: 1)) {
      final source = File(localPath);
      if (await source.exists()) {
        final downloads = await _downloadsDirectory();
        if (_isPathInDirectory(localPath, downloads)) {
          return localPath;
        }
        final targetPath = await _nextDownloadPath(attachment.fileName);
        await source.copy(targetPath);
        return targetPath;
      }
    }

    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }
    final targetPath = await _nextDownloadPath(attachment.fileName);
    await ref
        .read(chatApiProvider)
        .downloadAttachment(
          accessToken: accessToken,
          downloadUrl: attachment.downloadUrl,
          savePath: targetPath,
        );
    return targetPath;
  }

  ChatMessage? _noticeFromRoom(ChatRoom room) {
    final notice = room.notice;
    if (notice == null || notice.content.isEmpty) {
      return null;
    }
    return ChatMessage(
      id: notice.messageId,
      senderId: notice.senderId,
      sender: _senderProfileForNotice(notice),
      text: notice.content,
      time: formatChatClockTime(notice.sentAt),
      isMine:
          notice.senderId ==
              ref.read(authControllerProvider).value?.session?.user.id ||
          notice.senderName == _currentUserProfile.name,
      sentAt: notice.sentAt,
    );
  }

  ChatNotice _noticeFromMessage(ChatMessage message) {
    return ChatNotice(
      messageId: message.id,
      senderId: message.senderId,
      senderName: message.sender.name,
      content: message.text,
      sentAt: message.sentAt,
    );
  }

  PersonProfile _senderProfileForNotice(ChatNotice notice) {
    final current = _currentUserProfile;
    if ((notice.senderId != null && notice.senderId == current.id) ||
        notice.senderName == current.name) {
      return current;
    }
    for (final member in _room.members) {
      if ((notice.senderId != null && notice.senderId == member.id) ||
          member.name == notice.senderName) {
        return member;
      }
    }
    return PersonProfile(
      name: notice.senderName,
      color: _avatarColorFor(notice.senderId ?? notice.senderName),
    );
  }

  PersonProfile _senderProfile(ChatMessageDto message) {
    for (final member in _room.members) {
      if ((member.id != null && member.id == message.senderId) ||
          member.name == message.senderName) {
        return member;
      }
    }

    return PersonProfile(
      name: message.senderName.isEmpty ? _room.title : message.senderName,
      color: _avatarColorFor(message.senderId),
    );
  }

  Color _avatarColorFor(String senderId) {
    const colors = [
      Color(0xFF8FC7D5),
      Color(0xFFA6C6EE),
      Color(0xFFDDE8A5),
      Color(0xFF9FB2D9),
      Color(0xFF7DB3D7),
      Color(0xFFE2B28D),
      Color(0xFFB6A4E8),
      Color(0xFF92D5E2),
    ];
    final index = senderId.codeUnits.fold<int>(0, (sum, value) => sum + value);
    return colors[index % colors.length];
  }

  String _messageKey(ChatMessage message) {
    if (message.id != null && message.id!.isNotEmpty) {
      return message.id!;
    }
    return '${message.senderId ?? message.sender.name}-${message.sentAt?.toIso8601String() ?? message.time}-${message.text}';
  }

  PersonProfile get _currentUserProfile => ref.read(currentUserProfileProvider);

  Future<void> _showMessageContextMenu(
    ChatMessage message,
    Offset position,
  ) async {
    String? result;
    if (Platform.isWindows) {
      result = await WindowControl.showNativeMenu(
        items: [
          _nativeMenuItem('reply', '\uB2F5\uC7A5'),
          _nativeMenuItem('react', '\uACF5\uAC10'),
          _nativeMenuItem('share', '\uACF5\uC720'),
          _nativeMenuItem('me', '\uB098\uC5D0\uAC8C'),
          _nativeMenuSeparator(),
          _nativeMenuItem('notice', '\uACF5\uC9C0'),
          _nativeMenuItem('post', '\uAC8C\uC2DC\uAE00\uB85C \uC791\uC131'),
          _nativeMenuSeparator(),
          _nativeMenuItem('copy', '\uBCF5\uC0AC'),
          _nativeMenuItem('delete', '\uC0AD\uC81C    >'),
          _nativeMenuSeparator(),
          _nativeMenuItem('search', '#\uAC80\uC0C9'),
          _nativeMenuSeparator(),
          _nativeMenuItem('capture', '\uCEA1\uCC98'),
        ],
        x: position.dx + 4,
        y: position.dy,
      );
    } else {
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox;
      result = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(position.dx + 4, position.dy, 0, 0),
          Offset.zero & overlay.size,
        ),
        elevation: 6,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFFC8C8C8)),
          borderRadius: BorderRadius.circular(2),
        ),
        items: const [
          PopupMenuItem(
            value: 'reply',
            height: 28,
            padding: EdgeInsets.zero,
            child: _MessageMenuItem(label: '\uB2F5\uC7A5'),
          ),
          PopupMenuItem(
            value: 'react',
            height: 28,
            padding: EdgeInsets.zero,
            child: _MessageMenuItem(label: '\uACF5\uAC10'),
          ),
          PopupMenuItem(
            value: 'share',
            height: 28,
            padding: EdgeInsets.zero,
            child: _MessageMenuItem(label: '\uACF5\uC720'),
          ),
          PopupMenuItem(
            value: 'me',
            height: 28,
            padding: EdgeInsets.zero,
            child: _MessageMenuItem(label: '\uB098\uC5D0\uAC8C'),
          ),
          PopupMenuDivider(height: 8),
          PopupMenuItem(
            value: 'notice',
            height: 28,
            padding: EdgeInsets.zero,
            child: _MessageMenuItem(
              key: ValueKey('message-menu-notice'),
              label: '\uACF5\uC9C0',
            ),
          ),
          PopupMenuItem(
            value: 'post',
            height: 28,
            padding: EdgeInsets.zero,
            child: _MessageMenuItem(
              label: '\uAC8C\uC2DC\uAE00\uB85C \uC791\uC131',
            ),
          ),
          PopupMenuDivider(height: 8),
          PopupMenuItem(
            value: 'copy',
            height: 28,
            padding: EdgeInsets.zero,
            child: _MessageMenuItem(label: '\uBCF5\uC0AC'),
          ),
          PopupMenuItem(
            value: 'delete',
            height: 28,
            padding: EdgeInsets.zero,
            child: _MessageMenuItem(
              label: '\uC0AD\uC81C',
              trailing: Icons.chevron_right,
            ),
          ),
          PopupMenuDivider(height: 8),
          PopupMenuItem(
            value: 'search',
            height: 28,
            padding: EdgeInsets.zero,
            child: _MessageMenuItem(label: '#\uAC80\uC0C9'),
          ),
          PopupMenuDivider(height: 8),
          PopupMenuItem(
            value: 'capture',
            height: 28,
            padding: EdgeInsets.zero,
            child: _MessageMenuItem(label: '\uCEA1\uCC98'),
          ),
        ],
      );
    }

    if (!mounted || result != 'notice') {
      return;
    }

    setState(() {
      _noticeMessage = message;
    });
    final notice = _noticeFromMessage(message);
    ref.read(chatRoomsProvider.notifier).noticeSet(_room.id, notice);
    await _persistNotice(message);
  }

  Future<void> _persistNotice(ChatMessage message) async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty || _room.isDraft) {
      return;
    }

    try {
      final remoteRoom = await ref
          .read(chatApiProvider)
          .setNotice(
            accessToken: session.accessToken,
            roomCode: _room.id,
            messageId: message.id,
            senderId: message.senderId,
            senderName: message.sender.name,
            content: message.text,
            sentAt: message.sentAt,
          );
      if (!mounted) {
        return;
      }

      final updatedRoom = ref
          .read(chatRoomsProvider.notifier)
          .roomFromRemoteRoom(remoteRoom, members: _room.members);
      setState(() {
        _room = updatedRoom;
        _noticeMessage = _noticeFromRoom(updatedRoom) ?? message;
      });
      final notice = updatedRoom.notice;
      if (notice != null) {
        ref.read(chatRoomsProvider.notifier).noticeSet(updatedRoom.id, notice);
      }
    } on Object {
      // Keep the local notice visible; the next successful save will persist it.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            color: _chatBackground,
            border: Border(left: BorderSide(color: Color(0xFFD1D1D1))),
          ),
          child: Column(
            children: [
              _ChatHeader(room: _room, onClose: widget.onClose),
              if (_noticeMessage != null)
                _ChatNoticeCard(message: _noticeMessage!),
              Expanded(
                child: Stack(
                  children: [
                    _ChatMessagesView(
                      messages: _messages,
                      typingLabel: _typingLabel,
                      onMessageContextMenu: _showMessageContextMenu,
                      onOpenImages: _openImageViewer,
                    ),
                    if (_isLoadingMessages)
                      const Positioned(
                        top: 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _MessageComposer(
                onSend: _sendMessage,
                onAttachFiles: _showFileTransferDialog,
                onTypingChanged: _sendTypingStatus,
                enabled: _canSendMessages,
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: _FileDropOverlay(
            visible: _isFileDragActive || _isFileDropUploading,
            uploading: _isFileDropUploading,
            enabled: _canSendMessages,
          ),
        ),
      ],
    );
  }
}

class _SelectedUploadFile {
  const _SelectedUploadFile({
    required this.path,
    required this.name,
    required this.size,
  });

  final String path;
  final String name;
  final int size;
}

class _FileDropOverlay extends StatefulWidget {
  const _FileDropOverlay({
    required this.visible,
    required this.uploading,
    required this.enabled,
  });

  final bool visible;
  final bool uploading;
  final bool enabled;

  @override
  State<_FileDropOverlay> createState() => _FileDropOverlayState();
}

class _FileDropOverlayState extends State<_FileDropOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.visible) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _FileDropOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.visible && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        reverseDuration: const Duration(milliseconds: 140),
        transitionBuilder: (child, animation) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
              child: child,
            ),
          );
        },
        child: widget.visible
            ? AnimatedBuilder(
                key: const ValueKey('file-drop-overlay'),
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _FileDropOverlayPainter(
                      progress: _controller.value,
                      enabled: widget.enabled,
                    ),
                    child: child,
                  );
                },
                child: _FileDropOverlayContent(
                  uploading: widget.uploading,
                  enabled: widget.enabled,
                ),
              )
            : const SizedBox.shrink(key: ValueKey('file-drop-empty')),
      ),
    );
  }
}

class _FileDropOverlayContent extends StatelessWidget {
  const _FileDropOverlayContent({
    required this.uploading,
    required this.enabled,
  });

  final bool uploading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final title = uploading
        ? '\uD30C\uC77C \uC5C5\uB85C\uB4DC \uC911'
        : enabled
        ? '\uC5EC\uAE30\uC5D0 \uB193\uC73C\uBA74 \uC804\uC1A1\uB429\uB2C8\uB2E4'
        : '\uC774 \uCC44\uD305\uBC29\uC5D0\uB294 \uBCF4\uB0BC \uC218 \uC5C6\uC2B5\uB2C8\uB2E4';
    final subtitle = uploading
        ? '\uC120\uD0DD\uD55C \uD30C\uC77C\uC744 \uCC44\uD305\uBC29\uC5D0 \uC62C\uB9AC\uACE0 \uC788\uC2B5\uB2C8\uB2E4'
        : '\uC774\uBBF8\uC9C0, \uB3D9\uC601\uC0C1, \uD30C\uC77C \uC5EC\uB7EC \uAC1C\uB97C \uD55C \uBC88\uC5D0 \uC804\uC1A1';

    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.18)),
      child: Center(
        child: Container(
          width: 330,
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled ? const Color(0xFFFFDF00) : Colors.white,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: enabled
                        ? const Color(0xFFFFDF00)
                        : const Color(0xFFE0E0E0),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: uploading
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.6,
                              color: Colors.black,
                            ),
                          )
                        : Icon(
                            enabled
                                ? Icons.upload_file_rounded
                                : Icons.block_rounded,
                            color: Colors.black,
                            size: 25,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF4F5C64),
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileDropOverlayPainter extends CustomPainter {
  const _FileDropOverlayPainter({
    required this.progress,
    required this.enabled,
  });

  final double progress;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 24 || size.height <= 24) {
      return;
    }
    final rect = Offset.zero & size;
    final inset = 18 + progress * 3;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(inset),
      const Radius.circular(12),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = (enabled ? const Color(0xFFFFDF00) : Colors.white).withValues(
        alpha: 0.70 + 0.20 * progress,
      );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = math.min(distance + 18, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 30;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FileDropOverlayPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.enabled != enabled;
  }
}

Future<List<_SelectedUploadFile>> _pickAttachmentFiles(
  BuildContext context,
) async {
  if (!Platform.isWindows) {
    showAvaToast(context, '현재 파일 선택은 Windows에서 지원됩니다.');
    return const [];
  }

  const script = r'''
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = "파일 선택"
$dialog.Title = "Select files"
$dialog.Multiselect = $true
$dialog.Filter = "All files|*.*"
$dialog.Filter = "All files (*.*)|*.*"
$dialog.RestoreDirectory = $true
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  foreach ($fileName in $dialog.FileNames) {
    [Console]::WriteLine([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($fileName)))
  }
}
''';

  try {
    final result = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-Command', script],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      return const [];
    }
    final encodedPaths = result.stdout
        .toString()
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final files = <_SelectedUploadFile>[];
    for (final encodedPath in encodedPaths) {
      String path;
      try {
        path = utf8.decode(base64.decode(encodedPath));
      } on Object {
        path = encodedPath;
      }
      final file = File(path);
      if (!await file.exists()) {
        continue;
      }
      files.add(
        _SelectedUploadFile(
          path: path,
          name: path.split(RegExp(r'[\\/]')).last,
          size: await file.length(),
        ),
      );
    }
    if (files.isEmpty && encodedPaths.isNotEmpty && context.mounted) {
      showAvaToast(
        context,
        '\uC120\uD0DD\uD55C \uD30C\uC77C\uC744 \uC77D\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.',
      );
    }
    return files;
  } on Object catch (error) {
    if (context.mounted) {
      showAvaToast(context, authErrorMessage(error));
    }
    return const [];
  }
}

Future<List<_SelectedUploadFile>> _selectedUploadFilesFromPaths(
  List<String> paths,
) async {
  final files = <_SelectedUploadFile>[];
  final seen = <String>{};
  for (final rawPath in paths) {
    final path = rawPath.trim();
    if (path.isEmpty) {
      continue;
    }
    final file = File(path);
    if (!await file.exists()) {
      continue;
    }
    final absolutePath = file.absolute.path;
    final key = Platform.isWindows ? absolutePath.toLowerCase() : absolutePath;
    if (!seen.add(key)) {
      continue;
    }
    files.add(
      _SelectedUploadFile(
        path: absolutePath,
        name: absolutePath.split(RegExp(r'[\\/]')).last,
        size: await file.length(),
      ),
    );
  }
  return files;
}

bool _isVideoFileName(String fileName) {
  return ChatAttachment(
    id: 'probe',
    fileName: fileName,
    contentType: _guessContentType(fileName),
    size: 0,
    downloadUrl: '',
  ).isVideo;
}

String _guessContentType(String fileName) {
  final lowerName = fileName.toLowerCase();
  if (lowerName.endsWith('.mp4') || lowerName.endsWith('.m4v')) {
    return 'video/mp4';
  }
  if (lowerName.endsWith('.mov')) {
    return 'video/quicktime';
  }
  if (lowerName.endsWith('.avi')) {
    return 'video/x-msvideo';
  }
  if (lowerName.endsWith('.mkv')) {
    return 'video/x-matroska';
  }
  if (lowerName.endsWith('.webm')) {
    return 'video/webm';
  }
  if (lowerName.endsWith('.wmv')) {
    return 'video/x-ms-wmv';
  }
  if (lowerName.endsWith('.mpg') || lowerName.endsWith('.mpeg')) {
    return 'video/mpeg';
  }
  if (lowerName.endsWith('.3gp') || lowerName.endsWith('.3gpp')) {
    return 'video/3gpp';
  }
  return 'application/octet-stream';
}

Future<String?> _pickVideoSavePath(
  BuildContext context,
  String fileName,
) async {
  if (!Platform.isWindows) {
    showAvaToast(context, '현재 동영상 저장은 Windows에서 지원됩니다.');
    return null;
  }

  final encodedFileName = base64.encode(
    utf8.encode(_sanitizeFileName(fileName)),
  );
  final script =
      '''
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
\$fileName = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("$encodedFileName"))
\$dialog = New-Object System.Windows.Forms.SaveFileDialog
\$dialog.Title = "동영상 저장"
\$dialog.FileName = \$fileName
\$dialog.Filter = "Video files (*.mp4;*.mov;*.avi;*.mkv;*.webm;*.wmv)|*.mp4;*.mov;*.avi;*.mkv;*.webm;*.wmv|All files (*.*)|*.*"
\$dialog.OverwritePrompt = \$true
\$dialog.RestoreDirectory = \$true
if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  [Console]::WriteLine([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(\$dialog.FileName)))
}
''';

  try {
    final result = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-Command', script],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      return null;
    }
    final encodedPath = result.stdout
        .toString()
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (encodedPath.isEmpty) {
      return null;
    }
    return utf8.decode(base64.decode(encodedPath));
  } on Object catch (error) {
    if (context.mounted) {
      showAvaToast(context, authErrorMessage(error));
    }
    return null;
  }
}

Future<String> _nextDownloadPath(String fileName) async {
  final directory = await _downloadsDirectory();
  final sanitized = _sanitizeFileName(fileName);
  final dotIndex = sanitized.lastIndexOf('.');
  final stem = dotIndex <= 0 ? sanitized : sanitized.substring(0, dotIndex);
  final extension = dotIndex <= 0 ? '' : sanitized.substring(dotIndex);
  var candidate = '${directory.path}${Platform.pathSeparator}$sanitized';
  var index = 1;
  while (await File(candidate).exists()) {
    candidate =
        '${directory.path}${Platform.pathSeparator}$stem ($index)$extension';
    index++;
  }
  return candidate;
}

Future<String?> _cacheUploadedFileToDownloads(_SelectedUploadFile file) async {
  try {
    final source = File(file.path);
    if (!await source.exists()) {
      return null;
    }
    final downloads = await _downloadsDirectory();
    if (_isPathInDirectory(source.path, downloads)) {
      return source.path;
    }
    final targetPath = await _nextDownloadPath(file.name);
    await source.copy(targetPath);
    return targetPath;
  } on Object {
    return null;
  }
}

Future<Directory> _downloadsDirectory() async {
  if (Platform.isWindows) {
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) {
      final directory = Directory(
        '$userProfile${Platform.pathSeparator}Downloads',
      );
      await directory.create(recursive: true);
      return directory;
    }
  }
  if (Platform.isAndroid) {
    final directory = Directory('/storage/emulated/0/Download');
    await directory.create(recursive: true);
    return directory;
  }
  final directory = Directory.current;
  return directory;
}

bool _isPathInDirectory(String path, Directory directory) {
  final filePath = File(path).absolute.path;
  final directoryPath = directory.absolute.path;
  final separator = Platform.pathSeparator;
  if (Platform.isWindows) {
    final normalizedFile = filePath.toLowerCase();
    final normalizedDirectory = directoryPath.toLowerCase();
    return normalizedFile == normalizedDirectory ||
        normalizedFile.startsWith('$normalizedDirectory$separator');
  }
  return filePath == directoryPath ||
      filePath.startsWith('$directoryPath$separator');
}

String _absoluteAttachmentUrl(String apiBaseUrl, String downloadUrl) {
  if (downloadUrl.startsWith('http://') || downloadUrl.startsWith('https://')) {
    return downloadUrl;
  }
  final base = apiBaseUrl.endsWith('/')
      ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
      : apiBaseUrl;
  final path = downloadUrl.startsWith('/') ? downloadUrl : '/$downloadUrl';
  return '$base$path';
}

class _ImageViewerItem {
  const _ImageViewerItem({required this.path, required this.name});

  final String path;
  final String name;

  Map<String, Object?> toJson() => {'path': path, 'name': name};
}

String _imageViewerDateLabel(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

Future<bool> _showAvaImageViewer({
  required List<_ImageViewerItem> items,
  required int initialIndex,
  required String senderName,
  required DateTime sentAt,
}) async {
  if (!Platform.isWindows || items.isEmpty) {
    return false;
  }
  try {
    await WindowControl.showImageViewerPopup(
      images: [for (final item in items) item.toJson()],
      initialIndex: initialIndex,
      sender: senderName,
      date: _imageViewerDateLabel(sentAt),
    );
    return true;
  } on Object {
    return false;
  }
}

class _VideoThumbnailResult {
  const _VideoThumbnailResult({required this.duration});

  final Duration duration;
}

Future<_VideoThumbnailResult?> _createVideoThumbnail({
  required String videoPath,
  required String thumbnailPath,
}) async {
  if (!Platform.isWindows) {
    return null;
  }
  File? scriptFile;
  try {
    scriptFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'ava_video_thumb_${DateTime.now().microsecondsSinceEpoch}.ps1',
    );
    await scriptFile.writeAsString(_avaVideoThumbnailScript, encoding: utf8);
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-STA',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptFile.path,
        base64.encode(utf8.encode(videoPath)),
        base64.encode(utf8.encode(thumbnailPath)),
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      return null;
    }
    final durationMs =
        int.tryParse(
          result.stdout
              .toString()
              .split(RegExp(r'\r?\n'))
              .map((line) => line.trim())
              .firstWhere((line) => line.isNotEmpty, orElse: () => '0'),
        ) ??
        0;
    return _VideoThumbnailResult(duration: Duration(milliseconds: durationMs));
  } on Object {
    return null;
  } finally {
    if (scriptFile != null) {
      try {
        await scriptFile.delete();
      } on Object {
        // Ignore temporary script cleanup failures.
      }
    }
  }
}

Future<bool> _showAvaVideoViewer({
  required String path,
  required String fileName,
  required String senderName,
  required DateTime sentAt,
}) async {
  if (!Platform.isWindows || path.isEmpty || !await File(path).exists()) {
    return false;
  }
  try {
    await WindowControl.showVideoViewerPopup(
      path: path,
      name: fileName,
      sender: senderName,
      date: _imageViewerDateLabel(sentAt),
    );
    return true;
  } on Object {
    return false;
  }
}

String _formatVideoDuration(Duration? duration) {
  if (duration == null || duration <= Duration.zero) {
    return '0:00';
  }
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _formatTransferSize(int bytes, int totalBytes) {
  final safeTotal = math.max(0, totalBytes);
  final safeBytes = bytes.clamp(0, safeTotal == 0 ? bytes : safeTotal).toInt();
  return '${_formatFileSize(safeBytes)}/${_formatFileSize(safeTotal)}';
}

const _avaVideoThumbnailScript = r'''
param(
  [string]$Path64,
  [string]$Thumb64
)

function Decode-Utf8([string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) { return "" }
  return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($value))
}

$videoPath = Decode-Utf8 $Path64
$thumbPath = Decode-Utf8 $Thumb64
if (!(Test-Path -LiteralPath $videoPath)) {
  exit 1
}

Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$durationMs = 0
$rendered = $false
try {
  $script:mediaOpened = $false
  $script:mediaFailed = $false
  $player = New-Object System.Windows.Media.MediaPlayer
  $player.Volume = 0
  $player.Add_MediaOpened({ $script:mediaOpened = $true })
  $player.Add_MediaFailed({ $script:mediaFailed = $true })
  $player.Open([System.Uri]::new((Get-Item -LiteralPath $videoPath).FullName))

  $deadline = [DateTime]::Now.AddSeconds(8)
  while (!$script:mediaOpened -and !$script:mediaFailed -and [DateTime]::Now -lt $deadline) {
    $frame = New-Object Windows.Threading.DispatcherFrame
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(80)
    $timer.Add_Tick({
      $timer.Stop()
      $frame.Continue = $false
    })
    $timer.Start()
    [Windows.Threading.Dispatcher]::PushFrame($frame)
  }

  if ($script:mediaOpened -and $player.NaturalDuration.HasTimeSpan) {
    $duration = $player.NaturalDuration.TimeSpan
    $durationMs = [int64]$duration.TotalMilliseconds
    $seekMs = [Math]::Min([Math]::Max(250, [int]($duration.TotalMilliseconds * 0.08)), 1500)
    $player.Position = [TimeSpan]::FromMilliseconds($seekMs)
    $frame = New-Object Windows.Threading.DispatcherFrame
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(420)
    $timer.Add_Tick({
      $timer.Stop()
      $frame.Continue = $false
    })
    $timer.Start()
    [Windows.Threading.Dispatcher]::PushFrame($frame)

    $visual = New-Object System.Windows.Media.DrawingVisual
    $context = $visual.RenderOpen()
    $context.DrawRectangle(
      (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(24, 32, 36))),
      $null,
      (New-Object Windows.Rect 0, 0, 420, 280)
    )
    $videoWidth = [Math]::Max(1, $player.NaturalVideoWidth)
    $videoHeight = [Math]::Max(1, $player.NaturalVideoHeight)
    $scale = [Math]::Max(420 / $videoWidth, 280 / $videoHeight)
    $drawWidth = $videoWidth * $scale
    $drawHeight = $videoHeight * $scale
    $drawX = (420 - $drawWidth) / 2
    $drawY = (280 - $drawHeight) / 2
    $context.DrawVideo($player, (New-Object Windows.Rect $drawX, $drawY, $drawWidth, $drawHeight))
    $context.Close()

    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap 420, 280, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [System.IO.File]::Create($thumbPath)
    try {
      $encoder.Save($stream)
    } finally {
      $stream.Dispose()
    }
    $rendered = Test-Path -LiteralPath $thumbPath
    if ($rendered) {
      $thumbLength = (Get-Item -LiteralPath $thumbPath).Length
      if ($thumbLength -lt 5000) {
        Remove-Item -LiteralPath $thumbPath -Force -ErrorAction SilentlyContinue
        $rendered = $false
      }
    }
  }
  $player.Close()
} catch {
  try {
    if ($player) { $player.Close() }
  } catch {}
}

if (!$rendered) {
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct SIZE {
  public int cx;
  public int cy;
  public SIZE(int x, int y) { cx = x; cy = y; }
}

[Flags]
public enum SIIGBF {
  ResizeToFit = 0x00,
  BiggerSizeOk = 0x01,
  MemoryOnly = 0x02,
  IconOnly = 0x04,
  ThumbnailOnly = 0x08,
  InCacheOnly = 0x10
}

[ComImport]
[Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IShellItemImageFactory {
  void GetImage([In] SIZE size, [In] SIIGBF flags, out IntPtr phbm);
}

public static class AvaShellThumbnail {
  [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
  static extern void SHCreateItemFromParsingName(
    [MarshalAs(UnmanagedType.LPWStr)] string pszPath,
    IntPtr pbc,
    [MarshalAs(UnmanagedType.LPStruct)] Guid riid,
    [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory ppv);

  [DllImport("gdi32.dll")]
  static extern bool DeleteObject(IntPtr hObject);

  public static void Save(string path, string output, int width, int height) {
    Guid iid = typeof(IShellItemImageFactory).GUID;
    IShellItemImageFactory factory;
    SHCreateItemFromParsingName(path, IntPtr.Zero, iid, out factory);
    IntPtr bitmapHandle;
    factory.GetImage(new SIZE(width, height), SIIGBF.BiggerSizeOk, out bitmapHandle);
    try {
      using (Bitmap bitmap = Image.FromHbitmap(bitmapHandle)) {
        bitmap.Save(output, ImageFormat.Png);
      }
    } finally {
      DeleteObject(bitmapHandle);
    }
  }
}
"@
try {
  $shell = New-Object -ComObject Shell.Application
  $folder = $shell.Namespace([System.IO.Path]::GetDirectoryName($videoPath))
  if ($folder) {
    $item = $folder.ParseName([System.IO.Path]::GetFileName($videoPath))
    if ($item) {
      $duration = $item.ExtendedProperty("System.Media.Duration")
      if ($duration) {
        $durationMs = [int64]([double]$duration / 10000)
      }
    }
  }
} catch {}

try {
  [AvaShellThumbnail]::Save($videoPath, $thumbPath, 420, 280)
} catch {
  exit 2
}
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::WriteLine($durationMs)
''';

String _sanitizeFileName(String fileName) {
  final trimmed = fileName.trim().isEmpty ? 'attachment' : fileName.trim();
  final sanitized = trimmed.replaceAll(RegExp(r'[<>:"/\\|?*\r\n\t]'), '_');
  return sanitized.isEmpty ? 'attachment' : sanitized;
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) {
    return '${bytes}B';
  }
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)}KB';
  }
  final mb = kb / 1024;
  if (mb < 1024) {
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 2)}MB';
  }
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(gb >= 100 ? 0 : 2)}GB';
}

class _FileTransferDialog extends StatelessWidget {
  const _FileTransferDialog({required this.files});

  final List<_SelectedUploadFile> files;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 16,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      child: SizedBox(
        width: 298,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '\uD30C\uC77C \uC804\uC1A1',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  SizedBox.square(
                    dimension: 28,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.close,
                        color: Color(0xFF777777),
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 210),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final file in files)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _FileTransferRow(file: file),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black,
                    side: const BorderSide(color: Color(0xFFE0E0E0)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${files.length}\uAC1C \uC804\uC1A1',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 42),
                      const Icon(Icons.keyboard_arrow_down, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileTransferRow extends StatelessWidget {
  const _FileTransferRow({required this.file});

  final _SelectedUploadFile file;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.insert_drive_file_outlined,
          size: 25,
          color: Color(0xFF777777),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black, fontSize: 12),
              ),
              const SizedBox(height: 3),
              Text(
                _formatFileSize(file.size),
                style: const TextStyle(color: Color(0xFF777777), fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        const Icon(Icons.more_vert, size: 18, color: Color(0xFF777777)),
      ],
    );
  }
}

class _ChatMessagesView extends StatefulWidget {
  const _ChatMessagesView({
    required this.messages,
    required this.typingLabel,
    required this.onMessageContextMenu,
    required this.onOpenImages,
  });

  final List<ChatMessage> messages;
  final String? typingLabel;
  final void Function(ChatMessage message, Offset position)
  onMessageContextMenu;
  final void Function(List<ChatMessage> messages, int initialIndex)
  onOpenImages;

  @override
  State<_ChatMessagesView> createState() => _ChatMessagesViewState();
}

class _ChatMessagesViewState extends State<_ChatMessagesView> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollToBottom();
  }

  @override
  void didUpdateWidget(covariant _ChatMessagesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages.length != widget.messages.length ||
        oldWidget.typingLabel != widget.typingLabel) {
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) {
        return;
      }
      _controller.animateTo(
        _controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final showTyping = widget.typingLabel != null;
    final entries = _timelineEntries();
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: ListView.separated(
        controller: _controller,
        primary: false,
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        itemCount: entries.isEmpty
            ? (showTyping ? 1 : 0)
            : entries.length + (showTyping ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          if (entries.isEmpty) {
            return _TypingIndicator(label: widget.typingLabel);
          }
          if (showTyping && index == entries.length) {
            return _TypingIndicator(label: widget.typingLabel);
          }
          final entry = entries[index];
          if (entry.dateLabel != null) {
            return _DateChip(label: entry.dateLabel!);
          }
          if (entry.systemLabel != null) {
            return _SystemChip(label: entry.systemLabel!);
          }
          if (entry.imageGallery != null) {
            return _ImageGalleryMessage(
              key: ValueKey('chat-image-gallery-$index'),
              messages: entry.imageGallery!,
              onOpenImages: widget.onOpenImages,
              onContextMenu: widget.onMessageContextMenu,
            );
          }
          final message = entry.message!;

          return _MessageBubble(
            key: ValueKey('chat-message-$index'),
            message: message,
            onContextMenu: widget.onMessageContextMenu,
          );
        },
      ),
    );
  }

  List<_ChatTimelineEntry> _timelineEntries() {
    final entries = <_ChatTimelineEntry>[];
    DateTime? lastDate;
    var index = 0;
    while (index < widget.messages.length) {
      final message = widget.messages[index];
      final sentAt = message.sentAt?.toLocal();
      if (sentAt != null && !_isSameDate(sentAt, lastDate)) {
        entries.add(_ChatTimelineEntry.date(formatChatDateLabel(sentAt)));
        lastDate = sentAt;
      }
      if (message.isSystem) {
        entries.add(_ChatTimelineEntry.system(message.text));
        index++;
      } else if (_isImageMessage(message)) {
        final gallery = <ChatMessage>[message];
        var nextIndex = index + 1;
        while (nextIndex < widget.messages.length &&
            _canGroupImageMessages(message, widget.messages[nextIndex])) {
          final next = widget.messages[nextIndex];
          final nextSentAt = next.sentAt?.toLocal();
          if (sentAt != null &&
              nextSentAt != null &&
              !_isSameDate(sentAt, nextSentAt)) {
            break;
          }
          gallery.add(next);
          nextIndex++;
        }
        entries.add(_ChatTimelineEntry.imageGallery(gallery));
        index = nextIndex;
      } else {
        entries.add(_ChatTimelineEntry.message(message));
        index++;
      }
    }
    return entries;
  }

  bool _isSameDate(DateTime first, DateTime? second) {
    return second != null &&
        first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }
}

class _ChatTimelineEntry {
  const _ChatTimelineEntry._({
    this.message,
    this.imageGallery,
    this.dateLabel,
    this.systemLabel,
  });

  const _ChatTimelineEntry.message(ChatMessage message)
    : this._(message: message);

  const _ChatTimelineEntry.imageGallery(List<ChatMessage> messages)
    : this._(imageGallery: messages);

  const _ChatTimelineEntry.date(String label) : this._(dateLabel: label);

  const _ChatTimelineEntry.system(String label) : this._(systemLabel: label);

  final ChatMessage? message;
  final List<ChatMessage>? imageGallery;
  final String? dateLabel;
  final String? systemLabel;
}

bool _isImageMessage(ChatMessage message) {
  final attachment = message.attachment;
  return !message.isSystem && attachment != null && attachment.isImage;
}

bool _canGroupImageMessages(ChatMessage first, ChatMessage next) {
  if (!_isImageMessage(next) || first.isMine != next.isMine) {
    return false;
  }
  final firstGroupId = first.attachment?.groupId ?? '';
  final nextGroupId = next.attachment?.groupId ?? '';
  if (firstGroupId.isEmpty || nextGroupId.isEmpty) {
    return false;
  }
  if (firstGroupId != nextGroupId) {
    return false;
  }
  final firstSender = first.senderId ?? first.sender.name;
  final nextSender = next.senderId ?? next.sender.name;
  if (firstSender != nextSender) {
    return false;
  }
  return true;
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.room, required this.onClose});

  final ChatRoom room;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      color: _chatBackground,
      child: Row(
        children: [
          ProfileAvatar(profile: room.members.first, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.person,
                      color: Color(0xFF536A78),
                      size: 13,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${room.displayParticipantCount}',
                      style: const TextStyle(
                        color: Color(0xFF536A78),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const _ChatHeaderAction(
            icon: Icons.search,
            tooltip: '\uCC44\uD305\uBC29 \uAC80\uC0C9',
          ),
          const _ChatHeaderAction(
            icon: Icons.call_outlined,
            tooltip: '\uD1B5\uD654',
          ),
          const _ChatHeaderAction(
            icon: Icons.videocam_outlined,
            tooltip: '\uC601\uC0C1 \uD1B5\uD654',
          ),
          const _ChatHeaderAction(icon: Icons.menu, tooltip: '\uBA54\uB274'),
          _ChatHeaderAction(
            icon: Icons.close,
            tooltip: '\uCC44\uD305\uCC3D \uB2EB\uAE30',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _ChatHeaderAction extends StatelessWidget {
  const _ChatHeaderAction({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 30,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed ?? () {},
        icon: Icon(icon, color: _chatIconColor, size: 20),
      ),
    );
  }
}

class _ChatNoticeCard extends StatefulWidget {
  const _ChatNoticeCard({required this.message});

  final ChatMessage message;

  @override
  State<_ChatNoticeCard> createState() => _ChatNoticeCardState();
}

class _ChatNoticeCardState extends State<_ChatNoticeCard> {
  bool _isExpanded = false;

  @override
  void didUpdateWidget(covariant _ChatNoticeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) {
      _isExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('chat-notice-card'),
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.campaign, color: _noticeBlue, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.message.text,
                        key: const ValueKey('chat-notice-text'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Color(0xFF6D747A),
                        size: 20,
                      ),
                    ),
                  ],
                ),
                ClipRect(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: _isExpanded
                        ? _NoticeExpandedContent(
                            message: widget.message,
                            onCollapse: () {
                              setState(() => _isExpanded = false);
                            },
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeExpandedContent extends StatelessWidget {
  const _NoticeExpandedContent({
    required this.message,
    required this.onCollapse,
  });

  final ChatMessage message;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    if (message.text.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 1, color: Color(0xFFECECEC)),
            const SizedBox(height: 10),
            Text(
              '${message.sender.name} 夷?${message.time}',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message.text,
              style: const TextStyle(
                color: Color(0xFF555555),
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onCollapse,
                style: TextButton.styleFrom(
                  foregroundColor: _chatIconColor,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('?묒뼱?먭린'),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, color: Color(0xFFECECEC)),
          const SizedBox(height: 10),
          const Text(
            '?ㅻ뒛 怨듭쑀??二쇱슂 怨듭??ы빆?낅땲??',
            style: TextStyle(
              color: Colors.black,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '?낅Т 怨듭쑀 ?먮즺? ?뚯쓽 ?쇱젙???뺤씤??二쇱꽭??',
            style: TextStyle(
              color: Color(0xFF555555),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onCollapse,
              style: TextButton.styleFrom(
                foregroundColor: _chatIconColor,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('?묒뼱?먭린'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageMenuItem extends StatefulWidget {
  const _MessageMenuItem({required this.label, this.trailing, super.key});

  final String label;
  final IconData? trailing;

  @override
  State<_MessageMenuItem> createState() => _MessageMenuItemState();
}

class _MessageMenuItemState extends State<_MessageMenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        width: 130,
        height: 28,
        color: _isHovered ? const Color(0xFFEFEFEF) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  height: 1.1,
                ),
              ),
            ),
            if (widget.trailing != null)
              Icon(widget.trailing, size: 14, color: const Color(0xFF444444)),
          ],
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFABC2D2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.calendar_month_outlined,
                color: Color(0xFF3D5563),
                size: 13,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF213640),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemChip extends StatelessWidget {
  const _SystemChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFABC2D2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF213640),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({required this.label});

  final String? label;

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _dotOpacity(int index) {
    final phase = (_controller.value + index * 0.22) % 1;
    return phase < 0.45 ? 1 : 0.34;
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label ?? '';

    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: Column(
          key: ValueKey('typing-${label.isEmpty ? 'direct' : label}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 5),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF4D6370),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            CustomPaint(
              painter: const _TypingBubbleTailPainter(),
              child: Container(
                width: 36,
                height: 26,
                padding: const EdgeInsets.only(left: 9, right: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF9DA8AF),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var index = 0; index < 3; index++)
                          Opacity(
                            opacity: _dotOpacity(index),
                            child: const SizedBox.square(
                              dimension: 4,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Color(0xFFFFDF00),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubbleTailPainter extends CustomPainter {
  const _TypingBubbleTailPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF9DA8AF);
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(-6, 0)
      ..lineTo(0, 6)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TypingBubbleTailPainter oldDelegate) => false;
}

class _ImageGalleryMessage extends StatelessWidget {
  const _ImageGalleryMessage({
    required this.messages,
    required this.onOpenImages,
    required this.onContextMenu,
    super.key,
  });

  final List<ChatMessage> messages;
  final void Function(List<ChatMessage> messages, int initialIndex)
  onOpenImages;
  final void Function(ChatMessage message, Offset position) onContextMenu;

  @override
  Widget build(BuildContext context) {
    final first = messages.first;
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTapDown: (details) {
        onContextMenu(first, details.globalPosition);
      },
      child: first.isMine ? _mine(context, first) : _other(context, first),
    );
  }

  Widget _other(BuildContext context, ChatMessage first) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubbleWidth = constraints.maxWidth * 0.68;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileAvatar(profile: first.sender, size: 38),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    first.sender.name,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                          child: _ImageGalleryBubble(
                            messages: messages,
                            onOpenImages: onOpenImages,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        first.time,
                        style: const TextStyle(
                          color: Color(0xFF4D6370),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _mine(BuildContext context, ChatMessage first) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubbleWidth = constraints.maxWidth * 0.68;
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (first.unreadCount > 0)
                  Text(
                    '${first.unreadCount}',
                    style: const TextStyle(
                      color: Color(0xFFFFF263),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                Text(
                  first.time,
                  style: const TextStyle(
                    color: Color(0xFF4D6370),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                child: _ImageGalleryBubble(
                  messages: messages,
                  onOpenImages: onOpenImages,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ImageGalleryBubble extends StatelessWidget {
  const _ImageGalleryBubble({
    required this.messages,
    required this.onOpenImages,
  });

  final List<ChatMessage> messages;
  final void Function(List<ChatMessage> messages, int initialIndex)
  onOpenImages;

  @override
  Widget build(BuildContext context) {
    if (messages.length == 1) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onOpenImages(messages, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            width: 210,
            height: 150,
            child: _AttachmentImagePreview(
              attachment: messages.first.attachment!,
            ),
          ),
        ),
      );
    }

    final count = messages.length;
    final columns = count == 2 || count == 4 ? 2 : 3;
    const spacing = 2.0;
    final cellSize = columns == 2 ? 104.0 : 68.0;
    final visibleCount = count >= 10 ? 9 : count.clamp(0, 9);
    final width = columns * cellSize + (columns - 1) * spacing;
    return SizedBox(
      width: width,
      child: Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (var index = 0; index < visibleCount; index++)
            _ImageGalleryCell(
              message: messages[count >= 10 && index == 8 ? 7 : index],
              size: cellSize,
              overlayCount: count >= 10 && index == 8 ? count - 8 : 0,
              onTap: () =>
                  onOpenImages(messages, count >= 10 && index == 8 ? 0 : index),
            ),
        ],
      ),
    );
  }
}

class _ImageGalleryCell extends StatelessWidget {
  const _ImageGalleryCell({
    required this.message,
    required this.size,
    required this.overlayCount,
    required this.onTap,
  });

  final ChatMessage message;
  final double size;
  final int overlayCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.square(
              dimension: size,
              child: _AttachmentImagePreview(attachment: message.attachment!),
            ),
            if (overlayCount > 0)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.48),
                  ),
                  child: Center(
                    child: Text(
                      '+$overlayCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentImagePreview extends ConsumerWidget {
  const _AttachmentImagePreview({required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localPath = attachment.localPath;
    if (localPath != null &&
        localPath.isNotEmpty &&
        File(localPath).existsSync() &&
        attachment.hasFreshLocalFile) {
      return Image.file(
        File(localPath),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const _ImagePreviewFallback(),
      );
    }

    final session = ref.watch(authControllerProvider).value?.session;
    final headers = session?.accessToken.isNotEmpty == true
        ? {'Authorization': 'Bearer ${session!.accessToken}'}
        : null;
    return Image.network(
      _absoluteAttachmentUrl(
        ref.watch(appConfigProvider).apiBaseUrl,
        attachment.downloadUrl,
      ),
      headers: headers,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        return const _ImagePreviewFallback(isLoading: true);
      },
      errorBuilder: (context, error, stackTrace) =>
          const _ImagePreviewFallback(),
    );
  }
}

class _ImagePreviewFallback extends StatelessWidget {
  const _ImagePreviewFallback({this.isLoading = false});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFE8EEF2)),
      child: Center(
        child: isLoading
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(
                Icons.image_outlined,
                color: Color(0xFF8A9AA4),
                size: 32,
              ),
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.message,
    required this.onContextMenu,
    super.key,
  });

  final ChatMessage message;
  final void Function(ChatMessage message, Offset position) onContextMenu;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _spoilerRevealed = false;

  @override
  void didUpdateWidget(covariant _MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.text != widget.message.text) {
      _spoilerRevealed = widget.message.spoilerRevealed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message.copyWith(
      spoilerRevealed: _spoilerRevealed || widget.message.spoilerRevealed,
    );
    final child = message.isMine
        ? _MineMessage(
            message: message,
            onRevealSpoiler: () => setState(() => _spoilerRevealed = true),
          )
        : _OtherMessage(
            message: message,
            onRevealSpoiler: () => setState(() => _spoilerRevealed = true),
          );

    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTapDown: (details) {
        widget.onContextMenu(widget.message, details.globalPosition);
      },
      child: child,
    );
  }
}

class _OtherMessage extends StatelessWidget {
  const _OtherMessage({required this.message, required this.onRevealSpoiler});

  final ChatMessage message;
  final VoidCallback onRevealSpoiler;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubbleWidth = constraints.maxWidth * 0.68;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileAvatar(profile: message.sender, size: 38),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.sender.name,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                          child: _BubbleSurface(
                            color: Colors.white,
                            text: message.text,
                            attachment: message.attachment,
                            isMine: false,
                            senderName: message.sender.name,
                            sentAt: message.sentAt,
                            isSpoiler: message.isSpoiler,
                            spoilerRevealed: message.spoilerRevealed,
                            onRevealSpoiler: onRevealSpoiler,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        message.time,
                        style: const TextStyle(
                          color: Color(0xFF4D6370),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MineMessage extends StatelessWidget {
  const _MineMessage({required this.message, required this.onRevealSpoiler});

  final ChatMessage message;
  final VoidCallback onRevealSpoiler;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubbleWidth = constraints.maxWidth * 0.68;

        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (message.unreadCount > 0)
                  Text(
                    '${message.unreadCount}',
                    style: const TextStyle(
                      color: Color(0xFFFFF263),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                Text(
                  message.time,
                  style: const TextStyle(
                    color: Color(0xFF4D6370),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                child: _BubbleSurface(
                  color: const Color(0xFFFFDF00),
                  text: message.text,
                  attachment: message.attachment,
                  isMine: true,
                  senderName: message.sender.name,
                  sentAt: message.sentAt,
                  isSpoiler: message.isSpoiler,
                  spoilerRevealed: message.spoilerRevealed,
                  onRevealSpoiler: onRevealSpoiler,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BubbleSurface extends StatelessWidget {
  const _BubbleSurface({
    required this.color,
    required this.text,
    required this.attachment,
    required this.isMine,
    required this.senderName,
    required this.sentAt,
    required this.isSpoiler,
    required this.spoilerRevealed,
    required this.onRevealSpoiler,
  });

  final Color color;
  final String text;
  final ChatAttachment? attachment;
  final bool isMine;
  final String senderName;
  final DateTime? sentAt;
  final bool isSpoiler;
  final bool spoilerRevealed;
  final VoidCallback onRevealSpoiler;

  @override
  Widget build(BuildContext context) {
    final shouldBlur = isSpoiler && !spoilerRevealed;
    final currentAttachment = attachment;
    Widget content;
    if (currentAttachment != null) {
      content = currentAttachment.isVideo
          ? _VideoBubbleContent(
              attachment: currentAttachment,
              senderName: senderName,
              sentAt: sentAt,
            )
          : _AttachmentBubbleContent(attachment: currentAttachment);
    } else {
      final textWidget = Text(
        text,
        softWrap: true,
        style: const TextStyle(color: Colors.black, fontSize: 13, height: 1.28),
      );
      content = textWidget;
      if (shouldBlur) {
        content = ClipRect(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 3.4, sigmaY: 3.4),
            child: textWidget,
          ),
        );
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: shouldBlur ? onRevealSpoiler : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: currentAttachment == null
              ? color
              : currentAttachment.isVideo
              ? Colors.transparent
              : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3),
            bottomLeft: Radius.circular(isMine ? 3 : 1),
            bottomRight: Radius.circular(isMine ? 1 : 3),
          ),
        ),
        child: Padding(
          padding: currentAttachment == null
              ? const EdgeInsets.symmetric(horizontal: 9, vertical: 7)
              : currentAttachment.isVideo
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: content,
        ),
      ),
    );
  }
}

class _VideoBubbleContent extends ConsumerStatefulWidget {
  const _VideoBubbleContent({
    required this.attachment,
    required this.senderName,
    required this.sentAt,
  });

  final ChatAttachment attachment;
  final String senderName;
  final DateTime? sentAt;

  @override
  ConsumerState<_VideoBubbleContent> createState() =>
      _VideoBubbleContentState();
}

class _VideoBubbleContentState extends ConsumerState<_VideoBubbleContent> {
  String? _localPath;
  DateTime? _savedAt;
  bool _isSaving = false;
  double _progress = 0;
  Duration? _duration;

  @override
  void initState() {
    super.initState();
    _hydrateLocalPath();
  }

  @override
  void didUpdateWidget(covariant _VideoBubbleContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.id != widget.attachment.id ||
        oldWidget.attachment.localPath != widget.attachment.localPath) {
      _hydrateLocalPath();
    }
  }

  void _hydrateLocalPath() {
    final localPath = widget.attachment.localPath;
    if (localPath != null &&
        localPath.isNotEmpty &&
        File(localPath).existsSync()) {
      _localPath = localPath;
      _savedAt = widget.attachment.cachedAt ?? DateTime.now();
      return;
    }
    _localPath = null;
    _savedAt = null;
    _duration = null;
  }

  bool get _hasLocalVideo {
    final path = _localPath;
    return path != null && path.isNotEmpty && File(path).existsSync();
  }

  Future<void> _saveVideo() async {
    if (_isSaving || widget.attachment.transferInProgress) {
      return;
    }
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      showAvaToast(context, '다운로드 권한이 없습니다.');
      return;
    }

    final targetPath = await _pickVideoSavePath(
      context,
      widget.attachment.fileName,
    );
    if (!mounted || targetPath == null || targetPath.isEmpty) {
      return;
    }

    setState(() {
      _isSaving = true;
      _progress = 0;
    });
    try {
      await ref
          .read(chatApiProvider)
          .downloadAttachment(
            accessToken: session.accessToken,
            downloadUrl: widget.attachment.downloadUrl,
            savePath: targetPath,
            onReceiveProgress: (received, total) {
              if (!mounted || total <= 0) {
                return;
              }
              setState(() {
                _progress = (received / total).clamp(0, 1).toDouble();
              });
            },
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _localPath = targetPath;
        _savedAt = DateTime.now();
        _progress = 1;
      });
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _playVideo() async {
    final path = _localPath;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      showAvaToast(context, '동영상 파일을 찾을 수 없습니다.');
      return;
    }
    final opened = await _showAvaVideoViewer(
      path: path,
      fileName: widget.attachment.fileName,
      senderName: widget.senderName,
      sentAt: widget.sentAt ?? _savedAt ?? DateTime.now(),
    );
    if (!opened && mounted) {
      showAvaToast(context, '동영상을 열 수 없습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLocalVideo = _hasLocalVideo;
    final isTransferring = widget.attachment.transferInProgress || _isSaving;
    final transferBytes = widget.attachment.transferInProgress
        ? widget.attachment.transferBytes
        : (_progress * widget.attachment.size).round();
    final transferTotal = widget.attachment.transferInProgress
        ? widget.attachment.transferTotalBytes
        : widget.attachment.size;
    final transferProgress = widget.attachment.transferInProgress
        ? transferBytes / math.max(1, transferTotal)
        : _progress;
    final label = isTransferring
        ? _formatTransferSize(transferBytes, transferTotal)
        : hasLocalVideo
        ? _formatVideoDuration(_duration)
        : _formatFileSize(widget.attachment.size);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isTransferring
          ? null
          : hasLocalVideo
          ? _playVideo
          : _saveVideo,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          width: 210,
          height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: _VideoThumbnailPreview(
                  attachment: widget.attachment,
                  localPath: _localPath,
                  onDurationChanged: (duration) {
                    if (!mounted ||
                        duration <= Duration.zero ||
                        duration == _duration) {
                      return;
                    }
                    setState(() => _duration = duration);
                  },
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.12),
                  ),
                ),
              ),
              if (isTransferring)
                _VideoProgressDonut(
                  progress: transferProgress.clamp(0, 1).toDouble(),
                )
              else
                _VideoCenterAction(
                  icon: hasLocalVideo
                      ? Icons.play_arrow_rounded
                      : Icons.videocam_rounded,
                  onTap: hasLocalVideo ? _playVideo : _saveVideo,
                ),
              Positioned(
                top: 86,
                left: 0,
                right: 0,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    shadows: [
                      Shadow(
                        color: Color(0x8A000000),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoThumbnailPreview extends ConsumerStatefulWidget {
  const _VideoThumbnailPreview({
    required this.attachment,
    required this.localPath,
    required this.onDurationChanged,
  });

  final ChatAttachment attachment;
  final String? localPath;
  final ValueChanged<Duration> onDurationChanged;

  @override
  ConsumerState<_VideoThumbnailPreview> createState() =>
      _VideoThumbnailPreviewState();
}

class _VideoThumbnailPreviewState
    extends ConsumerState<_VideoThumbnailPreview> {
  File? _thumbnailFile;
  String? _loadedSource;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadThumbnail());
  }

  @override
  void didUpdateWidget(covariant _VideoThumbnailPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.id != widget.attachment.id ||
        oldWidget.localPath != widget.localPath) {
      unawaited(_loadThumbnail());
    }
  }

  Future<void> _loadThumbnail() async {
    if (_isLoading || !Platform.isWindows) {
      return;
    }
    var localPath = widget.localPath;
    if (localPath == null ||
        localPath.isEmpty ||
        !await File(localPath).exists()) {
      localPath = await _downloadPreviewCopy();
    }
    if (localPath == null ||
        localPath.isEmpty ||
        !await File(localPath).exists()) {
      if (mounted) {
        setState(() {
          _thumbnailFile = null;
          _loadedSource = null;
        });
      }
      return;
    }
    if (_loadedSource == localPath && _thumbnailFile?.existsSync() == true) {
      return;
    }

    _isLoading = true;
    try {
      final thumbnailPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'ava_video_thumb_${widget.attachment.id}_'
          '${DateTime.now().microsecondsSinceEpoch}.png';
      final result = await _createVideoThumbnail(
        videoPath: localPath,
        thumbnailPath: thumbnailPath,
      );
      if (!mounted) {
        return;
      }
      if (result != null && await File(thumbnailPath).exists()) {
        widget.onDurationChanged(result.duration);
        setState(() {
          _thumbnailFile = File(thumbnailPath);
          _loadedSource = localPath;
        });
      } else {
        setState(() {
          _thumbnailFile = null;
          _loadedSource = localPath;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _thumbnailFile = null;
          _loadedSource = localPath;
        });
      }
    } finally {
      _isLoading = false;
    }
  }

  Future<String?> _downloadPreviewCopy() async {
    final session = ref.read(authControllerProvider).value?.session;
    final accessToken = session?.accessToken;
    if (accessToken == null ||
        accessToken.isEmpty ||
        widget.attachment.downloadUrl.isEmpty) {
      return null;
    }
    try {
      final previewPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'ava_video_preview_${widget.attachment.id}_'
          '${_sanitizeFileName(widget.attachment.fileName)}';
      final previewFile = File(previewPath);
      if (await previewFile.exists() &&
          await previewFile.length() == widget.attachment.size) {
        return previewPath;
      }
      await ref
          .read(chatApiProvider)
          .downloadAttachment(
            accessToken: accessToken,
            downloadUrl: widget.attachment.downloadUrl,
            savePath: previewPath,
          );
      return previewPath;
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumbnail = _thumbnailFile;
    if (thumbnail == null || !thumbnail.existsSync()) {
      return const _VideoPreviewFallback();
    }
    return Image.file(
      thumbnail,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          const _VideoPreviewFallback(),
    );
  }
}

class _VideoPreviewFallback extends StatelessWidget {
  const _VideoPreviewFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Color(0xFF1D252B)),
      child: Center(
        child: Icon(
          Icons.movie_creation_outlined,
          color: Color(0xFF8FA1AA),
          size: 34,
        ),
      ),
    );
  }
}

class _VideoCenterAction extends StatelessWidget {
  const _VideoCenterAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.56),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          onPressed: onTap,
          padding: EdgeInsets.zero,
          icon: Icon(icon, color: Colors.white, size: 27),
        ),
      ),
    );
  }
}

class _VideoProgressDonut extends StatelessWidget {
  const _VideoProgressDonut({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0, 1).toDouble();
    return SizedBox.square(
      dimension: 52,
      child: CustomPaint(
        painter: _VideoProgressPainter(progress: clamped),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: const SizedBox.square(
              dimension: 30,
              child: Icon(Icons.close_rounded, color: Colors.white, size: 23),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoProgressPainter extends CustomPainter {
  const _VideoProgressPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 3;
    final background = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final foreground = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, background);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      foreground,
    );
  }

  @override
  bool shouldRepaint(covariant _VideoProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _AttachmentBubbleContent extends ConsumerStatefulWidget {
  const _AttachmentBubbleContent({required this.attachment});

  final ChatAttachment attachment;

  @override
  ConsumerState<_AttachmentBubbleContent> createState() =>
      _AttachmentBubbleContentState();
}

class _AttachmentBubbleContentState
    extends ConsumerState<_AttachmentBubbleContent> {
  String? _localPath;
  DateTime? _cachedAt;
  bool _isDownloading = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    if (widget.attachment.hasFreshLocalFile) {
      _localPath = widget.attachment.localPath;
      _cachedAt = widget.attachment.cachedAt;
    }
  }

  bool get _hasFreshLocalFile {
    final path = _localPath;
    final cachedAt = _cachedAt;
    if (path == null || path.isEmpty || cachedAt == null) {
      return false;
    }
    if (DateTime.now().difference(cachedAt) >= const Duration(hours: 1)) {
      return false;
    }
    return File(path).existsSync();
  }

  Future<void> _download() async {
    if (_isDownloading) {
      return;
    }
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      showAvaToast(context, '다운로드 권한이 없습니다.');
      return;
    }
    setState(() {
      _isDownloading = true;
      _progress = 0;
    });
    try {
      final targetPath = await _nextDownloadPath(widget.attachment.fileName);
      await ref
          .read(chatApiProvider)
          .downloadAttachment(
            accessToken: session.accessToken,
            downloadUrl: widget.attachment.downloadUrl,
            savePath: targetPath,
            onReceiveProgress: (received, total) {
              if (!mounted || total <= 0) {
                return;
              }
              setState(() {
                _progress = (received / total).clamp(0, 1).toDouble();
              });
            },
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _localPath = targetPath;
        _cachedAt = DateTime.now();
        _progress = 1;
      });
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  Future<void> _openFile() async {
    final path = await _ensureDownloadsLocalPath();
    if (!mounted) {
      return;
    }
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      showAvaToast(context, '파일을 찾을 수 없습니다.');
      return;
    }
    if (Platform.isWindows) {
      await Process.run('rundll32.exe', ['url.dll,FileProtocolHandler', path]);
    } else {
      showAvaToast(context, '현재 파일 열기는 Windows에서 지원됩니다.');
    }
  }

  Future<void> _openFolder() async {
    final path = await _ensureDownloadsLocalPath();
    if (!mounted) {
      return;
    }
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      showAvaToast(context, '파일을 찾을 수 없습니다.');
      return;
    }
    final downloads = await _downloadsDirectory();
    if (!mounted) {
      return;
    }
    if (Platform.isWindows) {
      if (_isPathInDirectory(path, downloads)) {
        await Process.run('explorer.exe', ['/select,', path]);
      } else {
        await Process.run('explorer.exe', [downloads.path]);
      }
    } else {
      showAvaToast(context, '현재 폴더 열기는 Windows에서 지원됩니다.');
    }
  }

  Future<String?> _ensureDownloadsLocalPath() async {
    final path = _localPath;
    final cachedAt = _cachedAt;
    if (path == null || path.isEmpty || cachedAt == null) {
      return null;
    }
    if (DateTime.now().difference(cachedAt) >= const Duration(hours: 1)) {
      return null;
    }
    final source = File(path);
    if (!await source.exists()) {
      return null;
    }
    final downloads = await _downloadsDirectory();
    if (_isPathInDirectory(path, downloads)) {
      return path;
    }
    try {
      final targetPath = await _nextDownloadPath(widget.attachment.fileName);
      await source.copy(targetPath);
      if (mounted) {
        setState(() {
          _localPath = targetPath;
          _cachedAt = DateTime.now();
        });
      }
      return targetPath;
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canOpen = _hasFreshLocalFile;
    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.attachment.fileName,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    height: 1.22,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _AttachmentActionIcon(
                isDownloading: _isDownloading,
                progress: _progress,
                canOpen: canOpen,
                onDownload: _download,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '유효기간: ~${_expiryLabel()}',
            style: const TextStyle(color: Color(0xFF777777), fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            '용량: ${_formatFileSize(widget.attachment.size)}',
            style: const TextStyle(color: Color(0xFF777777), fontSize: 11),
          ),
          const SizedBox(height: 8),
          if (canOpen)
            Row(
              children: [
                _AttachmentTextButton(label: '열기', onTap: _openFile),
                const Text(
                  ' · ',
                  style: TextStyle(color: Color(0xFF1D63AA), fontSize: 11),
                ),
                _AttachmentTextButton(label: '폴더 열기', onTap: _openFolder),
              ],
            )
          else
            _AttachmentTextButton(
              label: _isDownloading ? '다운로드 중' : '다운로드',
              onTap: _isDownloading ? null : _download,
            ),
        ],
      ),
    );
  }

  String _expiryLabel() {
    final expiry = DateTime.now().add(const Duration(days: 14));
    return '${expiry.year}.${expiry.month.toString().padLeft(2, '0')}.${expiry.day.toString().padLeft(2, '0')}.';
  }
}

class _AttachmentActionIcon extends StatelessWidget {
  const _AttachmentActionIcon({
    required this.isDownloading,
    required this.progress,
    required this.canOpen,
    required this.onDownload,
  });

  final bool isDownloading;
  final double progress;
  final bool canOpen;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    if (canOpen) {
      return const Icon(
        Icons.insert_drive_file_outlined,
        size: 30,
        color: Color(0xFF777777),
      );
    }
    return SizedBox.square(
      dimension: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isDownloading)
            CircularProgressIndicator(
              value: progress <= 0 ? null : progress,
              strokeWidth: 2.4,
              color: const Color(0xFF555555),
              backgroundColor: const Color(0xFFE6E6E6),
            )
          else
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F2),
                shape: BoxShape.circle,
              ),
              child: SizedBox.expand(
                child: IconButton(
                  onPressed: onDownload,
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.arrow_downward,
                    size: 22,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AttachmentTextButton extends StatelessWidget {
  const _AttachmentTextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: onTap == null
              ? const Color(0xFF9A9A9A)
              : const Color(0xFF1D63AA),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _MessageComposer extends StatefulWidget {
  const _MessageComposer({
    required this.onSend,
    required this.onAttachFiles,
    required this.onTypingChanged,
    required this.enabled,
  });

  final Future<void> Function(String content, [_SendOptions options]) onSend;
  final VoidCallback onAttachFiles;
  final ValueChanged<bool> onTypingChanged;
  final bool enabled;

  @override
  State<_MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<_MessageComposer> {
  final TextEditingController _controller = TextEditingController();
  Timer? _typingStopTimer;
  bool _canSend = false;
  bool _isSending = false;
  bool _isTyping = false;
  double _transparency = 0;

  @override
  void didUpdateWidget(covariant _MessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) {
      _setTyping(false);
      _controller.clear();
      _canSend = false;
    }
  }

  @override
  void dispose() {
    _setTyping(false);
    _typingStopTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    if (!widget.enabled) {
      _setTyping(false);
      return;
    }
    final canSend = _controller.text.trim().isNotEmpty;
    if (canSend) {
      _refreshTypingTimer();
    } else {
      _setTyping(false);
    }
    if (canSend == _canSend) {
      return;
    }
    setState(() {
      _canSend = canSend;
    });
  }

  void _refreshTypingTimer() {
    if (!_isTyping) {
      _setTyping(true);
    }
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(milliseconds: 2500), () {
      _setTyping(false);
    });
  }

  void _setTyping(bool typing) {
    if (_isTyping == typing) {
      return;
    }
    _isTyping = typing;
    widget.onTypingChanged(typing);
    if (!typing) {
      _typingStopTimer?.cancel();
      _typingStopTimer = null;
    }
  }

  Future<void> _handleSend([
    _SendOptions options = const _SendOptions(),
  ]) async {
    if (!widget.enabled || !_canSend || _isSending) {
      return;
    }

    final content = _controller.text.trim();
    setState(() {
      _isSending = true;
    });
    try {
      await widget.onSend(content, options);
      if (!mounted) {
        return;
      }
      _setTyping(false);
      _controller.clear();
      setState(() {
        _canSend = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  KeyEventResult _handleComposerKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) {
      return KeyEventResult.ignored;
    }
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final isShiftPressed =
        pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);
    if (isShiftPressed) {
      return KeyEventResult.ignored;
    }
    _handleSend();
    return KeyEventResult.handled;
  }

  Future<void> _showSendModeMenu() async {
    if (!widget.enabled || !_canSend || _isSending) {
      return;
    }
    final renderBox = context.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = renderBox?.size ?? Size.zero;
    if (Platform.isWindows) {
      final result = await WindowControl.showNativeMenu(
        items: [
          _nativeMenuItem(
            'quiet',
            '\uC870\uC6A9\uD788 \uBCF4\uB0B4\uAE30',
            icon: 'quiet',
          ),
          _nativeMenuItem(
            'spoiler',
            '\uC2A4\uD3EC \uBC29\uC9C0',
            icon: 'spoiler',
          ),
        ],
        x: offset.dx + size.width - 126,
        y: offset.dy + size.height - 104,
      );
      final mode = switch (result) {
        'quiet' => _SendMode.quiet,
        'spoiler' => _SendMode.spoiler,
        _ => null,
      };
      if (mode != null) {
        await _handleSend(_SendOptions(mode: mode));
      }
      return;
    }

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final result = await showMenu<_SendMode>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx + size.width - 148,
        offset.dy + size.height - 126,
        overlay.size.width - offset.dx - size.width + 8,
        overlay.size.height - offset.dy,
      ),
      elevation: 8,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFC8C8C8)),
        borderRadius: BorderRadius.circular(2),
      ),
      items: const [
        PopupMenuItem(
          value: _SendMode.quiet,
          height: 30,
          padding: EdgeInsets.zero,
          child: _SendModeMenuItem(
            icon: Icons.notifications_off_outlined,
            label: '\uC870\uC6A9\uD788 \uBCF4\uB0B4\uAE30',
          ),
        ),
        PopupMenuItem(
          value: _SendMode.spoiler,
          height: 30,
          padding: EdgeInsets.zero,
          child: _SendModeMenuItem(
            icon: Icons.blur_circular_outlined,
            label: '\uC2A4\uD3EC \uBC29\uC9C0',
          ),
        ),
      ],
    );
    if (result != null) {
      await _handleSend(_SendOptions(mode: result));
    }
  }

  void _setTransparency(double value) {
    setState(() {
      _transparency = value;
    });
    unawaited(
      WindowControl.setMessengerOpacity((1 - value).clamp(0.18, 1).toDouble()),
    );
  }

  void _showUnimplementedToast() {
    final renderBox = context.findRenderObject() as RenderBox?;
    final globalCenter = renderBox?.localToGlobal(
      Offset(renderBox.size.width / 2, -38),
    );
    showAvaToast(
      context,
      '\uBBF8 \uAD6C\uD604 \uAE30\uB2A5',
      globalCenter: globalCenter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sendEnabled = widget.enabled && _canSend && !_isSending;

    return Container(
      height: 122,
      color: Colors.white,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: widget.enabled
                  ? Focus(
                      onKeyEvent: _handleComposerKey,
                      child: TextField(
                        controller: _controller,
                        enabled: widget.enabled,
                        onChanged: (_) => _handleTextChanged(),
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(
                          hintText: '\uBA54\uC2DC\uC9C0 \uC785\uB825',
                          hintStyle: TextStyle(
                            color: Color(0xFF9A9A9A),
                            fontSize: 13,
                          ),
                          border: InputBorder.none,
                          isCollapsed: true,
                        ),
                      ),
                    )
                  : const Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        '\uBA54\uC2DC\uC9C0\uB97C \uC785\uB825\uD560\uC218\uC5C6\uC74C',
                        style: TextStyle(
                          color: Color(0xFF9A9A9A),
                          fontSize: 13,
                        ),
                      ),
                    ),
            ),
          ),
          SizedBox(
            height: 42,
            child: Row(
              children: [
                const SizedBox(width: 4),
                _ComposerIconButton(
                  icon: Icons.add,
                  tooltip: '\uCCA8\uBD80',
                  onPressed: _showUnimplementedToast,
                ),
                _ComposerIconButton(
                  icon: Icons.sentiment_satisfied_alt_outlined,
                  tooltip: '\uC774\uBAA8\uD2F0\uCF58',
                  onPressed: _showUnimplementedToast,
                ),
                _ComposerIconButton(
                  icon: Icons.insert_drive_file_outlined,
                  tooltip: '\uD30C\uC77C',
                  onPressed: widget.onAttachFiles,
                ),
                const Spacer(),
                SizedBox(
                  width: 58,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 1,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: const Color(0xFFB8B8B8),
                      inactiveTrackColor: const Color(0xFFE0E0E0),
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: _transparency,
                      min: 0,
                      max: 1,
                      onChanged: _setTransparency,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SendSplitButton(
                  enabled: sendEnabled,
                  isSending: _isSending,
                  onSend: _handleSend,
                  onMenu: _showSendModeMenu,
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SendSplitButton extends StatelessWidget {
  const _SendSplitButton({
    required this.enabled,
    required this.isSending,
    required this.onSend,
    required this.onMenu,
  });

  final bool enabled;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final background = enabled
        ? const Color(0xFFFFDF00)
        : const Color(0xFFF4F4F4);
    final foreground = enabled ? Colors.black : const Color(0xFF7E7E7E);
    return SizedBox(
      height: 32,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: enabled ? onSend : null,
              style: TextButton.styleFrom(
                foregroundColor: foreground,
                disabledForegroundColor: foreground,
                minimumSize: const Size(54, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(4),
                    bottomLeft: Radius.circular(4),
                  ),
                ),
              ),
              child: Text(
                isSending ? '\uC804\uC1A1 \uC911' : '\uC804\uC1A1',
                style: TextStyle(color: foreground, fontSize: 12),
              ),
            ),
            Container(width: 1, height: 18, color: const Color(0xFFD4BE00)),
            SizedBox(
              width: 30,
              height: 32,
              child: IconButton(
                onPressed: enabled ? onMenu : null,
                disabledColor: foreground,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.keyboard_arrow_down,
                  color: foreground,
                  size: 17,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SendModeMenuItem extends StatefulWidget {
  const _SendModeMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  State<_SendModeMenuItem> createState() => _SendModeMenuItemState();
}

class _SendModeMenuItemState extends State<_SendModeMenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        width: 122,
        height: 30,
        color: _hovered ? const Color(0xFFEFEFEF) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Icon(widget.icon, size: 15, color: const Color(0xFF222222)),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: const TextStyle(color: Colors.black, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 34,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon, color: _chatIconColor, size: 21),
      ),
    );
  }
}
