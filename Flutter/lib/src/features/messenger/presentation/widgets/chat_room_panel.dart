import 'dart:async';
import 'dart:convert' show base64, base64Url, jsonDecode, jsonEncode, utf8;
import 'dart:io' show Directory, File, Platform, Process;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

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

enum _MessageDeleteMode { forEveryone, forMe }

class _SendOptions {
  const _SendOptions({this.mode = _SendMode.normal, this.mentions = const []});

  final _SendMode mode;
  final List<ChatMentionDto> mentions;
  bool get silent => mode == _SendMode.quiet;
  bool get spoiler => mode == _SendMode.spoiler;

  _SendOptions withMentions(List<ChatMentionDto> value) {
    return _SendOptions(mode: mode, mentions: value);
  }
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

class _TypingParticipant {
  const _TypingParticipant({
    required this.displayName,
    required this.firstSeenAt,
  });

  final String displayName;
  final DateTime firstSeenAt;
}

final chatMessageMemoryCacheProvider =
    NotifierProvider<ChatMessageMemoryCache, Map<String, List<ChatMessage>>>(
      ChatMessageMemoryCache.new,
    );

class ChatMessageMemoryCache extends Notifier<Map<String, List<ChatMessage>>> {
  static const int _maxMessagesPerRoom = 300;
  static const int _maxPersistedRooms = 32;
  static const int _maxPersistedChars = 4 * 1024 * 1024;
  static const String _storagePrefix = 'ava.chat.message_cache.v3';
  String? _scope;
  String? _storageKey;
  String? _hydratedScope;
  Future<void>? _hydrationFuture;
  Future<void>? _persistFuture;
  bool _persistAgain = false;

  @override
  Map<String, List<ChatMessage>> build() => const {};

  List<ChatMessage> messagesFor(String roomId) => state[roomId] ?? const [];

  void configureScope(String scope) {
    final normalizedScope = scope.trim();
    if (normalizedScope.isEmpty || _scope == normalizedScope) {
      return;
    }
    _scope = normalizedScope;
    _storageKey =
        '$_storagePrefix.${base64Url.encode(utf8.encode(normalizedScope))}';
    _hydratedScope = null;
    _hydrationFuture = null;
    _persistAgain = false;
  }

  Future<void> hydrate(String scope) {
    configureScope(scope);
    if (_scope == null || _storageKey == null) {
      return Future<void>.value();
    }
    if (_hydratedScope == _scope) {
      return Future<void>.value();
    }
    final running = _hydrationFuture;
    if (running != null) {
      return running;
    }
    final future = _hydrateCurrentScope();
    _hydrationFuture = future;
    return future;
  }

  Future<List<ChatMessage>> hydrateRoom(String roomId) async {
    if (roomId.isEmpty) {
      return const [];
    }
    final cached = messagesFor(roomId);
    if (cached.isNotEmpty) {
      return cached;
    }
    final scope = _scope;
    if (scope == null || scope.isEmpty) {
      return const [];
    }
    await hydrate(scope);
    return messagesFor(roomId);
  }

  Future<void> _hydrateCurrentScope() async {
    final key = _storageKey;
    final scope = _scope;
    if (key == null || scope == null) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) {
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return;
      }
      final next = <String, List<ChatMessage>>{};
      for (final entry in decoded.entries) {
        final roomId = entry.key.toString();
        final values = entry.value;
        if (roomId.isEmpty || values is! List) {
          continue;
        }
        final messages = [
          for (final item in values)
            if (item is Map)
              _messageFromCacheJson(item.cast<String, dynamic>()),
        ].whereType<ChatMessage>().toList(growable: false);
        if (messages.isNotEmpty) {
          next[roomId] = List<ChatMessage>.unmodifiable(
            _dedupeAndTrim(messages),
          );
        }
      }
      if (next.isNotEmpty && ref.mounted && _scope == scope) {
        state = {...state, ...next};
      }
    } on Object {
      // Local cache is an acceleration path; remote sync remains authoritative.
    } finally {
      if (_scope == scope) {
        _hydratedScope = scope;
      }
      _hydrationFuture = null;
    }
  }

  void put(String roomId, List<ChatMessage> messages, {bool persist = true}) {
    if (roomId.isEmpty) {
      return;
    }
    final nextMessages = _dedupeAndTrim([
      ...(state[roomId] ?? const <ChatMessage>[]),
      ...messages,
    ]);
    state = {...state, roomId: List<ChatMessage>.unmodifiable(nextMessages)};
    if (persist) {
      _schedulePersist();
    }
  }

  void _schedulePersist() {
    final key = _storageKey;
    if (key == null || state.isEmpty) {
      return;
    }
    if (_persistFuture != null) {
      _persistAgain = true;
      return;
    }
    _persistFuture = Future<void>.microtask(() async {
      try {
        do {
          _persistAgain = false;
          await _writeCurrentState(key);
        } while (_persistAgain && _storageKey == key);
      } on Object {
        // Keep memory cache even if persistence is temporarily unavailable.
      } finally {
        _persistFuture = null;
        if (_persistAgain) {
          _persistAgain = false;
          _schedulePersist();
        }
      }
    });
  }

  Future<void> flush() async {
    final running = _persistFuture;
    if (running != null) {
      await running;
    }
    final key = _storageKey;
    if (key == null || state.isEmpty) {
      return;
    }
    await _writeCurrentState(key);
  }

  Future<void> _writeCurrentState(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, Object?>{};
    var serializedChars = 2;
    for (final entry in state.entries.take(_maxPersistedRooms)) {
      final roomMessages = [
        for (final message in entry.value) _messageToCacheJson(message),
      ];
      if (roomMessages.isEmpty) {
        continue;
      }
      final roomJson = jsonEncode(roomMessages);
      final nextSize = serializedChars + entry.key.length + roomJson.length + 8;
      if (encoded.isNotEmpty && nextSize > _maxPersistedChars) {
        break;
      }
      encoded[entry.key] = roomMessages;
      serializedChars = nextSize;
    }
    if (encoded.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, jsonEncode(encoded));
  }

  static List<ChatMessage> _dedupeAndTrim(List<ChatMessage> messages) {
    if (messages.isEmpty) {
      return const [];
    }
    final byKey = <String, ChatMessage>{};
    for (final message in messages) {
      byKey[chatMessageCacheKey(message)] = message;
    }
    final nextMessages = byKey.values.toList()
      ..sort((a, b) {
        final aSentAt = a.sentAt;
        final bSentAt = b.sentAt;
        if (aSentAt != null && bSentAt != null) {
          return aSentAt.compareTo(bSentAt);
        }
        if (aSentAt != null) {
          return -1;
        }
        if (bSentAt != null) {
          return 1;
        }
        return 0;
      });
    if (nextMessages.length <= _maxMessagesPerRoom) {
      return nextMessages;
    }
    return nextMessages.sublist(nextMessages.length - _maxMessagesPerRoom);
  }
}

Map<String, Object?> _messageToCacheJson(ChatMessage message) {
  return {
    'id': message.id,
    'senderId': message.senderId,
    'sender': _personToCacheJson(message.sender),
    'text': _cacheLimitedString(message.text, maxLength: 4096),
    'time': message.time,
    'isMine': message.isMine,
    'sentAt': message.sentAt?.toIso8601String(),
    'unreadCount': message.unreadCount,
    'isSystem': message.isSystem,
    'isSilent': message.isSilent,
    'isSpoiler': message.isSpoiler,
    'spoilerRevealed': message.spoilerRevealed,
    'deletedForEveryone': message.deletedForEveryone,
    'attachment': message.attachment == null
        ? null
        : _attachmentToCacheJson(message.attachment!),
    'mentions': [
      for (final mention in message.mentions)
        {'userId': mention.userId, 'displayName': mention.displayName},
    ],
  };
}

ChatMessage? _messageFromCacheJson(Map<String, dynamic> json) {
  final senderJson = json['sender'];
  final sender = senderJson is Map
      ? _personFromCacheJson(senderJson.cast<String, dynamic>())
      : null;
  final text = json['text'] as String? ?? '';
  if (sender == null || text.isEmpty) {
    return null;
  }
  final attachmentJson = json['attachment'];
  return ChatMessage(
    id: json['id'] as String?,
    senderId: json['senderId'] as String?,
    sender: sender,
    text: text,
    time: json['time'] as String? ?? '',
    isMine: json['isMine'] as bool? ?? false,
    sentAt: DateTime.tryParse(json['sentAt'] as String? ?? ''),
    unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    isSystem: json['isSystem'] as bool? ?? false,
    isSilent: json['isSilent'] as bool? ?? false,
    isSpoiler: json['isSpoiler'] as bool? ?? false,
    spoilerRevealed: json['spoilerRevealed'] as bool? ?? false,
    deletedForEveryone: json['deletedForEveryone'] as bool? ?? false,
    attachment: attachmentJson is Map
        ? _attachmentFromCacheJson(attachmentJson.cast<String, dynamic>())
        : null,
    mentions: [
      for (final item in json['mentions'] as List<dynamic>? ?? const [])
        if (item is Map)
          ChatMention(
            userId: item['userId'] as String? ?? '',
            displayName: item['displayName'] as String? ?? '',
          ),
    ],
  );
}

Map<String, Object?> _personToCacheJson(PersonProfile profile) {
  return {
    'id': profile.id,
    'name': profile.name,
    'nickname': profile.nickname,
    'phoneNumber': profile.phoneNumber,
    'email': profile.email,
    'companyName': profile.companyName,
    'position': profile.position,
    'role': profile.role,
    'department': profile.department,
    'birthDate': profile.birthDate?.toIso8601String(),
    'color': colorToHex(profile.color),
    'imageUrl': _cacheLimitedString(
      profile.imageUrl,
      maxLength: 2048,
      dropDataUri: true,
    ),
    'status': profile.status,
    'statusMessage': profile.statusMessage,
    'profileBackgroundColor': profile.profileBackgroundColor == null
        ? null
        : colorToHex(profile.profileBackgroundColor!),
    'profileBackgroundImageUrl': _cacheLimitedString(
      profile.profileBackgroundImageUrl,
      maxLength: 2048,
      dropDataUri: true,
    ),
    'blocked': profile.blocked,
  };
}

String? _cacheLimitedString(
  String? value, {
  required int maxLength,
  bool dropDataUri = false,
}) {
  if (value == null) {
    return null;
  }
  if (dropDataUri && value.startsWith('data:')) {
    return null;
  }
  if (value.length <= maxLength) {
    return value;
  }
  return value.substring(0, maxLength);
}

PersonProfile? _personFromCacheJson(Map<String, dynamic> json) {
  final name = json['name'] as String? ?? '';
  if (name.isEmpty) {
    return null;
  }
  return PersonProfile(
    id: json['id'] as String?,
    name: name,
    nickname: json['nickname'] as String?,
    phoneNumber: json['phoneNumber'] as String?,
    email: json['email'] as String?,
    companyName: json['companyName'] as String?,
    position: json['position'] as String?,
    role: json['role'] as String?,
    department: json['department'] as String?,
    birthDate: DateTime.tryParse(json['birthDate'] as String? ?? ''),
    color: avatarColorFromHex(json['color'] as String?),
    imageUrl: json['imageUrl'] as String?,
    status: json['status'] as String?,
    statusMessage: json['statusMessage'] as String?,
    profileBackgroundColor: json['profileBackgroundColor'] == null
        ? null
        : avatarColorFromHex(json['profileBackgroundColor'] as String?),
    profileBackgroundImageUrl: json['profileBackgroundImageUrl'] as String?,
    blocked: json['blocked'] as bool? ?? false,
  );
}

Map<String, Object?> _attachmentToCacheJson(ChatAttachment attachment) {
  return {
    'id': attachment.id,
    'fileName': attachment.fileName,
    'contentType': attachment.contentType,
    'size': attachment.size,
    'downloadUrl': attachment.downloadUrl,
    'groupId': attachment.groupId,
  };
}

ChatAttachment? _attachmentFromCacheJson(Map<String, dynamic> json) {
  final id = json['id'] as String? ?? '';
  if (id.isEmpty) {
    return null;
  }
  return ChatAttachment(
    id: id,
    fileName: json['fileName'] as String? ?? '',
    contentType: json['contentType'] as String? ?? '',
    size: (json['size'] as num?)?.toInt() ?? 0,
    downloadUrl: json['downloadUrl'] as String? ?? '',
    groupId: json['groupId'] as String? ?? '',
  );
}

String chatMessageCacheKey(ChatMessage message) {
  if (message.id != null && message.id!.isNotEmpty) {
    return message.id!;
  }
  return '${message.senderId ?? message.sender.name}-${message.sentAt?.toIso8601String() ?? message.time}-${message.text}';
}

class ChatRoomPanel extends ConsumerStatefulWidget {
  const ChatRoomPanel({
    required this.room,
    required this.onClose,
    this.mobileLayout = false,
    super.key,
  });

  final ChatRoom room;
  final VoidCallback onClose;
  final bool mobileLayout;

  @override
  ConsumerState<ChatRoomPanel> createState() => _ChatRoomPanelState();
}

class _ChatRoomPanelState extends ConsumerState<ChatRoomPanel> {
  static const int _messagePageSize = 80;
  static const int _compactInitialMessagePageSize = 40;
  static const int _largeRoomInitialMessagePageSize = 96;
  static const Duration _cachedRemoteSyncDelay = Duration(milliseconds: 1200);

  late ChatRoom _room;
  late List<ChatMessage> _messages;
  ChatMessage? _noticeMessage;
  final Set<String> _messageIds = {};
  final Set<String> _locallyHiddenMessageIds = {};
  StreamSubscription<ChatMessageDto>? _realtimeSubscription;
  StreamSubscription<ChatReadStateDto>? _readStateSubscription;
  StreamSubscription<ChatTypingEventDto>? _typingSubscription;
  ChatRealtimeClient? _realtimeClient;
  Timer? _cachedRemoteSyncTimer;
  final Map<String, _TypingParticipant> _typingParticipants = {};
  final Map<String, Timer> _typingExpiryTimers = {};
  bool _isLoadingMessages = false;
  bool _isLoadingOlderMessages = false;
  bool _hasMoreOlderMessages = true;
  bool _isFileDragActive = false;
  bool _isFileDropUploading = false;
  String? _loadingRoomId;
  String? _loadedFocusMessageId;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _searchOpen = false;
  String _searchQuery = '';
  List<String> _searchMatchIds = const [];
  int _searchMatchIndex = 0;
  _ChatSidePanelMode? _sidePanelMode;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _noticeMessage = _noticeFromRoom(_room);
    _loadedFocusMessageId = null;
    _messages = _initialMessagesFor(_room);
    _rememberMessageIds(_messages);
    WindowControl.setFileDropHandler(
      onDragState: _handleNativeFileDragState,
      onDrop: _handleNativeFileDrop,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_restoreLocalMessagesThenLoadRemote());
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
    _cancelCachedRemoteSync();
    _stopRealtime();
    _clearTypingParticipants();
    _room = widget.room;
    _noticeMessage = _noticeFromRoom(_room);
    _messages = _initialMessagesFor(_room);
    _hasMoreOlderMessages = true;
    _isLoadingOlderMessages = false;
    _searchOpen = false;
    _searchQuery = '';
    _searchController.clear();
    _searchMatchIds = const [];
    _searchMatchIndex = 0;
    _sidePanelMode = null;
    _messageIds
      ..clear()
      ..addAll(_messages.map(_messageKey));
    unawaited(_restoreLocalMessagesThenLoadRemote());
  }

  List<ChatMessage> _initialMessagesFor(ChatRoom room) {
    final cachedMessages = ref
        .read(chatMessageMemoryCacheProvider.notifier)
        .messagesFor(room.id);
    if (cachedMessages.isNotEmpty) {
      return _latestMessagePage(room, cachedMessages);
    }
    final session = ref.read(authControllerProvider).value?.session;
    if (session != null && session.accessToken.isNotEmpty && !room.isDraft) {
      return const [];
    }
    return messagesFor(room);
  }

  List<ChatMessage> _latestMessagePage(
    ChatRoom room,
    List<ChatMessage> messages,
  ) {
    final pageSize = room.displayParticipantCount >= 10
        ? _largeRoomInitialMessagePageSize
        : _compactInitialMessagePageSize;
    if (messages.length <= pageSize) {
      return messages;
    }
    return messages.sublist(messages.length - pageSize);
  }

  Future<void> _restoreLocalMessagesThenLoadRemote() async {
    await _loadLocallyHiddenMessageIds();
    if (!mounted) {
      return;
    }
    _applyLocalHiddenMessages();
    await _restoreLocalMessagesForCurrentRoom();
    if (!mounted) {
      return;
    }
    final focusedMessageId = ref.read(focusedChatMessageIdProvider);
    if (_messages.isNotEmpty &&
        (focusedMessageId == null || focusedMessageId.isEmpty)) {
      _scheduleCachedRemoteSync(_room.id);
      return;
    }
    await _loadRemoteMessages();
  }

  Future<void> _loadLocallyHiddenMessageIds() async {
    final key = _localHiddenMessagesStorageKey();
    if (key == null) {
      _locallyHiddenMessageIds.clear();
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = prefs.getStringList(key) ?? const <String>[];
      _locallyHiddenMessageIds
        ..clear()
        ..addAll(values.where((value) => value.trim().isNotEmpty));
    } on Object {
      _locallyHiddenMessageIds.clear();
    }
  }

  String? _localHiddenMessagesStorageKey() {
    final session = ref.read(authControllerProvider).value?.session;
    final userId = session?.user.id.trim();
    if (userId == null || userId.isEmpty || _room.id.trim().isEmpty) {
      return null;
    }
    return 'ava.chat.hidden_messages.v1.$userId.${_room.id}';
  }

  void _applyLocalHiddenMessages() {
    if (_locallyHiddenMessageIds.isEmpty || _messages.isEmpty) {
      return;
    }
    final filtered = [
      for (final message in _messages)
        if (!_locallyHiddenMessageIds.contains(_messageKey(message))) message,
    ];
    if (filtered.length == _messages.length) {
      return;
    }
    setState(() {
      _messages = filtered;
      _rememberMessageIds(_messages);
    });
  }

  Future<void> _restoreLocalMessagesForCurrentRoom() async {
    if (_messages.isNotEmpty || _room.isDraft) {
      return;
    }
    final requestRoomId = _room.id;
    final cachedMessages = await ref
        .read(chatMessageMemoryCacheProvider.notifier)
        .hydrateRoom(requestRoomId);
    if (!mounted || _room.id != requestRoomId || cachedMessages.isEmpty) {
      return;
    }
    final visibleMessages = _filterLocallyHiddenMessages(
      _latestMessagePage(_room, cachedMessages),
    );
    setState(() {
      _messages = visibleMessages;
      _rememberMessageIds(_messages);
      _isLoadingMessages = false;
      _hasMoreOlderMessages =
          cachedMessages.length > visibleMessages.length ||
          visibleMessages.length >= _messagePageSize;
    });
  }

  @override
  void dispose() {
    _cancelCachedRemoteSync();
    _stopRealtime();
    _clearTypingParticipants();
    _searchFocusNode.dispose();
    _searchController.dispose();
    WindowControl.setFileDropHandler();
    unawaited(WindowControl.setMessengerOpacity(1));
    super.dispose();
  }

  void _scheduleCachedRemoteSync(String roomId) {
    _cancelCachedRemoteSync();
    _cachedRemoteSyncTimer = Timer(_cachedRemoteSyncDelay, () {
      _cachedRemoteSyncTimer = null;
      if (!mounted || _room.id != roomId) {
        return;
      }
      unawaited(_loadRemoteMessages());
    });
  }

  void _cancelCachedRemoteSync() {
    _cachedRemoteSyncTimer?.cancel();
    _cachedRemoteSyncTimer = null;
  }

  Future<void> _loadRemoteMessages() async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      return;
    }
    if (_room.isDraft) {
      return;
    }
    final requestRoomId = _room.id;
    if (_loadingRoomId == requestRoomId) {
      return;
    }
    _loadingRoomId = requestRoomId;

    _startRealtime(session.accessToken, session.user.id);
    if (_isLoadingMessages) {
      setState(() {
        _isLoadingMessages = false;
      });
    }

    try {
      final focusedMessageId = ref.read(focusedChatMessageIdProvider);
      final effectiveMessages =
          focusedMessageId != null && focusedMessageId.isNotEmpty
          ? await ref
                .read(chatApiProvider)
                .messagesAround(
                  accessToken: session.accessToken,
                  roomCode: requestRoomId,
                  messageId: focusedMessageId,
                  before: 40,
                  after: 40,
                )
          : await ref
                .read(chatApiProvider)
                .messages(
                  accessToken: session.accessToken,
                  roomCode: requestRoomId,
                  limit: _messagePageSize,
                );
      if (!mounted || _room.id != requestRoomId) {
        return;
      }

      final mapped = [
        for (final message in effectiveMessages)
          _messageFromDto(message, currentUserId: session.user.id),
      ];
      final merged = _filterLocallyHiddenMessages(_mergeRemoteMessages(mapped));
      setState(() {
        _messages = merged;
        _messageIds
          ..clear()
          ..addAll(merged.map(_messageKey));
        _isLoadingMessages = false;
        _loadedFocusMessageId = focusedMessageId;
        _hasMoreOlderMessages =
            effectiveMessages.length >=
            (focusedMessageId != null && focusedMessageId.isNotEmpty
                ? 41
                : _messagePageSize);
      });
      _cacheCurrentMessages();
      _refreshSearchMatches(keepIndex: true);
      unawaited(_markRoomRead(session.accessToken));
    } on Object {
      if (mounted) {
        setState(() {
          _isLoadingMessages = false;
        });
      }
    } finally {
      if (_loadingRoomId == requestRoomId) {
        _loadingRoomId = null;
      }
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoadingOlderMessages || !_hasMoreOlderMessages || _room.isDraft) {
      return;
    }
    ChatMessage? boundaryMessage;
    for (final message in _messages) {
      final id = message.id;
      if (id != null && id.isNotEmpty && message.sentAt != null) {
        boundaryMessage = message;
        break;
      }
    }
    final boundaryMessageId = boundaryMessage?.id;
    if (boundaryMessageId == null || boundaryMessageId.isEmpty) {
      setState(() {
        _hasMoreOlderMessages = false;
      });
      return;
    }
    if (_prependOlderMessagesFromCache(boundaryMessage!)) {
      return;
    }

    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      setState(() {
        _hasMoreOlderMessages = false;
      });
      return;
    }

    final requestRoomId = _room.id;
    setState(() {
      _isLoadingOlderMessages = true;
    });

    try {
      final olderDtos = await ref
          .read(chatApiProvider)
          .messagesBefore(
            accessToken: session.accessToken,
            roomCode: requestRoomId,
            messageId: boundaryMessageId,
            limit: _messagePageSize,
          );
      if (!mounted || _room.id != requestRoomId) {
        return;
      }

      final currentKeys = _messages.map(_messageKey).toSet();
      final mapped = [
        for (final message in olderDtos)
          _messageFromDto(message, currentUserId: session.user.id),
      ];
      final visibleOlder = _filterLocallyHiddenMessages(mapped);
      final addedVisibleMessage = visibleOlder.any(
        (message) => !currentKeys.contains(_messageKey(message)),
      );
      final merged = _filterLocallyHiddenMessages(_mergeRemoteMessages(mapped));
      setState(() {
        _messages = merged;
        _messageIds
          ..clear()
          ..addAll(merged.map(_messageKey));
        _hasMoreOlderMessages =
            olderDtos.length >= _messagePageSize && addedVisibleMessage;
      });
      _cacheCurrentMessages();
      _refreshSearchMatches(keepIndex: true);
    } on Object {
      // Keep the current page usable; the next top-scroll can retry.
    } finally {
      if (mounted && _room.id == requestRoomId) {
        setState(() {
          _isLoadingOlderMessages = false;
        });
      }
    }
  }

  bool _prependOlderMessagesFromCache(ChatMessage boundaryMessage) {
    final cachedMessages = ref
        .read(chatMessageMemoryCacheProvider.notifier)
        .messagesFor(_room.id);
    if (cachedMessages.isEmpty) {
      return false;
    }
    final boundaryKey = _messageKey(boundaryMessage);
    final boundaryIndex = cachedMessages.indexWhere(
      (message) => _messageKey(message) == boundaryKey,
    );
    if (boundaryIndex <= 0) {
      return false;
    }
    final start = math.max(0, boundaryIndex - _messagePageSize);
    final cachedOlderMessages = cachedMessages.sublist(start, boundaryIndex);
    if (cachedOlderMessages.isEmpty) {
      return false;
    }
    final currentKeys = _messages.map(_messageKey).toSet();
    final visibleOlderMessages = _filterLocallyHiddenMessages(
      cachedOlderMessages,
    );
    final addedVisibleMessage = visibleOlderMessages.any(
      (message) => !currentKeys.contains(_messageKey(message)),
    );
    if (!addedVisibleMessage) {
      return false;
    }
    final merged = _filterLocallyHiddenMessages(
      _mergeRemoteMessages(cachedOlderMessages),
    );
    setState(() {
      _messages = merged;
      _messageIds
        ..clear()
        ..addAll(merged.map(_messageKey));
      _hasMoreOlderMessages = true;
    });
    _cacheCurrentMessages();
    _refreshSearchMatches(keepIndex: true);
    return true;
  }

  List<ChatMessage> _mergeRemoteMessages(List<ChatMessage> remoteMessages) {
    if (_messages.isEmpty) {
      return remoteMessages;
    }
    final byKey = <String, ChatMessage>{};
    for (final message in _messages) {
      byKey[_messageKey(message)] = message;
    }
    for (final message in remoteMessages) {
      byKey[_messageKey(message)] = message;
    }
    final merged = byKey.values.toList()
      ..sort((a, b) {
        final aSentAt = a.sentAt;
        final bSentAt = b.sentAt;
        if (aSentAt != null && bSentAt != null) {
          return aSentAt.compareTo(bSentAt);
        }
        if (aSentAt != null) {
          return -1;
        }
        if (bSentAt != null) {
          return 1;
        }
        return 0;
      });
    return merged;
  }

  List<ChatMessage> _filterLocallyHiddenMessages(List<ChatMessage> messages) {
    if (_locallyHiddenMessageIds.isEmpty || messages.isEmpty) {
      return messages;
    }
    return [
      for (final message in messages)
        if (!_locallyHiddenMessageIds.contains(_messageKey(message))) message,
    ];
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

    final sentAt = DateTime.now();
    final pendingId =
        'pending-${_room.id}-${sentAt.microsecondsSinceEpoch}-${trimmed.hashCode}';
    final pendingUnreadCount = _pendingUnreadCount(
      currentUserId: session.user.id,
    );
    _appendMessage(
      ChatMessage(
        id: pendingId,
        senderId: session.user.id,
        sender: _currentUserProfile,
        text: trimmed,
        time: formatChatClockTime(sentAt),
        isMine: true,
        sentAt: sentAt,
        unreadCount: pendingUnreadCount,
        isSilent: options.silent,
        isSpoiler: options.spoiler,
        mentions: [
          for (final mention in options.mentions)
            ChatMention(
              userId: mention.userId,
              displayName: mention.displayName,
            ),
        ],
      ),
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

    unawaited(
      _confirmSentMessage(
        pendingKey: pendingId,
        roomCode: _room.id,
        accessToken: session.accessToken,
        currentUserId: session.user.id,
        content: trimmed,
        options: options,
      ),
    );
  }

  int _pendingUnreadCount({required String currentUserId}) {
    if (_room.isSelfChat) {
      return 0;
    }
    final participantCount = _room.participantCount;
    if (participantCount != null && participantCount > 0) {
      return math.max(0, participantCount - 1);
    }
    if (_room.isDirectChat) {
      return 1;
    }
    var currentUserIncluded = false;
    var memberCount = 0;
    for (final member in _room.members) {
      final memberId = member.id?.trim();
      if (memberId != null &&
          memberId.isNotEmpty &&
          memberId == currentUserId) {
        currentUserIncluded = true;
      }
      memberCount++;
    }
    return math.max(0, memberCount - (currentUserIncluded ? 1 : 0));
  }

  Future<void> _confirmSentMessage({
    required String pendingKey,
    required String roomCode,
    required String accessToken,
    required String currentUserId,
    required String content,
    required _SendOptions options,
  }) async {
    try {
      var targetRoomCode = roomCode;
      if (_room.isDraft) {
        final canSendRemote = await _resolveDraftRoom(
          accessToken: accessToken,
          loadMessages: false,
        );
        if (!canSendRemote || !mounted) {
          throw StateError('Unable to prepare chat room.');
        }
        targetRoomCode = _room.id;
        ref
            .read(chatRoomsProvider.notifier)
            .messagePosted(
              targetRoomCode,
              content,
              DateTime.now(),
              fallbackRoom: _room,
              spoiler: options.spoiler,
            );
      }
      final message = await ref
          .read(chatApiProvider)
          .send(
            accessToken: accessToken,
            roomCode: targetRoomCode,
            content: content,
            silent: options.silent,
            spoiler: options.spoiler,
            mentions: options.mentions,
          );
      if (!mounted || _room.id != targetRoomCode) {
        return;
      }
      final sentAt = message.sentAt ?? DateTime.now();
      final pendingUnreadCount = _messageByKey(pendingKey)?.unreadCount ?? 0;
      final confirmedMessage = _messageFromDto(
        message,
        currentUserId: currentUserId,
      );
      _replaceMessage(
        pendingKey,
        pendingUnreadCount > confirmedMessage.unreadCount
            ? confirmedMessage.copyWith(unreadCount: pendingUnreadCount)
            : confirmedMessage,
      );
      ref
          .read(chatRoomsProvider.notifier)
          .messagePosted(
            targetRoomCode,
            content,
            sentAt,
            fallbackRoom: _room,
            spoiler: options.spoiler,
          );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _removeMessage(pendingKey);
      showAvaToast(context, authErrorMessage(error));
    }
  }

  Future<bool> _resolveDraftRoom({
    required String accessToken,
    bool loadMessages = true,
  }) async {
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
      ref.read(chatRoomsProvider.notifier).upsert(resolvedRoom);
      ref.read(selectedChatRoomProvider.notifier).open(resolvedRoom);
      if (loadMessages) {
        await _loadRemoteMessages();
      }
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
            chatMessageListPreview(message),
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
    _cacheCurrentMessages();
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

  List<PersonProfile> _mentionMembersFor(List<PersonProfile> companyProfiles) {
    final merged = <PersonProfile>[];
    final seen = <String>{};

    void add(PersonProfile profile) {
      final key = profile.identityKey.trim();
      if (key.isEmpty || !seen.add(key)) {
        return;
      }
      merged.add(profile);
    }

    for (final member in _room.members) {
      add(member);
    }

    final hasSelectableMember = merged.any((profile) {
      final id = profile.id;
      return id != null && id.isNotEmpty;
    });
    if (!_room.isDirectChat || !hasSelectableMember) {
      for (final profile in companyProfiles) {
        add(profile);
      }
    }

    return merged;
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
    if (_locallyHiddenMessageIds.contains(key)) {
      return;
    }
    if (!_messageIds.add(key)) {
      final attachment = message.attachment;
      ChatMessage? existing;
      for (final item in _messages) {
        if (_messageKey(item) == key) {
          existing = item;
          break;
        }
      }
      final shouldReplace =
          message.deletedForEveryone ||
          existing == null ||
          existing.text != message.text ||
          existing.unreadCount != message.unreadCount ||
          existing.deletedForEveryone != message.deletedForEveryone ||
          existing.attachment?.id != attachment?.id ||
          (attachment != null &&
              (attachment.hasFreshLocalFile || attachment.transferInProgress));
      if (shouldReplace) {
        setState(() {
          _messages = [
            for (final existing in _messages)
              if (_messageKey(existing) == key) message else existing,
          ];
        });
        _cacheCurrentMessages();
      }
      return;
    }
    setState(() {
      _messages = [..._messages, message];
    });
    _cacheCurrentMessages();
    _refreshSearchMatches(keepIndex: true);
  }

  ChatMessage? _messageByKey(String key) {
    for (final message in _messages) {
      if (_messageKey(message) == key) {
        return message;
      }
    }
    return null;
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
    _cacheCurrentMessages();
    _refreshSearchMatches(keepIndex: true);
  }

  void _removeMessage(String key) {
    if (!_messageIds.contains(key)) {
      return;
    }
    final nextMessages = [
      for (final message in _messages)
        if (_messageKey(message) != key) message,
    ];
    setState(() {
      _messages = nextMessages;
      _messageIds
        ..clear()
        ..addAll(nextMessages.map(_messageKey));
    });
    _cacheCurrentMessages();
    _refreshSearchMatches(keepIndex: true);
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
    _cacheCurrentMessages();
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

  void _cacheCurrentMessages() {
    if (_room.isDraft || _messages.isEmpty) {
      return;
    }
    ref.read(chatMessageMemoryCacheProvider.notifier).put(_room.id, _messages);
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
      deletedForEveryone: message.deletedForEveryone,
      attachment: message.deletedForEveryone
          ? null
          : _attachmentFromDto(message.attachment),
      mentions: [
        for (final mention in message.mentions)
          ChatMention(userId: mention.userId, displayName: mention.displayName),
      ],
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

  Future<void> _attachGalleryImages() async {
    if (!_canSendMessages) {
      return;
    }
    try {
      final images = await ImagePicker().pickMultiImage(imageQuality: 92);
      if (!mounted || images.isEmpty) {
        return;
      }
      final files = <_SelectedUploadFile>[];
      for (final image in images) {
        final source = File(image.path);
        if (!await source.exists()) {
          continue;
        }
        files.add(
          _SelectedUploadFile(
            path: image.path,
            name: image.name.isEmpty
                ? image.path.split(RegExp(r'[\\/]')).last
                : image.name,
            size: await source.length(),
          ),
        );
      }
      await _sendAttachments(files);
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    }
  }

  Future<void> _attachGalleryVideo() async {
    if (!_canSendMessages) {
      return;
    }
    try {
      final video = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (!mounted || video == null) {
        return;
      }
      final source = File(video.path);
      if (!await source.exists()) {
        return;
      }
      await _sendAttachments([
        _SelectedUploadFile(
          path: video.path,
          name: video.name.isEmpty
              ? video.path.split(RegExp(r'[\\/]')).last
              : video.name,
          size: await source.length(),
        ),
      ]);
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    }
  }

  Future<void> _captureCameraImage() async {
    if (!_canSendMessages) {
      return;
    }
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
      if (!mounted || image == null) {
        return;
      }
      final source = File(image.path);
      if (!await source.exists()) {
        return;
      }
      if (!mounted) {
        return;
      }
      final shouldSend = await showDialog<bool>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.48),
        builder: (_) => _CameraCaptureConfirmDialog(path: image.path),
      );
      if (!mounted || shouldSend != true) {
        return;
      }
      await _sendAttachments([
        _SelectedUploadFile(
          path: image.path,
          name: image.name.isEmpty
              ? image.path.split(RegExp(r'[\\/]')).last
              : image.name,
          size: await source.length(),
        ),
      ]);
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    }
  }

  Future<void> _sendVoiceMessage(_SelectedUploadFile file) async {
    if (!_canSendMessages) {
      return;
    }
    await _sendAttachments([file]);
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
    if (_isFileDropUploading) {
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
      showAvaToast(
        context,
        '\uB85C\uADF8\uC778\uC774 \uD544\uC694\uD569\uB2C8\uB2E4.',
      );
      return;
    }
    final canSendRemote = await _resolveDraftRoom(
      accessToken: session.accessToken,
    );
    if (!canSendRemote) {
      if (mounted) {
        showAvaToast(
          context,
          '\uD604\uC7AC \uCC44\uD305\uBC29\uC5D0\uB294 \uCCA8\uBD80\uD30C\uC77C\uC744 \uBCF4\uB0BC \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.',
        );
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
              chatAttachmentPreview(file.name, _guessContentType(file.name)),
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

    if (!Platform.isWindows) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => _MobileImageViewerPage(
            messages: imageMessages,
            initialIndex: initialIndex.clamp(0, imageMessages.length - 1),
            onDeleteMessage: _deleteMessage,
          ),
        ),
      );
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
        showAvaToast(
          context,
          '\uC774\uBBF8\uC9C0\uB97C \uBD88\uB7EC\uC624\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.',
        );
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
      showAvaToast(
        context,
        '\uC774\uBBF8\uC9C0\uB97C \uC5F4 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.',
      );
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
    return chatMessageCacheKey(message);
  }

  PersonProfile get _currentUserProfile => ref.read(currentUserProfileProvider);

  void _openSearch() {
    setState(() {
      _searchOpen = true;
      _sidePanelMode = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _closeSearch() {
    setState(() {
      _searchOpen = false;
      _searchQuery = '';
      _searchMatchIds = const [];
      _searchMatchIndex = 0;
      _searchController.clear();
      _loadedFocusMessageId = null;
    });
  }

  void _updateSearch(String value) {
    final query = value.trim();
    setState(() {
      _searchQuery = query;
    });
    _refreshSearchMatches();
  }

  void _refreshSearchMatches({bool keepIndex = false}) {
    final query = _searchQuery.toLowerCase();
    if (query.isEmpty) {
      if (_searchMatchIds.isNotEmpty) {
        setState(() {
          _searchMatchIds = const [];
          _searchMatchIndex = 0;
        });
      }
      return;
    }
    final matches = <String>[];
    for (final message in _messages.reversed) {
      final id = message.id;
      if (id == null || id.isEmpty || message.isSystem) {
        continue;
      }
      if (message.text.toLowerCase().contains(query)) {
        matches.add(id);
      }
    }
    final previousTarget = keepIndex && _searchMatchIds.isNotEmpty
        ? _searchMatchIds[_searchMatchIndex.clamp(
            0,
            _searchMatchIds.length - 1,
          )]
        : null;
    var nextIndex = 0;
    if (previousTarget != null) {
      final foundIndex = matches.indexOf(previousTarget);
      if (foundIndex >= 0) {
        nextIndex = foundIndex;
      }
    }
    setState(() {
      _searchMatchIds = matches;
      _searchMatchIndex = matches.isEmpty
          ? 0
          : nextIndex.clamp(0, matches.length - 1);
      _loadedFocusMessageId = matches.isEmpty
          ? null
          : matches[_searchMatchIndex];
    });
  }

  void _moveSearchResult(int delta) {
    if (_searchMatchIds.isEmpty) {
      return;
    }
    final nextIndex = (_searchMatchIndex + delta) % _searchMatchIds.length;
    setState(() {
      _searchMatchIndex = nextIndex < 0
          ? nextIndex + _searchMatchIds.length
          : nextIndex;
      _loadedFocusMessageId = _searchMatchIds[_searchMatchIndex];
    });
  }

  void _openSidePanel([_ChatSidePanelMode mode = _ChatSidePanelMode.info]) {
    setState(() {
      _sidePanelMode = mode;
      _searchOpen = false;
    });
  }

  void _closeSidePanel() {
    setState(() {
      _sidePanelMode = null;
    });
  }

  void _showReadyToast() {
    showAvaToast(context, '\uC900\uBE44\uC911');
  }

  bool get _isBackendDirectRoom => _room.id.startsWith('direct-');

  List<PersonProfile> _inviteCandidatesFor(List<PersonProfile> profiles) {
    final currentUser = ref.read(authControllerProvider).value?.session?.user;
    final memberIds = <String>{};
    final memberEmails = <String>{};
    final memberNames = <String>{};
    for (final member in _room.members) {
      final id = member.id;
      final email = member.email;
      if (id != null && id.isNotEmpty) {
        memberIds.add(id);
      }
      if (email != null && email.isNotEmpty) {
        memberEmails.add(email.toLowerCase());
      }
      memberNames.add(member.name.toLowerCase());
    }
    if (currentUser != null) {
      memberIds.add(currentUser.id);
      memberEmails.add(currentUser.email.toLowerCase());
      memberNames.add(currentUser.displayName.toLowerCase());
    }

    return [
      for (final profile in profiles)
        if (!_profileMatchesAny(
          profile,
          ids: memberIds,
          emails: memberEmails,
          names: memberNames,
        ))
          profile,
    ];
  }

  bool _profileMatchesAny(
    PersonProfile profile, {
    required Set<String> ids,
    required Set<String> emails,
    required Set<String> names,
  }) {
    final id = profile.id;
    final email = profile.email;
    if (id != null && id.isNotEmpty && ids.contains(id)) {
      return true;
    }
    if (email != null &&
        email.isNotEmpty &&
        emails.contains(email.toLowerCase())) {
      return true;
    }
    return names.contains(profile.name.toLowerCase());
  }

  Future<void> _showInviteMembersDialog() async {
    var profiles =
        ref.read(userProfilesProvider).value ?? const <PersonProfile>[];
    if (profiles.isEmpty) {
      try {
        profiles = await ref.read(userProfilesProvider.future);
      } on Object {
        profiles = const <PersonProfile>[];
      }
    }
    if (!mounted) {
      return;
    }
    final candidates = _inviteCandidatesFor(profiles);
    if (candidates.isEmpty) {
      showAvaToast(
        context,
        '\uCD08\uB300\uD560 \uC0AC\uC6A9\uC790\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.',
      );
      return;
    }
    final createsNewGroup = _isBackendDirectRoom;
    final result = await showDialog<_InviteMembersResult>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => _InviteMembersDialog(
        users: candidates,
        showTitleField: createsNewGroup,
      ),
    );
    if (!mounted || result == null || result.userIds.isEmpty) {
      return;
    }
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      showAvaToast(
        context,
        '\uB85C\uADF8\uC778 \uD6C4 \uC0AC\uC6A9\uD574\uC8FC\uC138\uC694.',
      );
      return;
    }
    try {
      final remoteRoom = await ref
          .read(chatApiProvider)
          .inviteRoomMembers(
            accessToken: session.accessToken,
            roomCode: _room.id,
            targetUserIds: result.userIds,
            title: result.title,
          );
      final updatedRoom = ref
          .read(chatRoomsProvider.notifier)
          .roomFromRemoteRoom(remoteRoom);
      if (!mounted) {
        return;
      }
      setState(() {
        _room = updatedRoom;
        _noticeMessage = _noticeFromRoom(updatedRoom);
      });
      ref.read(chatRoomsProvider.notifier).upsert(updatedRoom);
      if (createsNewGroup) {
        ref.read(selectedChatRoomProvider.notifier).open(updatedRoom);
        showAvaToast(
          context,
          '\uC0C8 \uCC44\uD305\uBC29\uC744 \uB9CC\uB4E4\uC5C8\uC2B5\uB2C8\uB2E4.',
        );
      } else {
        ref.read(selectedChatRoomProvider.notifier).replaceIfOpen(updatedRoom);
        showAvaToast(context, '\uCD08\uB300\uD588\uC2B5\uB2C8\uB2E4.');
      }
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    }
  }

  Future<void> _leaveCurrentRoom() async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty || _room.isDraft) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => _LeaveRoomConfirmDialog(roomTitle: _room.title),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref
          .read(chatApiProvider)
          .leaveRoom(accessToken: session.accessToken, roomCode: _room.id);
      final leftAt = DateTime.now();
      _appendMessage(
        ChatMessage(
          id: 'leave-${session.user.id}-${leftAt.microsecondsSinceEpoch}',
          senderId: session.user.id,
          sender: _currentUserProfile,
          text:
              '${_currentUserProfile.name}\uB2D8\uC774 \uCC44\uD305\uBC29\uC744 \uB098\uAC14\uC2B5\uB2C8\uB2E4',
          time: formatChatClockTime(leftAt),
          isMine: false,
          sentAt: leftAt,
          isSystem: true,
        ),
      );
      ref.read(chatRoomsProvider.notifier).remove(_room.id);
      if (mounted) {
        widget.onClose();
      }
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    }
  }

  Future<void> _deleteMessage(
    ChatMessage message, {
    _MessageDeleteMode? mode,
  }) async {
    final selectedMode = mode ?? await _selectDeleteMode(message);
    if (selectedMode == null || !mounted) {
      return;
    }
    if (selectedMode == _MessageDeleteMode.forMe) {
      await _hideMessageForMe(message);
      if (mounted) {
        showAvaToast(
          context,
          '\uB098\uC5D0\uAC8C\uC11C\uB9CC \uC0AD\uC81C\uD588\uC2B5\uB2C8\uB2E4.',
        );
      }
      return;
    }
    await _deleteMessageForEveryone(message);
  }

  Future<_MessageDeleteMode?> _selectDeleteMode(ChatMessage message) async {
    if (!message.isMine) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.28),
        builder: (_) => _MessageDeleteForMeDialog(messageLabel: message.text),
      );
      return confirmed == true ? _MessageDeleteMode.forMe : null;
    }
    return showDialog<_MessageDeleteMode>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (_) => const _MessageDeleteModeDialog(),
    );
  }

  Future<void> _hideMessageForMe(ChatMessage message) async {
    final key = _messageKey(message);
    _locallyHiddenMessageIds.add(key);
    setState(() {
      _messages = [
        for (final item in _messages)
          if (_messageKey(item) != key) item,
      ];
      _rememberMessageIds(_messages);
    });
    _cacheCurrentMessages();
    final storageKey = _localHiddenMessagesStorageKey();
    if (storageKey == null) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        storageKey,
        _locallyHiddenMessageIds.toList(growable: false),
      );
    } on Object {
      // The in-memory deletion still applies for the active session.
    }
  }

  Future<void> _deleteMessageForEveryone(ChatMessage message) async {
    final messageId = message.id;
    final session = ref.read(authControllerProvider).value?.session;
    if (messageId == null ||
        messageId.isEmpty ||
        messageId.startsWith('local-') ||
        messageId.startsWith('pending-') ||
        session == null ||
        session.accessToken.isEmpty ||
        _room.isDraft) {
      showAvaToast(
        context,
        '\uC774 \uBA54\uC2DC\uC9C0\uB294 \uBAA8\uB450\uC5D0\uAC8C\uC11C \uC0AD\uC81C\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.',
      );
      return;
    }
    try {
      final deleted = await ref
          .read(chatApiProvider)
          .deleteMessageForEveryone(
            accessToken: session.accessToken,
            roomCode: _room.id,
            messageId: messageId,
          );
      if (!mounted) {
        return;
      }
      final mapped = _messageFromDto(deleted, currentUserId: session.user.id);
      _replaceMessage(_messageKey(message), mapped);
      ref
          .read(chatRoomsProvider.notifier)
          .messagePosted(
            _room.id,
            '\uC0AD\uC81C\uB41C \uBA54\uC2DC\uC9C0\uC785\uB2C8\uB2E4',
            mapped.sentAt ?? DateTime.now(),
            fallbackRoom: _room,
          );
      showAvaToast(
        context,
        '\uBAA8\uB450\uC5D0\uAC8C\uC11C \uC0AD\uC81C\uD588\uC2B5\uB2C8\uB2E4.',
      );
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    }
  }

  Future<void> _showMessageContextMenu(
    ChatMessage message,
    Offset position,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final result = await showMenu<String>(
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

    if (!mounted || result == null) {
      return;
    }

    switch (result) {
      case 'notice':
        setState(() {
          _noticeMessage = message;
        });
        final notice = _noticeFromMessage(message);
        ref.read(chatRoomsProvider.notifier).noticeSet(_room.id, notice);
        await _persistNotice(message);
      case 'copy':
        if (message.text.trim().isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: message.text));
          if (mounted) {
            showAvaToast(
              context,
              '\uBA54\uC2DC\uC9C0\uB97C \uBCF5\uC0AC\uD588\uC2B5\uB2C8\uB2E4.',
            );
          }
        }
      case 'delete':
        await _deleteMessage(message);
      case 'share':
        final attachment = message.attachment;
        if (attachment != null) {
          await _showAttachmentShareSheet(context, ref, attachment);
        } else if (message.text.trim().isNotEmpty) {
          await _showTextShareSheet(context, ref, message.text.trim());
        }
      default:
        break;
    }
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
    final authState = ref.watch(authControllerProvider);
    final session = authState.value?.session;
    if (session != null &&
        session.accessToken.isNotEmpty &&
        !_room.isDraft &&
        _messages.isEmpty &&
        _loadingRoomId != _room.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _messages.isEmpty && _loadingRoomId != _room.id) {
          _loadRemoteMessages();
        }
      });
    }
    final companyProfiles = ref.watch(userProfilesProvider).value ?? const [];
    final mentionMembers = _mentionMembersFor(companyProfiles);
    final keyboardBottomInset = widget.mobileLayout
        ? MediaQuery.viewInsetsOf(context).bottom
        : 0.0;
    final panel = KeyedSubtree(
      key: widget.mobileLayout ? null : ValueKey('chat-panel-${_room.id}'),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: _chatBackground,
              border: widget.mobileLayout
                  ? null
                  : const Border(left: BorderSide(color: Color(0xFFD1D1D1))),
            ),
            child: Column(
              children: [
                if (_searchOpen && widget.mobileLayout)
                  _ChatRoomSearchBar(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    mobileLayout: widget.mobileLayout,
                    matchCount: _searchMatchIds.length,
                    currentIndex: _searchMatchIds.isEmpty
                        ? 0
                        : _searchMatchIndex + 1,
                    onChanged: _updateSearch,
                    onPrevious: () => _moveSearchResult(1),
                    onNext: () => _moveSearchResult(-1),
                    onClose: _closeSearch,
                  )
                else
                  _ChatHeader(
                    room: _room,
                    onClose: widget.onClose,
                    mobileLayout: widget.mobileLayout,
                    onSearch: _openSearch,
                    onOpenMenu: () => _openSidePanel(),
                  ),
                if (_searchOpen && !widget.mobileLayout)
                  _ChatRoomSearchBar(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    mobileLayout: widget.mobileLayout,
                    matchCount: _searchMatchIds.length,
                    currentIndex: _searchMatchIds.isEmpty
                        ? 0
                        : _searchMatchIndex + 1,
                    onChanged: _updateSearch,
                    onPrevious: () => _moveSearchResult(1),
                    onNext: () => _moveSearchResult(-1),
                    onClose: _closeSearch,
                  ),
                if (_noticeMessage != null)
                  _ChatNoticeCard(message: _noticeMessage!),
                Expanded(
                  child: Stack(
                    children: [
                      RepaintBoundary(
                        child: _ChatMessagesView(
                          roomId: _room.id,
                          messages: _messages,
                          focusedMessageId: _loadedFocusMessageId,
                          searchQuery: _searchQuery,
                          typingLabel: _typingLabel,
                          hasMoreOlderMessages: _hasMoreOlderMessages,
                          loadingOlderMessages: _isLoadingOlderMessages,
                          bottomViewportInset: keyboardBottomInset,
                          onLoadOlderMessages: _loadOlderMessages,
                          onMessageContextMenu: _showMessageContextMenu,
                          onOpenImages: _openImageViewer,
                          onFocusedMessageConsumed: () {
                            if (_loadedFocusMessageId != null) {
                              setState(() {
                                _loadedFocusMessageId = null;
                              });
                              ref
                                  .read(focusedChatMessageIdProvider.notifier)
                                  .clear();
                            }
                          },
                        ),
                      ),
                      if (_isLoadingMessages)
                        const Center(
                          key: ValueKey('chat-room-loading-indicator'),
                          child: SizedBox.square(
                            dimension: 48,
                            child: CircularProgressIndicator(
                              strokeWidth: 4,
                              strokeCap: StrokeCap.round,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _MessageComposer(
                  onSend: _sendMessage,
                  onAttachFiles: _showFileTransferDialog,
                  onAttachImages: _attachGalleryImages,
                  onAttachVideos: _attachGalleryVideo,
                  onCaptureCamera: _captureCameraImage,
                  onSendVoiceMessage: _sendVoiceMessage,
                  onTypingChanged: _sendTypingStatus,
                  enabled: _canSendMessages,
                  mobileLayout: widget.mobileLayout,
                  members: mentionMembers,
                  currentUserId: ref
                      .watch(authControllerProvider)
                      .value
                      ?.session
                      ?.user
                      .id,
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
          if (_sidePanelMode != null)
            Positioned.fill(
              child: _ChatSidePanelHost(
                mode: _sidePanelMode!,
                room: _room,
                messages: _messages,
                onClose: _closeSidePanel,
                onOpenMedia: () => _openSidePanel(_ChatSidePanelMode.media),
                onOpenFiles: () => _openSidePanel(_ChatSidePanelMode.files),
                onOpenLinks: () => _openSidePanel(_ChatSidePanelMode.links),
                onReady: _showReadyToast,
                onOpenAvaAi: () {
                  ref
                      .read(activeMessengerTabProvider.notifier)
                      .setTab(MessengerTab.avaAi);
                  widget.onClose();
                },
                onLeaveRoom: _leaveCurrentRoom,
                onInviteMembers: _showInviteMembersDialog,
              ),
            ),
        ],
      ),
    );
    if (!widget.mobileLayout &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return DropTarget(
        onDragEntered: (_) => _handleNativeFileDragState(true),
        onDragExited: (_) => _handleNativeFileDragState(false),
        onDragDone: (detail) {
          final paths = [
            for (final file in detail.files)
              if (file.path.isNotEmpty) file.path,
          ];
          unawaited(_handleNativeFileDrop(paths));
        },
        child: panel,
      );
    }
    return panel;
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
    return _pickAttachmentFilesPortable(context);
  }
  /*
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null || result.files.isEmpty) {
        return const [];
      }
      final files = <_SelectedUploadFile>[];
      for (final item in result.files) {
        final path = item.path;
        if (path == null || path.isEmpty) {
          continue;
        }
        final file = File(path);
        if (!await file.exists()) {
          continue;
        }
        files.add(
          _SelectedUploadFile(
            path: path,
            name: item.name.isEmpty
                ? path.split(RegExp(r'[\\/]')).last
                : item.name,
            size: item.size > 0 ? item.size : await file.length(),
          ),
        );
      }
      return files;
    } on Object catch (error) {
      if (context.mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
      return const [];
    }
    showAvaToast(context, '\uCCA8\uBD80\uD30C\uC77C\uC740 Windows\uC5D0\uC11C\uB9CC \uACBD\uB85C \uC120\uD0DD\uC744 \uC9C0\uC6D0\uD569\uB2C8\uB2E4.');
    return const [];
  */

  const script = r'''
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$dialog = New-Object System.Windows.Forms.OpenFileDialog
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

Future<List<_SelectedUploadFile>> _pickAttachmentFilesPortable(
  BuildContext context,
) async {
  try {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) {
      return const [];
    }
    final files = <_SelectedUploadFile>[];
    for (final item in result.files) {
      final path = item.path;
      if (path == null || path.isEmpty) {
        continue;
      }
      final file = File(path);
      if (!await file.exists()) {
        continue;
      }
      files.add(
        _SelectedUploadFile(
          path: path,
          name: item.name.isEmpty
              ? path.split(RegExp(r'[\\/]')).last
              : item.name,
          size: item.size > 0 ? item.size : await file.length(),
        ),
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
  if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (lowerName.endsWith('.png')) {
    return 'image/png';
  }
  if (lowerName.endsWith('.gif')) {
    return 'image/gif';
  }
  if (lowerName.endsWith('.webp')) {
    return 'image/webp';
  }
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
  if (lowerName.endsWith('.m4a')) {
    return 'audio/mp4';
  }
  if (lowerName.endsWith('.aac')) {
    return 'audio/aac';
  }
  if (lowerName.endsWith('.mp3')) {
    return 'audio/mpeg';
  }
  if (lowerName.endsWith('.wav')) {
    return 'audio/wav';
  }
  if (lowerName.endsWith('.ogg')) {
    return 'audio/ogg';
  }
  if (lowerName.endsWith('.opus')) {
    return 'audio/opus';
  }
  return 'application/octet-stream';
}

Future<String?> _pickVideoSavePath(
  BuildContext context,
  String fileName,
) async {
  if (!Platform.isWindows) {
    showAvaToast(
      context,
      '\uB3D9\uC601\uC0C1 \uC800\uC7A5\uC740 Windows\uC5D0\uC11C\uB9CC \uACBD\uB85C \uC120\uD0DD\uC744 \uC9C0\uC6D0\uD569\uB2C8\uB2E4.',
    );
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
\$dialog.Title = "Save video"
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

Future<String?> _downloadAttachmentToDownloads(
  BuildContext context,
  WidgetRef ref,
  ChatAttachment attachment,
) async {
  final sourcePath = await _downloadAttachmentToTemp(ref, attachment);
  if (sourcePath == null ||
      sourcePath.isEmpty ||
      !await File(sourcePath).exists()) {
    if (context.mounted) {
      showAvaToast(
        context,
        '\uB85C\uADF8\uC778\uC774 \uD544\uC694\uD569\uB2C8\uB2E4.',
      );
    }
    return null;
  }

  if (Platform.isAndroid) {
    return WindowControl.saveAttachmentToMediaStore(
      sourcePath: sourcePath,
      fileName: attachment.fileName,
      mimeType: attachment.contentType,
      notify: true,
    );
  }

  final downloads = await _downloadsDirectory();
  if (_isPathInDirectory(sourcePath, downloads)) {
    return sourcePath;
  }
  final targetPath = await _nextDownloadPath(attachment.fileName);
  await File(sourcePath).copy(targetPath);
  return targetPath;
}

const String _attachmentLocalPathStoragePrefix =
    'ava.chat.attachment.local_path.v1';

String _attachmentLocalPathKey(ChatAttachment attachment) {
  final identity = attachment.id.isNotEmpty
      ? attachment.id
      : '${attachment.downloadUrl}|${attachment.fileName}|${attachment.size}';
  return '$_attachmentLocalPathStoragePrefix.'
      '${base64Url.encode(utf8.encode(identity))}';
}

Future<void> _rememberAttachmentLocalPath(
  ChatAttachment attachment,
  String path,
) async {
  if (path.isEmpty || !await File(path).exists()) {
    return;
  }
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = _attachmentLocalPathKey(attachment);
    await prefs.setString(key, path);
    await prefs.setString('$key.cachedAt', DateTime.now().toIso8601String());
  } on Object {
    // Playback cache is opportunistic; the remote download remains available.
  }
}

Future<String?> _rememberedAttachmentLocalPath(
  ChatAttachment attachment,
) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = _attachmentLocalPathKey(attachment);
    final path = prefs.getString(key);
    if (path == null || path.isEmpty) {
      return null;
    }
    if (await File(path).exists()) {
      return path;
    }
    await prefs.remove(key);
    await prefs.remove('$key.cachedAt');
  } on Object {
    // Ignore stale or unreadable cache metadata.
  }
  return null;
}

Future<String?> _downloadAttachmentToTemp(
  WidgetRef ref,
  ChatAttachment attachment, {
  void Function(int received, int total)? onReceiveProgress,
}) async {
  final localPath = attachment.localPath;
  if (localPath != null &&
      localPath.isNotEmpty &&
      await File(localPath).exists()) {
    unawaited(_rememberAttachmentLocalPath(attachment, localPath));
    return localPath;
  }
  final session = ref.read(authControllerProvider).value?.session;
  if (session == null || session.accessToken.isEmpty) {
    return null;
  }
  final targetPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'ava_share_${attachment.id}_${_sanitizeFileName(attachment.fileName)}';
  await ref
      .read(chatApiProvider)
      .downloadAttachment(
        accessToken: session.accessToken,
        downloadUrl: attachment.downloadUrl,
        savePath: targetPath,
        onReceiveProgress: onReceiveProgress,
      );
  await _rememberAttachmentLocalPath(attachment, targetPath);
  return targetPath;
}

class _MobileAudioPlayback {
  const _MobileAudioPlayback._();

  static const MethodChannel _channel = MethodChannel('ava/mobile_audio');

  static Future<Duration?> play(String path) async {
    try {
      final durationMs = await _channel.invokeMethod<int>('play', {
        'path': path,
      });
      if (durationMs == null || durationMs <= 0) {
        return null;
      }
      return Duration(milliseconds: durationMs);
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Desktop and widget tests do not provide this Android channel.
    }
  }
}

Future<void> _openLocalFile(BuildContext context, String path) async {
  if (path.isEmpty || !await File(path).exists()) {
    if (context.mounted) {
      showAvaToast(
        context,
        '\uD30C\uC77C\uC744 \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.',
      );
    }
    return;
  }
  if (Platform.isWindows) {
    await Process.run('rundll32.exe', ['url.dll,FileProtocolHandler', path]);
    return;
  }
  final opened = await launchUrl(
    Uri.file(path),
    mode: LaunchMode.externalApplication,
  );
  if (!opened && context.mounted) {
    showAvaToast(
      context,
      '\uD30C\uC77C\uC744 \uC5F4 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.',
    );
  }
}

Map<String, String>? _attachmentAuthHeaders(WidgetRef ref) {
  final token = ref.watch(authControllerProvider).value?.session?.accessToken;
  if (token == null || token.isEmpty) {
    return null;
  }
  return {'Authorization': 'Bearer $token'};
}

Widget _attachmentImage(
  BuildContext context,
  WidgetRef ref,
  ChatAttachment attachment, {
  BoxFit fit = BoxFit.contain,
}) {
  final localPath = attachment.localPath;
  if (localPath != null &&
      localPath.isNotEmpty &&
      File(localPath).existsSync()) {
    return Image.file(File(localPath), fit: fit);
  }
  return Image.network(
    _absoluteAttachmentUrl(
      ref.watch(appConfigProvider).apiBaseUrl,
      attachment.downloadUrl,
    ),
    headers: _attachmentAuthHeaders(ref),
    fit: fit,
    loadingBuilder: (context, child, progress) {
      if (progress == null) {
        return child;
      }
      return const Center(
        child: SizedBox.square(
          dimension: 42,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    },
    errorBuilder: (context, error, stackTrace) => const Center(
      child: Icon(Icons.broken_image_outlined, color: Colors.white70, size: 44),
    ),
  );
}

Future<void> _showAttachmentShareSheet(
  BuildContext context,
  WidgetRef ref,
  ChatAttachment attachment,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AttachmentShareSheet(attachment: attachment),
  );
}

Future<void> _showTextShareSheet(
  BuildContext context,
  WidgetRef ref,
  String text,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TextShareSheet(text: text),
  );
}

Future<void> _showAttachmentInfoSheet(
  BuildContext context,
  ChatAttachment attachment,
) async {
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) {
      final bottom = MediaQuery.paddingOf(context).bottom;
      return Container(
        padding: EdgeInsets.fromLTRB(18, 12, 18, bottom + 18),
        decoration: const BoxDecoration(
          color: Color(0xFFF2F7FC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFB7C8D8),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '\uD30C\uC77C \uC815\uBCF4',
              style: TextStyle(
                color: Color(0xFF0B1730),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            _InfoLine(label: '\uC774\uB984', value: attachment.fileName),
            _InfoLine(
              label: '\uD06C\uAE30',
              value: _formatFileSize(attachment.size),
            ),
            _InfoLine(label: '\uD615\uC2DD', value: attachment.contentType),
          ],
        ),
      );
    },
  );
}

class _MobileImageViewerPage extends ConsumerStatefulWidget {
  const _MobileImageViewerPage({
    required this.messages,
    required this.initialIndex,
    required this.onDeleteMessage,
  });

  final List<ChatMessage> messages;
  final int initialIndex;
  final Future<void> Function(ChatMessage message, {_MessageDeleteMode? mode})
  onDeleteMessage;

  @override
  ConsumerState<_MobileImageViewerPage> createState() =>
      _MobileImageViewerPageState();
}

class _MobileImageViewerPageState
    extends ConsumerState<_MobileImageViewerPage> {
  late final PageController _controller;
  late int _index;
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.messages.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ChatMessage get _message => widget.messages[_index];
  ChatAttachment get _attachment => _message.attachment!;

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
  }

  Future<void> _download() async {
    try {
      final path = await _downloadAttachmentToDownloads(
        context,
        ref,
        _attachment,
      );
      if (path != null) {
        if (await File(path).exists()) {
          await _rememberAttachmentLocalPath(_attachment, path);
        }
      }
      if (mounted && path != null) {
        showAvaToast(
          context,
          '\uB2E4\uC6B4\uB85C\uB4DC\uD588\uC2B5\uB2C8\uB2E4.',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    }
  }

  Future<void> _delete() async {
    await widget.onDeleteMessage(_message);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _edit() async {
    final path = await _downloadAttachmentToTemp(ref, _attachment);
    if (!mounted || path == null) {
      return;
    }
    await _openLocalFile(context, path);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final sentAt = _message.sentAt ?? DateTime.now();
    return Scaffold(
      backgroundColor: const Color(0xFF16202A),
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleChrome,
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.messages.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) {
                  final attachment = widget.messages[index].attachment;
                  if (attachment == null) {
                    return const SizedBox.shrink();
                  }
                  return Center(
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: _attachmentImage(context, ref, attachment),
                    ),
                  );
                },
              ),
            ),
          ),
          AnimatedSlide(
            offset: _chromeVisible ? Offset.zero : const Offset(0, -1),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: _ViewerTopBar(
              sender: _message.sender.name,
              date: _viewerDateTimeLabel(sentAt),
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
          AnimatedSlide(
            offset: _chromeVisible ? Offset.zero : const Offset(0, 1),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 10),
                color: const Color(0xF20A121B),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.messages.length > 1)
                      SizedBox(
                        height: 72,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: widget.messages.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 6),
                          itemBuilder: (context, index) {
                            final attachment =
                                widget.messages[index].attachment;
                            if (attachment == null) {
                              return const SizedBox.shrink();
                            }
                            final selected = index == _index;
                            return GestureDetector(
                              onTap: () => _controller.animateToPage(
                                index,
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                              ),
                              child: Container(
                                width: 46,
                                height: 58,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: selected
                                        ? const Color(0xFF9ED8FF)
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: _attachmentImage(
                                    context,
                                    ref,
                                    attachment,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    if (widget.messages.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 3, bottom: 8),
                        child: Text(
                          '${widget.messages.length}\uC7A5 \uC911 ${_index + 1}\uBC88',
                          style: const TextStyle(
                            color: Color(0xFFEAF4FF),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _ViewerActionButton(
                          icon: Icons.file_download_outlined,
                          label: '\uB2E4\uC6B4\uB85C\uB4DC',
                          onTap: _download,
                        ),
                        _ViewerActionButton(
                          icon: Icons.ios_share_outlined,
                          label: '\uACF5\uC720',
                          onTap: () => _showAttachmentShareSheet(
                            context,
                            ref,
                            _attachment,
                          ),
                        ),
                        _ViewerActionButton(
                          icon: Icons.delete_outline_rounded,
                          label: '\uC0AD\uC81C',
                          onTap: _delete,
                        ),
                        _ViewerActionButton(
                          icon: Icons.auto_fix_high_outlined,
                          label: '\uD3B8\uC9D1',
                          onTap: _edit,
                        ),
                        _ViewerActionButton(
                          icon: Icons.more_horiz_rounded,
                          label: '\uB354\uBCF4\uAE30',
                          onTap: () =>
                              _showAttachmentInfoSheet(context, _attachment),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileFileViewerPage extends ConsumerStatefulWidget {
  const _MobileFileViewerPage({
    required this.attachment,
    required this.localPath,
    required this.senderName,
    required this.sentAt,
  });

  final ChatAttachment attachment;
  final String localPath;
  final String senderName;
  final DateTime sentAt;

  @override
  ConsumerState<_MobileFileViewerPage> createState() =>
      _MobileFileViewerPageState();
}

class _MobileFileViewerPageState extends ConsumerState<_MobileFileViewerPage> {
  bool _chromeVisible = true;

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
  }

  Future<void> _download() async {
    try {
      final path = await _downloadAttachmentToDownloads(
        context,
        ref,
        widget.attachment,
      );
      if (mounted && path != null) {
        showAvaToast(
          context,
          '\uB2E4\uC6B4\uB85C\uB4DC\uD588\uC2B5\uB2C8\uB2E4.',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: const Color(0xFF16202A),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleChrome,
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 114,
                    height: 114,
                    decoration: BoxDecoration(
                      color: const Color(0xFF304052),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: Color(0xFFC5D4E4),
                      size: 58,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    widget.attachment.fileName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatFileSize(widget.attachment.size),
                    style: const TextStyle(
                      color: Color(0xFFC5D4E4),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSlide(
              offset: _chromeVisible ? Offset.zero : const Offset(0, -1),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: _ViewerTopBar(
                sender: widget.senderName,
                date: _viewerDateTimeLabel(widget.sentAt),
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            AnimatedSlide(
              offset: _chromeVisible ? Offset.zero : const Offset(0, 1),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  color: const Color(0xF20A121B),
                  padding: EdgeInsets.fromLTRB(14, 12, 14, bottom + 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.attachment.fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _formatFileSize(widget.attachment.size),
                                  style: const TextStyle(
                                    color: Color(0xFFC5D4E4),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FilledButton(
                            onPressed: () =>
                                _openLocalFile(context, widget.localPath),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF9ED8FF),
                              foregroundColor: const Color(0xFF071827),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              '\uC5F4\uAE30',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _ViewerActionButton(
                            icon: Icons.file_download_outlined,
                            label: '\uB2E4\uC6B4\uB85C\uB4DC',
                            onTap: _download,
                          ),
                          _ViewerActionButton(
                            icon: Icons.ios_share_outlined,
                            label: '\uACF5\uC720',
                            onTap: () => _showAttachmentShareSheet(
                              context,
                              ref,
                              widget.attachment,
                            ),
                          ),
                          _ViewerActionButton(
                            icon: Icons.more_horiz_rounded,
                            label: '\uB354\uBCF4\uAE30',
                            onTap: () => _showAttachmentInfoSheet(
                              context,
                              widget.attachment,
                            ),
                          ),
                        ],
                      ),
                    ],
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

class _MobileVideoViewerPage extends ConsumerStatefulWidget {
  const _MobileVideoViewerPage({
    required this.attachment,
    required this.localPath,
    required this.senderName,
    required this.sentAt,
  });

  final ChatAttachment attachment;
  final String localPath;
  final String senderName;
  final DateTime sentAt;

  @override
  ConsumerState<_MobileVideoViewerPage> createState() =>
      _MobileVideoViewerPageState();
}

class _MobileVideoViewerPageState
    extends ConsumerState<_MobileVideoViewerPage> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;
  bool _chromeVisible = true;
  Object? _initializeError;
  int _initializeGeneration = 0;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  VideoPlayerController _createVideoController(String path) {
    final uri = Uri.tryParse(path);
    if (uri != null && uri.scheme == 'content') {
      return VideoPlayerController.contentUri(uri);
    }
    return VideoPlayerController.file(File(path));
  }

  Future<void> _initializeVideo() async {
    final generation = ++_initializeGeneration;
    final previous = _controller;
    final controller = _createVideoController(widget.localPath);
    _controller = controller;
    _initializeError = null;
    unawaited(previous?.dispose());
    final future = controller.initialize().timeout(const Duration(seconds: 12));
    _initializeFuture = future;
    if (mounted && generation > 1) {
      setState(() {});
    }
    try {
      await future;
      if (!mounted) {
        return;
      }
      if (generation != _initializeGeneration) {
        return;
      }
      setState(() {});
      unawaited(_controller!.play());
    } on Object catch (error) {
      if (!mounted || generation != _initializeGeneration) {
        return;
      }
      setState(() => _initializeError = error);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      await _initializeVideo();
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _download() async {
    try {
      final path = await _downloadAttachmentToDownloads(
        context,
        ref,
        widget.attachment.copyWith(
          localPath: widget.localPath,
          cachedAt: DateTime.now(),
        ),
      );
      if (path != null) {
        final playbackPath = await File(widget.localPath).exists()
            ? widget.localPath
            : path;
        await _rememberAttachmentLocalPath(widget.attachment, playbackPath);
      }
      if (mounted && path != null) {
        showAvaToast(
          context,
          '\uB2E4\uC6B4\uB85C\uB4DC\uD588\uC2B5\uB2C8\uB2E4.',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: const Color(0xFF16202A),
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleChrome,
              child: Center(
                child: FutureBuilder<void>(
                  future: _initializeFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done ||
                        controller == null) {
                      return const SizedBox.square(
                        dimension: 54,
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          color: Color(0xFFEAF4FF),
                        ),
                      );
                    }
                    final hasError =
                        snapshot.hasError ||
                        _initializeError != null ||
                        !controller.value.isInitialized;
                    if (hasError) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton.filled(
                            onPressed: _initializeVideo,
                            style: IconButton.styleFrom(
                              fixedSize: const Size.square(72),
                              backgroundColor: const Color(0xAA000000),
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 50,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '\uB3D9\uC601\uC0C1\uC744 \uB2E4\uC2DC \uBD88\uB7EC\uC624\uC138\uC694.',
                            style: TextStyle(
                              color: Color(0xFFEAF4FF),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      );
                    }
                    return AspectRatio(
                      aspectRatio: controller.value.aspectRatio == 0
                          ? 16 / 9
                          : controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    );
                  },
                ),
              ),
            ),
          ),
          if (controller != null)
            Positioned.fill(
              child: Center(
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: controller,
                  builder: (context, value, child) {
                    if (!value.isInitialized) {
                      return const SizedBox.shrink();
                    }
                    if (value.isPlaying && !_chromeVisible) {
                      return const SizedBox.shrink();
                    }
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _togglePlayback,
                        customBorder: const CircleBorder(),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.48),
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 16,
                                offset: Offset(0, 5),
                              ),
                            ],
                          ),
                          child: SizedBox.square(
                            dimension: 74,
                            child: Icon(
                              value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 52,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          AnimatedSlide(
            offset: _chromeVisible ? Offset.zero : const Offset(0, -1),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: _ViewerTopBar(
              sender: widget.senderName,
              date: _viewerDateTimeLabel(widget.sentAt),
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
          AnimatedSlide(
            offset: _chromeVisible ? Offset.zero : const Offset(0, 1),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                color: const Color(0xF20A121B),
                padding: EdgeInsets.fromLTRB(14, 10, 14, bottom + 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (controller != null)
                      VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                        padding: const EdgeInsets.only(bottom: 12),
                        colors: const VideoProgressColors(
                          playedColor: Color(0xFF9ED8FF),
                          bufferedColor: Color(0x6687A7BF),
                          backgroundColor: Color(0x6644576B),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _ViewerActionButton(
                          icon: Icons.file_download_outlined,
                          label: '\uB2E4\uC6B4\uB85C\uB4DC',
                          onTap: _download,
                        ),
                        _ViewerActionButton(
                          icon: Icons.ios_share_outlined,
                          label: '\uACF5\uC720',
                          onTap: () => _showAttachmentShareSheet(
                            context,
                            ref,
                            widget.attachment.copyWith(
                              localPath: widget.localPath,
                              cachedAt: DateTime.now(),
                            ),
                          ),
                        ),
                        _ViewerActionButton(
                          icon: Icons.more_horiz_rounded,
                          label: '\uB354\uBCF4\uAE30',
                          onTap: () => _showAttachmentInfoSheet(
                            context,
                            widget.attachment,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewerTopBar extends StatelessWidget {
  const _ViewerTopBar({
    required this.sender,
    required this.date,
    required this.onBack,
  });

  final String sender;
  final String date;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      height: top + 78,
      padding: EdgeInsets.fromLTRB(6, top + 8, 8, 10),
      color: const Color(0xF20A121B),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sender,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  date,
                  style: const TextStyle(
                    color: Color(0xFFD9E7F4),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => showAvaToast(context, '\uC804\uCCB4 \uBCF4\uAE30'),
            icon: const Icon(Icons.grid_view_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ViewerActionButton extends StatelessWidget {
  const _ViewerActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 96,
        height: 76,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFFEAF4FF), size: 26),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFEAF4FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentShareSheet extends ConsumerStatefulWidget {
  const _AttachmentShareSheet({required this.attachment});

  final ChatAttachment attachment;

  @override
  ConsumerState<_AttachmentShareSheet> createState() =>
      _AttachmentShareSheetState();
}

class _AttachmentShareSheetState extends ConsumerState<_AttachmentShareSheet> {
  final Set<String> _selectedRoomIds = {};
  final TextEditingController _searchController = TextEditingController();
  bool _sending = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_selectedRoomIds.isEmpty || _sending) {
      return;
    }
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      showAvaToast(
        context,
        '\uB85C\uADF8\uC778 \uD6C4 \uACF5\uC720\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.',
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final sourcePath = await _downloadAttachmentToTemp(
        ref,
        widget.attachment,
      );
      if (sourcePath == null || sourcePath.isEmpty) {
        throw StateError('Attachment is not available.');
      }
      final rooms = ref.read(chatRoomsProvider);
      for (final room in rooms.where(
        (room) => _selectedRoomIds.contains(room.id),
      )) {
        final message = await ref
            .read(chatApiProvider)
            .uploadAttachment(
              accessToken: session.accessToken,
              roomCode: room.id,
              filePath: sourcePath,
              fileName: widget.attachment.fileName,
              groupId: 'share-${DateTime.now().microsecondsSinceEpoch}',
            );
        ref
            .read(chatRoomsProvider.notifier)
            .messagePosted(
              room.id,
              chatMessageListPreview(message),
              message.sentAt,
              fallbackRoom: room,
            );
      }
      if (mounted) {
        Navigator.of(context).pop();
        showAvaToast(context, '\uACF5\uC720\uD588\uC2B5\uB2C8\uB2E4.');
      }
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final rooms = ref.watch(chatRoomsProvider);
    final query = _query.trim().toLowerCase();
    final filtered = [
      for (final room in rooms)
        if (!room.isDraft &&
            (query.isEmpty || room.title.toLowerCase().contains(query)))
          room,
    ];
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.64,
      ),
      padding: EdgeInsets.fromLTRB(14, 8, 14, bottom + 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF2F7FC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFB7C8D8),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText:
                  '\uACF5\uC720\uD558\uACE0 \uC2F6\uC740 \uCE5C\uAD6C, \uCC44\uD305\uBC29 \uAC80\uC0C9 (\uCD08\uC131 \uAC00\uB2A5)',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              _ShareFilterChip(label: '\uC804\uCCB4', selected: true),
              SizedBox(width: 8),
              _ShareFilterChip(label: '\uCE5C\uAD6C'),
              SizedBox(width: 8),
              _ShareFilterChip(label: '\uCD5C\uADFC \uACF5\uC720'),
            ],
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: filtered.length,
              separatorBuilder: (context, index) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final room = filtered[index];
                final selected = _selectedRoomIds.contains(room.id);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _ShareRoomAvatar(room: room),
                  title: Text(
                    room.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF0B1730),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: Text(
                    room.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF6A7C8D),
                      fontSize: 12,
                    ),
                  ),
                  trailing: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected
                        ? const Color(0xFF2FAF72)
                        : const Color(0xFF8DA2B5),
                  ),
                  onTap: () {
                    setState(() {
                      if (selected) {
                        _selectedRoomIds.remove(room.id);
                      } else {
                        _selectedRoomIds.add(room.id);
                      }
                    });
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _selectedRoomIds.isEmpty || _sending ? null : _send,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2FAF72),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFC9D7E4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                _sending
                    ? '\uC804\uC1A1 \uC911'
                    : '${_selectedRoomIds.length} \uBCF4\uB0B4\uAE30',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextShareSheet extends ConsumerWidget {
  const _TextShareSheet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _TextShareSheetBody(text: text);
  }
}

class _TextShareSheetBody extends ConsumerStatefulWidget {
  const _TextShareSheetBody({required this.text});

  final String text;

  @override
  ConsumerState<_TextShareSheetBody> createState() =>
      _TextShareSheetBodyState();
}

class _TextShareSheetBodyState extends ConsumerState<_TextShareSheetBody> {
  final Set<String> _selectedRoomIds = {};
  bool _sending = false;

  Future<void> _send() async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null ||
        session.accessToken.isEmpty ||
        _selectedRoomIds.isEmpty) {
      return;
    }
    setState(() => _sending = true);
    try {
      for (final room
          in ref
              .read(chatRoomsProvider)
              .where((room) => _selectedRoomIds.contains(room.id))) {
        final message = await ref
            .read(chatApiProvider)
            .send(
              accessToken: session.accessToken,
              roomCode: room.id,
              content: widget.text,
            );
        ref
            .read(chatRoomsProvider.notifier)
            .messagePosted(
              room.id,
              widget.text,
              message.sentAt,
              fallbackRoom: room,
            );
      }
      if (mounted) {
        Navigator.of(context).pop();
        showAvaToast(context, '\uACF5\uC720\uD588\uC2B5\uB2C8\uB2E4.');
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final rooms = ref
        .watch(chatRoomsProvider)
        .where((room) => !room.isDraft)
        .toList();
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.56,
      ),
      padding: EdgeInsets.fromLTRB(14, 10, 14, bottom + 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF2F7FC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFB7C8D8),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final room in rooms)
                  CheckboxListTile(
                    value: _selectedRoomIds.contains(room.id),
                    title: Text(room.title),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedRoomIds.add(room.id);
                        } else {
                          _selectedRoomIds.remove(room.id);
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _selectedRoomIds.isEmpty || _sending ? null : _send,
              child: Text('${_selectedRoomIds.length} \uBCF4\uB0B4\uAE30'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareFilterChip extends StatelessWidget {
  const _ShareFilterChip({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? Colors.white : const Color(0xFFE2ECF5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD0DFEC)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF0B1730),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ShareRoomAvatar extends StatelessWidget {
  const _ShareRoomAvatar({required this.room});

  final ChatRoom room;

  @override
  Widget build(BuildContext context) {
    if (room.members.length <= 1) {
      return ProfileAvatar(
        profile: room.members.isEmpty
            ? PersonProfile(name: room.title, color: const Color(0xFF8FD4E3))
            : room.members.first,
        size: 42,
      );
    }
    final members = room.members.take(4).toList();
    return SizedBox(
      width: 42,
      height: 42,
      child: Stack(
        children: [
          for (final entry in members.indexed)
            Positioned(
              left: entry.$1.isEven ? 0 : 20,
              top: entry.$1 < 2 ? 0 : 20,
              child: ProfileAvatar(profile: entry.$2, size: 22),
            ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6A7C8D),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF0B1730),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _viewerDateTimeLabel(DateTime value) {
  final local = value.toLocal();
  final period = local.hour < 12 ? '\uC624\uC804' : '\uC624\uD6C4';
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}. ${local.month}. ${local.day}. $period $hour:$minute';
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
    required this.roomId,
    required this.messages,
    required this.focusedMessageId,
    required this.searchQuery,
    required this.typingLabel,
    required this.hasMoreOlderMessages,
    required this.loadingOlderMessages,
    required this.bottomViewportInset,
    required this.onLoadOlderMessages,
    required this.onMessageContextMenu,
    required this.onOpenImages,
    required this.onFocusedMessageConsumed,
  });

  final String roomId;
  final List<ChatMessage> messages;
  final String? focusedMessageId;
  final String searchQuery;
  final String? typingLabel;
  final bool hasMoreOlderMessages;
  final bool loadingOlderMessages;
  final double bottomViewportInset;
  final VoidCallback onLoadOlderMessages;
  final void Function(ChatMessage message, Offset position)
  onMessageContextMenu;
  final void Function(List<ChatMessage> messages, int initialIndex)
  onOpenImages;
  final VoidCallback onFocusedMessageConsumed;

  @override
  State<_ChatMessagesView> createState() => _ChatMessagesViewState();
}

class _ChatMessagesViewState extends State<_ChatMessagesView> {
  static const double _olderMessagePrefetchExtent = 720;

  final ScrollController _controller = ScrollController();
  final Map<String, GlobalKey> _focusKeys = {};
  List<ChatMessage>? _timelineMessages;
  List<_ChatTimelineEntry> _timelineEntriesCache = const [];
  int _roomScrollResetGeneration = 0;
  int _keyboardInsetScrollGeneration = 0;
  DateTime? _ignoreOlderLoadsUntil;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleScroll);
    _scheduleRoomResetToBottom();
  }

  @override
  void didUpdateWidget(covariant _ChatMessagesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      _focusKeys.clear();
      _timelineMessages = null;
      _timelineEntriesCache = const [];
      _scheduleRoomResetToBottom();
      return;
    }
    final focusedMessageChanged =
        oldWidget.focusedMessageId != widget.focusedMessageId;
    final focusedMessageCleared =
        (oldWidget.focusedMessageId ?? '').isNotEmpty &&
        (widget.focusedMessageId ?? '').isEmpty;
    final prependedOlderMessages = _didPrependMessages(
      oldWidget.messages,
      widget.messages,
    );
    if (prependedOlderMessages) {
      _preserveScrollOffsetAfterPrepend();
      return;
    }
    final keyboardInsetIncreased =
        widget.bottomViewportInset > oldWidget.bottomViewportInset + 0.5;
    if (keyboardInsetIncreased) {
      _scheduleKeyboardInsetScrollToBottom();
    }
    final appendedOwnMessage = _didAppendOwnMessage(
      oldWidget.messages,
      widget.messages,
    );
    final shouldAutoScroll =
        appendedOwnMessage ||
        oldWidget.messages.isEmpty ||
        _isNearBottom() ||
        oldWidget.typingLabel != widget.typingLabel ||
        (focusedMessageChanged && !focusedMessageCleared);
    if ((oldWidget.messages.length != widget.messages.length &&
            shouldAutoScroll) ||
        oldWidget.typingLabel != widget.typingLabel ||
        (focusedMessageChanged && !focusedMessageCleared)) {
      _scrollToFocusedOrBottom();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleScroll);
    _controller.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!widget.hasMoreOlderMessages ||
        widget.loadingOlderMessages ||
        !_controller.hasClients) {
      return;
    }
    final ignoreOlderLoadsUntil = _ignoreOlderLoadsUntil;
    if (ignoreOlderLoadsUntil != null &&
        DateTime.now().isBefore(ignoreOlderLoadsUntil)) {
      return;
    }
    final position = _controller.position;
    if (position.pixels <=
        position.minScrollExtent + _olderMessagePrefetchExtent) {
      widget.onLoadOlderMessages();
    }
  }

  void _scheduleRoomResetToBottom() {
    final generation = ++_roomScrollResetGeneration;
    _ignoreOlderLoadsUntil = DateTime.now().add(
      const Duration(milliseconds: 320),
    );
    if (_controller.hasClients) {
      _jumpToCurrentBottom();
    }

    void jumpAfterFrame(int remainingFrames) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _roomScrollResetGeneration) {
          return;
        }
        _jumpToCurrentBottom();
        if (remainingFrames > 0) {
          jumpAfterFrame(remainingFrames - 1);
        }
      });
    }

    jumpAfterFrame(1);
  }

  void _scheduleKeyboardInsetScrollToBottom() {
    final generation = ++_keyboardInsetScrollGeneration;

    void scrollAfterFrame(int remainingFrames) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _keyboardInsetScrollGeneration) {
          return;
        }
        _scrollControllerToBottom(instant: remainingFrames > 0);
        if (remainingFrames > 0) {
          scrollAfterFrame(remainingFrames - 1);
        }
      });
    }

    scrollAfterFrame(2);
  }

  void _jumpToCurrentBottom() {
    if (!_controller.hasClients) {
      return;
    }
    final position = _controller.position;
    _controller.jumpTo(position.maxScrollExtent);
  }

  bool _didPrependMessages(
    List<ChatMessage> oldMessages,
    List<ChatMessage> newMessages,
  ) {
    if (oldMessages.isEmpty || newMessages.length <= oldMessages.length) {
      return false;
    }
    final oldFirstKey = chatMessageCacheKey(oldMessages.first);
    final newFirstKey = chatMessageCacheKey(newMessages.first);
    if (oldFirstKey == newFirstKey) {
      return false;
    }
    return newMessages.any(
      (message) => chatMessageCacheKey(message) == oldFirstKey,
    );
  }

  bool _didAppendOwnMessage(
    List<ChatMessage> oldMessages,
    List<ChatMessage> newMessages,
  ) {
    if (newMessages.length <= oldMessages.length || newMessages.isEmpty) {
      return false;
    }
    final lastMessage = newMessages.last;
    if (!lastMessage.isMine) {
      return false;
    }
    if (oldMessages.isEmpty) {
      return true;
    }
    return chatMessageCacheKey(oldMessages.last) !=
        chatMessageCacheKey(lastMessage);
  }

  bool _isNearBottom() {
    if (!_controller.hasClients) {
      return true;
    }
    final position = _controller.position;
    return position.maxScrollExtent - position.pixels <= 120;
  }

  void _preserveScrollOffsetAfterPrepend() {
    if (!_controller.hasClients) {
      return;
    }
    final previousPixels = _controller.position.pixels;
    final previousMaxScrollExtent = _controller.position.maxScrollExtent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) {
        return;
      }
      final position = _controller.position;
      final delta = position.maxScrollExtent - previousMaxScrollExtent;
      final target = (previousPixels + delta)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      _controller.jumpTo(target);
    });
  }

  void _scrollToFocusedOrBottom({bool instant = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final focusedMessageId = widget.focusedMessageId;
      if (focusedMessageId != null && focusedMessageId.isNotEmpty) {
        final targetContext = _focusKeys[focusedMessageId]?.currentContext;
        if (targetContext != null) {
          _ensureFocusedVisible(targetContext);
          return;
        }
        if (_controller.hasClients) {
          final targetIndex = _timelineIndexForMessage(focusedMessageId);
          if (targetIndex != null) {
            final entries = _timelineEntries();
            final denominator = math.max(entries.length - 1, 1);
            final targetOffset =
                _controller.position.maxScrollExtent *
                (targetIndex / denominator).clamp(0, 1).toDouble();
            _controller
                .animateTo(
                  targetOffset,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                )
                .then((_) {
                  if (!mounted) {
                    return;
                  }
                  final context = _focusKeys[focusedMessageId]?.currentContext;
                  if (context != null && context.mounted) {
                    _ensureFocusedVisible(context);
                  } else {
                    widget.onFocusedMessageConsumed();
                  }
                });
            return;
          }
        }
      }
      if (!_controller.hasClients) {
        return;
      }
      _scrollControllerToBottom(instant: instant);
    });
  }

  void _scrollControllerToBottom({bool instant = false}) {
    if (!_controller.hasClients) {
      return;
    }
    final target = _controller.position.maxScrollExtent;
    if (instant) {
      _controller.jumpTo(target);
    } else {
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _ensureFocusedVisible(BuildContext targetContext) {
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.92,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
    widget.onFocusedMessageConsumed();
  }

  int? _timelineIndexForMessage(String messageId) {
    final entries = _timelineEntries();
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final message = entry.message;
      if (message?.id == messageId) {
        return index;
      }
      final gallery = entry.imageGallery;
      if (gallery != null &&
          gallery.any((message) => message.id == messageId)) {
        return index;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final showTyping = widget.typingLabel != null;
    final entries = _timelineEntries();
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: ListView.separated(
        key: const ValueKey('chat-messages-list'),
        controller: _controller,
        primary: false,
        cacheExtent: 1600,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
            final key = _focusKeyForGallery(entry.imageGallery!);
            return _ImageGalleryMessage(
              key: key ?? ValueKey('chat-image-gallery-$index'),
              messages: entry.imageGallery!,
              onOpenImages: widget.onOpenImages,
              onContextMenu: widget.onMessageContextMenu,
            );
          }
          final message = entry.message!;

          return _MessageBubble(
            key:
                _focusKeyForMessage(message) ?? ValueKey('chat-message-$index'),
            message: message,
            searchQuery: widget.searchQuery,
            onContextMenu: widget.onMessageContextMenu,
          );
        },
      ),
    );
  }

  Key? _focusKeyForMessage(ChatMessage message) {
    final id = message.id;
    if (id == null || id.isEmpty || id != widget.focusedMessageId) {
      return null;
    }
    return _focusKeys.putIfAbsent(id, () => GlobalKey());
  }

  Key? _focusKeyForGallery(List<ChatMessage> messages) {
    final focusedMessageId = widget.focusedMessageId;
    if (focusedMessageId == null || focusedMessageId.isEmpty) {
      return null;
    }
    for (final message in messages) {
      if (message.id == focusedMessageId) {
        return _focusKeys.putIfAbsent(focusedMessageId, () => GlobalKey());
      }
    }
    return null;
  }

  List<_ChatTimelineEntry> _timelineEntries() {
    if (identical(_timelineMessages, widget.messages)) {
      return _timelineEntriesCache;
    }
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
    _timelineMessages = widget.messages;
    _timelineEntriesCache = List<_ChatTimelineEntry>.unmodifiable(entries);
    return _timelineEntriesCache;
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
  return !message.isSystem &&
      !message.deletedForEveryone &&
      attachment != null &&
      attachment.isImage;
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

List<ChatMessage> _chatMediaMessages(List<ChatMessage> messages) {
  final items = [
    for (final message in messages)
      if (!message.isSystem &&
          !message.deletedForEveryone &&
          message.attachment != null &&
          (message.attachment!.isImage || message.attachment!.isVideo))
        message,
  ];
  items.sort(_sortMessagesNewestFirst);
  return items;
}

List<ChatMessage> _chatFileMessages(List<ChatMessage> messages) {
  final items = [
    for (final message in messages)
      if (!message.isSystem &&
          !message.deletedForEveryone &&
          message.attachment != null &&
          !message.attachment!.isImage &&
          !message.attachment!.isVideo &&
          !message.attachment!.isAudio)
        message,
  ];
  items.sort(_sortMessagesNewestFirst);
  return items;
}

List<ChatMessage> _chatLinkMessages(List<ChatMessage> messages) {
  final items = [
    for (final message in messages)
      if (!message.isSystem && _firstLink(message.text) != null) message,
  ];
  items.sort(_sortMessagesNewestFirst);
  return items;
}

int _sortMessagesNewestFirst(ChatMessage a, ChatMessage b) {
  final aTime = a.sentAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final bTime = b.sentAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  return bTime.compareTo(aTime);
}

Map<String, List<ChatMessage>> _groupMessagesByDate(
  List<ChatMessage> messages,
) {
  final grouped = <String, List<ChatMessage>>{};
  for (final message in messages) {
    final sentAt = message.sentAt?.toLocal() ?? DateTime.now();
    final label = '${sentAt.year}. ${sentAt.month}. ${sentAt.day}';
    grouped.putIfAbsent(label, () => []).add(message);
  }
  return grouped;
}

String? _firstLink(String text) {
  final match = RegExp(r'https?:\/\/[^\s]+').firstMatch(text);
  return match?.group(0);
}

const _stickerTokenPrefix = '[[AVA_STICKER:';
const _stickerTokenSuffix = ']]';
final List<String> _avaStickerIds = List<String>.generate(
  30,
  (index) => 'kakao_friends_${(index + 1).toString().padLeft(2, '0')}',
);

String _stickerAssetPath(String stickerId) {
  final raw = RegExp(r'(\d+)$').firstMatch(stickerId)?.group(1);
  final number = (int.tryParse(raw ?? '1') ?? 1).clamp(1, 30);
  return 'assets/images/AVA_IMG/emoticon/kakaofreinds/'
      'emoticon_${number.toString().padLeft(2, '0')}.gif';
}

String _stickerToken(String stickerId) {
  return '$_stickerTokenPrefix$stickerId$_stickerTokenSuffix';
}

String? _stickerIdFromText(String text) {
  final trimmed = text.trim();
  if (!trimmed.startsWith(_stickerTokenPrefix) ||
      !trimmed.endsWith(_stickerTokenSuffix)) {
    return null;
  }
  final id = trimmed.substring(
    _stickerTokenPrefix.length,
    trimmed.length - _stickerTokenSuffix.length,
  );
  return id.isEmpty ? null : id;
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.room,
    required this.onClose,
    required this.mobileLayout,
    required this.onSearch,
    required this.onOpenMenu,
  });

  final ChatRoom room;
  final VoidCallback onClose;
  final bool mobileLayout;
  final VoidCallback onSearch;
  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) {
    if (mobileLayout) {
      return SafeArea(
        bottom: false,
        child: Container(
          height: 58,
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
          color: _chatBackground,
          child: Row(
            children: [
              _ChatHeaderAction(
                key: const ValueKey('mobile-chat-back'),
                icon: Icons.arrow_back,
                tooltip: '\uB4A4\uB85C\uAC00\uAE30',
                onPressed: onClose,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  room.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _ChatHeaderAction(
                icon: Icons.search,
                tooltip: '\uCC44\uD305\uBC29 \uAC80\uC0C9',
                onPressed: onSearch,
              ),
              _ChatHeaderAction(
                icon: Icons.menu,
                tooltip: '\uBA54\uB274',
                onPressed: onOpenMenu,
              ),
            ],
          ),
        ),
      );
    }

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
          _ChatHeaderAction(
            icon: Icons.search,
            tooltip: '\uCC44\uD305\uBC29 \uAC80\uC0C9',
            onPressed: onSearch,
          ),
          const _ChatHeaderAction(
            icon: Icons.call_outlined,
            tooltip: '\uD1B5\uD654',
          ),
          const _ChatHeaderAction(
            icon: Icons.videocam_outlined,
            tooltip: '\uC601\uC0C1 \uD1B5\uD654',
          ),
          _ChatHeaderAction(
            icon: Icons.menu,
            tooltip: '\uBA54\uB274',
            onPressed: onOpenMenu,
          ),
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
    super.key,
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

class _ChatRoomSearchBar extends StatelessWidget {
  const _ChatRoomSearchBar({
    required this.controller,
    required this.focusNode,
    required this.mobileLayout,
    required this.matchCount,
    required this.currentIndex,
    required this.onChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool mobileLayout;
  final int matchCount;
  final int currentIndex;
  final ValueChanged<String> onChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (mobileLayout) {
      final hasMatches = matchCount > 0;
      final hasQuery = controller.text.trim().isNotEmpty;

      return Material(
        color: _chatBackground,
        elevation: 0,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                SizedBox(
                  width: 47,
                  height: 52,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    splashRadius: 22,
                    onPressed: onClose,
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Color(0xFF102033),
                      size: 25,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 36,
                    margin: const EdgeInsets.only(right: 16),
                    padding: const EdgeInsets.only(left: 14, right: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7EEF5),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            focusNode: focusNode,
                            onChanged: onChanged,
                            textInputAction: TextInputAction.search,
                            style: const TextStyle(
                              color: Color(0xFF102033),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                            cursorColor: const Color(0xFF4F63CF),
                            decoration: const InputDecoration(
                              hintText: '\uB300\uD654\uB0B4\uC6A9 \uAC80\uC0C9',
                              hintStyle: TextStyle(
                                color: Color(0xFF7E8A98),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                              border: InputBorder.none,
                              isCollapsed: true,
                            ),
                          ),
                        ),
                        AnimatedOpacity(
                          opacity: hasQuery ? 1 : 0,
                          duration: const Duration(milliseconds: 120),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4, right: 2),
                            child: Text(
                              hasQuery && hasMatches
                                  ? '$currentIndex/$matchCount'
                                  : '0/0',
                              style: const TextStyle(
                                color: Color(0xFF5D6D7D),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        _MobileSearchArrowButton(
                          icon: Icons.keyboard_arrow_up_rounded,
                          enabled: hasMatches,
                          onPressed: onPrevious,
                        ),
                        _MobileSearchArrowButton(
                          icon: Icons.keyboard_arrow_down_rounded,
                          enabled: hasMatches,
                          onPressed: onNext,
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

    return Material(
      color: const Color(0xFFEAF2F8),
      elevation: 2,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Container(
          height: 50,
          padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 36,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: onClose,
                  icon: Icon(
                    Icons.close_rounded,
                    color: const Color(0xFF102033),
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7EEF5),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFFD3DFEA)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          onChanged: onChanged,
                          style: const TextStyle(
                            color: Color(0xFF102033),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                          cursorColor: const Color(0xFF4F63CF),
                          decoration: const InputDecoration(
                            hintText: '\uB300\uD654\uB0B4\uC6A9 \uAC80\uC0C9',
                            hintStyle: TextStyle(
                              color: Color(0xFF7F8C99),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      if (controller.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            matchCount == 0
                                ? '0/0'
                                : '$currentIndex/$matchCount',
                            style: const TextStyle(
                              color: Color(0xFF4B5E71),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: '\uC774\uC804',
                onPressed: matchCount == 0 ? null : onPrevious,
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                color: const Color(0xFF102033),
                disabledColor: const Color(0xFF94A3B5),
              ),
              IconButton(
                tooltip: '\uB2E4\uC74C',
                onPressed: matchCount == 0 ? null : onNext,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                color: const Color(0xFF102033),
                disabledColor: const Color(0xFF94A3B5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileSearchArrowButton extends StatelessWidget {
  const _MobileSearchArrowButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 34,
      child: IconButton(
        padding: EdgeInsets.zero,
        splashRadius: 17,
        visualDensity: VisualDensity.compact,
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 22),
        color: const Color(0xFF102033),
        disabledColor: const Color(0xFF9DAAB8),
      ),
    );
  }
}

enum _ChatSidePanelMode { info, media, files, links }

class _ChatSidePanelHost extends StatefulWidget {
  const _ChatSidePanelHost({
    required this.mode,
    required this.room,
    required this.messages,
    required this.onClose,
    required this.onOpenMedia,
    required this.onOpenFiles,
    required this.onOpenLinks,
    required this.onReady,
    required this.onOpenAvaAi,
    required this.onLeaveRoom,
    required this.onInviteMembers,
  });

  final _ChatSidePanelMode mode;
  final ChatRoom room;
  final List<ChatMessage> messages;
  final VoidCallback onClose;
  final VoidCallback onOpenMedia;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenLinks;
  final VoidCallback onReady;
  final VoidCallback onOpenAvaAi;
  final Future<void> Function() onLeaveRoom;
  final VoidCallback onInviteMembers;

  @override
  State<_ChatSidePanelHost> createState() => _ChatSidePanelHostState();
}

class _ChatSidePanelHostState extends State<_ChatSidePanelHost> {
  bool _visible = false;
  late _ChatSidePanelMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.mode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _visible = true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _ChatSidePanelHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _visible = true;
      _mode = widget.mode;
    }
  }

  Future<void> _close() async {
    setState(() => _visible = false);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (mounted) {
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _mode == _ChatSidePanelMode.info
        ? _ChatInfoPanel(
            room: widget.room,
            messages: widget.messages,
            onBack: _close,
            onOpenMedia: () => setState(() => _mode = _ChatSidePanelMode.media),
            onOpenFiles: () => setState(() => _mode = _ChatSidePanelMode.files),
            onOpenLinks: () => setState(() => _mode = _ChatSidePanelMode.links),
            onReady: widget.onReady,
            onOpenAvaAi: widget.onOpenAvaAi,
            onLeaveRoom: widget.onLeaveRoom,
            onInviteMembers: widget.onInviteMembers,
          )
        : _ChatAssetsPanel(
            mode: _mode,
            room: widget.room,
            messages: widget.messages,
            onBack: () => setState(() => _mode = _ChatSidePanelMode.info),
            onClose: _close,
            onSelectMode: (mode) => setState(() => _mode = mode),
          );

    return AnimatedSlide(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      offset: _visible ? Offset.zero : const Offset(1, 0),
      child: child,
    );
  }
}

class _ChatInfoPanel extends StatefulWidget {
  const _ChatInfoPanel({
    required this.room,
    required this.messages,
    required this.onBack,
    required this.onOpenMedia,
    required this.onOpenFiles,
    required this.onOpenLinks,
    required this.onReady,
    required this.onOpenAvaAi,
    required this.onLeaveRoom,
    required this.onInviteMembers,
  });

  final ChatRoom room;
  final List<ChatMessage> messages;
  final VoidCallback onBack;
  final VoidCallback onOpenMedia;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenLinks;
  final VoidCallback onReady;
  final VoidCallback onOpenAvaAi;
  final Future<void> Function() onLeaveRoom;
  final VoidCallback onInviteMembers;

  @override
  State<_ChatInfoPanel> createState() => _ChatInfoPanelState();
}

class _ChatInfoPanelState extends State<_ChatInfoPanel> {
  bool _notificationsEnabled = true;
  bool _favorite = false;

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final media = _chatMediaMessages(widget.messages).take(8).toList();
    return Material(
      color: const Color(0xFFF5F8FC),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 28),
          children: [
            Row(
              children: [
                _DarkCircleIcon(icon: Icons.arrow_back, onTap: widget.onBack),
                const Spacer(),
                _DarkCircleIcon(
                  icon: _notificationsEnabled
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  selected: _notificationsEnabled,
                  onTap: () => setState(() {
                    _notificationsEnabled = !_notificationsEnabled;
                  }),
                ),
                const SizedBox(width: 10),
                _DarkCircleIcon(
                  icon: _favorite
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  selected: _favorite,
                  onTap: () => setState(() {
                    _favorite = !_favorite;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Center(child: _RoomAvatarCluster(room: room)),
            const SizedBox(height: 14),
            Center(
              child: Text(
                room.title,
                style: const TextStyle(
                  color: Color(0xFF0B1730),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _DarkCard(
              children: [
                _ChatInfoMediaSection(media: media, onTap: widget.onOpenMedia),
                _ChatInfoRow(
                  icon: Icons.insert_drive_file_rounded,
                  iconColor: const Color(0xFF9AA4AA),
                  label: '\uD30C\uC77C',
                  onTap: widget.onOpenFiles,
                ),
                _ChatInfoRow(
                  icon: Icons.link_rounded,
                  iconColor: const Color(0xFF43A6FF),
                  label: '\uB9C1\uD06C',
                  onTap: widget.onOpenLinks,
                ),
                _ChatInfoRow(
                  icon: Icons.event_available_rounded,
                  iconColor: const Color(0xFF43A6FF),
                  label: '\uC77C\uC815',
                  onTap: widget.onReady,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _DarkCard(
              children: [
                _ChatInfoRow(
                  icon: Icons.article_rounded,
                  iconColor: const Color(0xFF9AA4AA),
                  label: '\uAC8C\uC2DC\uD310',
                  onTap: widget.onReady,
                ),
                _ChatInfoRow(
                  icon: Icons.campaign_rounded,
                  iconColor: const Color(0xFF43A6FF),
                  label: '\uACF5\uC9C0',
                  onTap: widget.onReady,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _DarkCard(
              children: [
                _ChatInfoRow(
                  icon: Icons.smart_toy_rounded,
                  iconColor: const Color(0xFF9AA4AA),
                  label: 'AVA AI',
                  onTap: widget.onOpenAvaAi,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _DarkCard(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Text(
                    '\uB300\uD654\uC0C1\uB300 ${room.displayParticipantCount}',
                    style: const TextStyle(
                      color: Color(0xFF0B1730),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _ChatInfoRow(
                  icon: Icons.add,
                  iconColor: const Color(0xFF43A6FF),
                  label: '\uCD08\uB300\uD558\uAE30',
                  onTap: widget.onInviteMembers,
                ),
                for (final member in room.members)
                  _ChatParticipantRow(profile: member),
              ],
            ),
            const SizedBox(height: 12),
            _DarkCard(
              children: [
                _ChatInfoRow(
                  icon: Icons.logout_rounded,
                  iconColor: const Color(0xFFFF7D4D),
                  label: '\uCC44\uD305\uBC29 \uB098\uAC00\uAE30',
                  destructive: true,
                  onTap: () => unawaited(widget.onLeaveRoom()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatAssetsPanel extends StatelessWidget {
  const _ChatAssetsPanel({
    required this.mode,
    required this.room,
    required this.messages,
    required this.onBack,
    required this.onClose,
    required this.onSelectMode,
  });

  final _ChatSidePanelMode mode;
  final ChatRoom room;
  final List<ChatMessage> messages;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final ValueChanged<_ChatSidePanelMode> onSelectMode;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF070707),
      child: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 54,
              child: Row(
                children: [
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      room.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            _AssetTabs(mode: mode, onSelectMode: onSelectMode),
            Expanded(
              child: _AssetsBody(mode: mode, messages: messages),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetTabs extends StatelessWidget {
  const _AssetTabs({required this.mode, required this.onSelectMode});

  final _ChatSidePanelMode mode;
  final ValueChanged<_ChatSidePanelMode> onSelectMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF202124))),
      ),
      child: Row(
        children: [
          _AssetTab(
            label: '\uC0AC\uC9C4/\uB3D9\uC601\uC0C1',
            selected: mode == _ChatSidePanelMode.media,
            onTap: () => onSelectMode(_ChatSidePanelMode.media),
          ),
          _AssetTab(
            label: '\uD30C\uC77C',
            selected: mode == _ChatSidePanelMode.files,
            onTap: () => onSelectMode(_ChatSidePanelMode.files),
          ),
          _AssetTab(
            label: '\uB9C1\uD06C',
            selected: mode == _ChatSidePanelMode.links,
            onTap: () => onSelectMode(_ChatSidePanelMode.links),
          ),
        ],
      ),
    );
  }
}

class _AssetTab extends StatelessWidget {
  const _AssetTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF85858C),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 2,
              width: 76,
              color: selected ? Colors.white : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetsBody extends StatelessWidget {
  const _AssetsBody({required this.mode, required this.messages});

  final _ChatSidePanelMode mode;
  final List<ChatMessage> messages;

  @override
  Widget build(BuildContext context) {
    final items = switch (mode) {
      _ChatSidePanelMode.media => _chatMediaMessages(messages),
      _ChatSidePanelMode.files => _chatFileMessages(messages),
      _ChatSidePanelMode.links => _chatLinkMessages(messages),
      _ChatSidePanelMode.info => const <ChatMessage>[],
    };
    if (items.isEmpty) {
      return const Center(
        child: Text(
          '\uD45C\uC2DC\uD560 \uB0B4\uC5ED\uC774 \uC5C6\uC2B5\uB2C8\uB2E4',
          style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
      children: [
        if (mode == _ChatSidePanelMode.media)
          _MediaGrid(messages: items)
        else if (mode == _ChatSidePanelMode.links)
          _LinksGrid(messages: items)
        else
          for (final entry in _groupMessagesByDate(items).entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 10),
              child: Text(
                entry.key,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final message in entry.value) _FileAssetRow(message: message),
          ],
      ],
    );
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({required this.messages});

  final List<ChatMessage> messages;

  @override
  Widget build(BuildContext context) {
    final grouped = _groupMessagesByDate(messages);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 10),
            child: Text(
              entry.key,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            primary: false,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 1,
              mainAxisSpacing: 1,
            ),
            itemCount: entry.value.length,
            itemBuilder: (context, index) {
              final attachment = entry.value[index].attachment;
              if (attachment == null || !attachment.isImage) {
                return const ColoredBox(color: Color(0xFF202124));
              }
              return _AttachmentImagePreview(attachment: attachment);
            },
          ),
        ],
      ],
    );
  }
}

class _LinksGrid extends StatelessWidget {
  const _LinksGrid({required this.messages});

  final List<ChatMessage> messages;

  @override
  Widget build(BuildContext context) {
    final grouped = _groupMessagesByDate(messages);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 10),
            child: Text(
              entry.key,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            primary: false,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 10,
              mainAxisExtent: 162,
            ),
            itemCount: entry.value.length,
            itemBuilder: (context, index) {
              final message = entry.value[index];
              final link = _firstLink(message.text) ?? message.text;
              return _LinkPreviewCard(
                url: link,
                compact: true,
                dark: true,
                showMenu: true,
              );
            },
          ),
        ],
      ],
    );
  }
}

class _FileAssetRow extends StatelessWidget {
  const _FileAssetRow({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final attachment = message.attachment;
    final name = attachment?.fileName ?? message.text;
    final size = attachment == null ? '' : _formatFileSize(attachment.size);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 50,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0xFF1F2023)),
              child: Icon(
                Icons.insert_drive_file_outlined,
                color: Color(0xFF37A9FF),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (size.isNotEmpty)
                  Text(
                    size,
                    style: const TextStyle(
                      color: Color(0xFF8E8E93),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          const Icon(Icons.download_rounded, color: Colors.white),
        ],
      ),
    );
  }
}

class _LinkPreviewCard extends ConsumerStatefulWidget {
  const _LinkPreviewCard({
    required this.url,
    this.compact = false,
    this.dark = false,
    this.showMenu = false,
    this.bubble = false,
  });

  final String url;
  final bool compact;
  final bool dark;
  final bool showMenu;
  final bool bubble;

  @override
  ConsumerState<_LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends ConsumerState<_LinkPreviewCard> {
  ChatLinkPreviewDto? _preview;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _LinkPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _preview = null;
      _load();
    }
  }

  Future<void> _load() async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty || widget.url.isEmpty) {
      return;
    }
    setState(() => _loading = true);
    try {
      final preview = await ref
          .read(chatApiProvider)
          .linkPreview(accessToken: session.accessToken, url: widget.url);
      if (mounted) {
        setState(() => _preview = preview);
      }
    } on Object {
      if (mounted) {
        setState(
          () => _preview = ChatLinkPreviewDto(
            url: widget.url,
            title: Uri.tryParse(widget.url)?.host ?? widget.url,
            description: '',
            imageUrl: '',
            siteName: Uri.tryParse(widget.url)?.host ?? '',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open() async {
    final uri = Uri.tryParse(_preview?.url ?? widget.url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final dark = widget.dark || widget.bubble;
    final background = dark ? const Color(0xFF2B2C2F) : Colors.white;
    final titleColor = dark ? Colors.white : const Color(0xFF111827);
    final bodyColor = dark ? const Color(0xFFC9CDD3) : const Color(0xFF4B5563);
    final urlColor = dark ? const Color(0xFF8CC8FF) : const Color(0xFF2563EB);
    final height = widget.compact ? 156.0 : (widget.bubble ? 214.0 : 168.0);
    final imageHeight = widget.compact ? 78.0 : (widget.bubble ? 122.0 : 88.0);

    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(widget.bubble ? 9 : 8),
      child: Container(
        constraints: BoxConstraints(maxWidth: widget.compact ? 190 : 268),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(widget.bubble ? 9 : 8),
          border: widget.bubble
              ? null
              : Border.all(
                  color: dark
                      ? const Color(0xFF34363A)
                      : const Color(0xFFE2E8F0),
                ),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: imageHeight,
                    width: double.infinity,
                    child: _loading && preview == null
                        ? const Center(
                            child: SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : preview != null && preview.imageUrl.isNotEmpty
                        ? Image.network(
                            preview.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _LinkPreviewFallback(
                                  title: preview.siteName,
                                  dark: dark,
                                ),
                          )
                        : _LinkPreviewFallback(
                            title:
                                preview?.siteName ??
                                Uri.tryParse(widget.url)?.host ??
                                '',
                            dark: dark,
                          ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      widget.bubble ? 12 : 10,
                      widget.bubble ? 11 : 9,
                      widget.bubble ? 12 : 10,
                      widget.bubble ? 10 : 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          preview?.title.isNotEmpty == true
                              ? preview!.title
                              : Uri.tryParse(widget.url)?.host ?? widget.url,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: titleColor,
                            fontSize: widget.compact
                                ? 12
                                : (widget.bubble ? 13.5 : 13),
                            fontWeight: FontWeight.w800,
                            height: 1.22,
                          ),
                        ),
                        if (!widget.compact &&
                            (preview?.description ?? '').isNotEmpty) ...[
                          SizedBox(height: widget.bubble ? 7 : 5),
                          Text(
                            preview!.description,
                            maxLines: widget.bubble ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: bodyColor,
                              fontSize: widget.bubble ? 12 : 11,
                              height: 1.25,
                            ),
                          ),
                        ],
                        SizedBox(height: widget.bubble ? 7 : 5),
                        Text(
                          preview?.url ?? widget.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: urlColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (widget.showMenu)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    Icons.more_vert_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkPreviewFallback extends StatelessWidget {
  const _LinkPreviewFallback({required this.title, required this.dark});

  final String title;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: dark ? const Color(0xFF3A3B3D) : const Color(0xFFF1F5F9),
      child: Center(
        child: Text(
          title.isEmpty
              ? 'LINK'
              : title.characters.take(1).toString().toUpperCase(),
          style: TextStyle(
            color: dark ? const Color(0xFFBFC5D0) : const Color(0xFF526176),
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _ChatStickerBubble extends StatefulWidget {
  const _ChatStickerBubble({required this.stickerId});

  final String stickerId;

  @override
  State<_ChatStickerBubble> createState() => _ChatStickerBubbleState();
}

class _ChatStickerBubbleState extends State<_ChatStickerBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _stopTimer;
  int _replayNonce = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    _playThreeLoops();
  }

  @override
  void didUpdateWidget(covariant _ChatStickerBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stickerId != widget.stickerId) {
      _playThreeLoops();
    }
  }

  @override
  void dispose() {
    _stopTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _playThreeLoops() {
    _stopTimer?.cancel();
    if (mounted) {
      setState(() {
        _replayNonce++;
      });
    }
    _controller
      ..stop()
      ..value = 0
      ..repeat();
    _stopTimer = Timer(const Duration(milliseconds: 2280), () {
      if (!mounted) {
        return;
      }
      _controller
        ..stop()
        ..value = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _playThreeLoops,
      child: SizedBox.square(
        dimension: 118,
        child: Image.asset(
          _stickerAssetPath(widget.stickerId),
          key: ValueKey('${widget.stickerId}-$_replayNonce'),
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _AvaStickerPainter(
                  stickerId: widget.stickerId,
                  progress: _controller.value,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AvaStickerPainter extends CustomPainter {
  const _AvaStickerPainter({
    required this.stickerId,
    required this.progress,
    this.preview = false,
  });

  final String stickerId;
  final double progress;
  final bool preview;

  int get _index {
    final raw = RegExp(r'(\d+)$').firstMatch(stickerId)?.group(1);
    return int.tryParse(raw ?? '1') ?? 1;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    final t = math.sin(progress * math.pi * 2);
    final center = Offset(size.width / 2, size.height / 2 + t * 3);
    final scale = preview ? 1.05 : 1.0;
    final radius = size.shortestSide * 0.34 * scale;
    final variant = _index % 6;

    paint.color = const Color(0xFFFFB642);
    canvas.drawCircle(center, radius, paint);
    paint.color = const Color(0xFF3A2718);
    canvas.drawCircle(
      center + Offset(-radius * 0.36, -radius * 0.16),
      3.2,
      paint,
    );
    canvas.drawCircle(
      center + Offset(radius * 0.36, -radius * 0.16),
      3.2,
      paint,
    );

    final earOffset = radius * 0.72;
    paint.color = const Color(0xFFFFB642);
    canvas.drawCircle(
      center + Offset(-earOffset, -earOffset),
      radius * 0.25,
      paint,
    );
    canvas.drawCircle(
      center + Offset(earOffset, -earOffset),
      radius * 0.25,
      paint,
    );
    paint.color = const Color(0xFF3A2718).withValues(alpha: 0.12);
    canvas.drawCircle(
      center + Offset(-earOffset, -earOffset),
      radius * 0.13,
      paint,
    );
    canvas.drawCircle(
      center + Offset(earOffset, -earOffset),
      radius * 0.13,
      paint,
    );

    final nose = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center + Offset(0, radius * 0.1),
        width: radius * 0.58,
        height: radius * 0.36,
      ),
      Radius.circular(radius * 0.18),
    );
    paint.color = const Color(0xFFFFE5B3);
    canvas.drawRRect(nose, paint);
    paint.color = const Color(0xFF3A2718);
    canvas.drawCircle(center + Offset(0, radius * 0.04), 2.8, paint);

    final mouth = Path();
    final mouthY = center.dy + radius * (0.18 + (variant == 2 ? 0.06 : 0));
    mouth.moveTo(center.dx - radius * 0.2, mouthY);
    mouth.quadraticBezierTo(
      center.dx,
      mouthY + radius * 0.18,
      center.dx + radius * 0.2,
      mouthY,
    );
    canvas.drawPath(
      mouth,
      Paint()
        ..isAntiAlias = true
        ..color = const Color(0xFF3A2718)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    if (variant == 0 || variant == 3) {
      paint.color = const Color(0xFFFF6E8D);
      canvas.drawCircle(
        center + Offset(-radius * 0.52, radius * 0.06),
        radius * 0.12,
        paint,
      );
      canvas.drawCircle(
        center + Offset(radius * 0.52, radius * 0.06),
        radius * 0.12,
        paint,
      );
    }
    if (variant == 1 || variant == 4) {
      final heart = Path()
        ..moveTo(center.dx + radius * 0.72, center.dy - radius * 0.48 + t * 3)
        ..cubicTo(
          center.dx + radius * 0.58,
          center.dy - radius * 0.65,
          center.dx + radius * 0.36,
          center.dy - radius * 0.36,
          center.dx + radius * 0.72,
          center.dy - radius * 0.18,
        )
        ..cubicTo(
          center.dx + radius * 1.08,
          center.dy - radius * 0.36,
          center.dx + radius * 0.86,
          center.dy - radius * 0.65,
          center.dx + radius * 0.72,
          center.dy - radius * 0.48 + t * 3,
        );
      paint.color = const Color(0xFFFF5A76);
      canvas.drawPath(heart, paint);
    }
    if (variant == 5) {
      paint.color = const Color(0xFF4C63D9);
      canvas.drawCircle(
        center + Offset(-radius * 0.82, -radius * 0.4 + t * 4),
        radius * 0.08,
        paint,
      );
      canvas.drawCircle(
        center + Offset(radius * 0.82, radius * 0.36 - t * 4),
        radius * 0.08,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AvaStickerPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.stickerId != stickerId ||
        oldDelegate.preview != preview;
  }
}

class _DarkCircleIcon extends StatelessWidget {
  const _DarkCircleIcon({
    required this.icon,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox.square(
        dimension: 38,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE6EEFF) : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFD7E1F2)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF264C9A).withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: selected ? const Color(0xFF4F63CF) : const Color(0xFF506178),
            size: 21,
          ),
        ),
      ),
    );
  }
}

class _DarkCard extends StatelessWidget {
  const _DarkCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDCE6F2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF17376D).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _ChatInfoRow extends StatelessWidget {
  const _ChatInfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: destructive
                      ? const Color(0xFFE55837)
                      : const Color(0xFF0B1730),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatInfoMediaSection extends StatelessWidget {
  const _ChatInfoMediaSection({required this.media, required this.onTap});

  final List<ChatMessage> media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.image_rounded, color: Color(0xFF29C46A), size: 21),
                SizedBox(width: 12),
                Text(
                  '\uC0AC\uC9C4/\uB3D9\uC601\uC0C1',
                  style: TextStyle(
                    color: Color(0xFF0B1730),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            if (media.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    final attachment = media[index].attachment;
                    return SizedBox.square(
                      dimension: 56,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: attachment != null && attachment.isImage
                            ? _AttachmentImagePreview(attachment: attachment)
                            : const ColoredBox(color: Color(0xFFE9EEF5)),
                      ),
                    );
                  },
                  separatorBuilder: (_, index) => const SizedBox(width: 4),
                  itemCount: media.length,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChatParticipantRow extends StatelessWidget {
  const _ChatParticipantRow({required this.profile});

  final PersonProfile profile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          ProfileAvatar(profile: profile, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              profile.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF0B1730),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomAvatarCluster extends StatelessWidget {
  const _RoomAvatarCluster({required this.room});

  final ChatRoom room;

  @override
  Widget build(BuildContext context) {
    final members = room.members.take(4).toList();
    if (members.length <= 1) {
      return ProfileAvatar(
        profile: members.isEmpty
            ? PersonProfile(name: room.title, color: const Color(0xFF8FD4E3))
            : members.first,
        size: 72,
      );
    }
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        children: [
          for (final entry in members.indexed)
            Positioned(
              left: entry.$1.isEven ? 2 : 42,
              top: entry.$1 < 2 ? 2 : 42,
              child: ProfileAvatar(profile: entry.$2, size: 40),
            ),
        ],
      ),
    );
  }
}

class _CameraCaptureConfirmDialog extends StatelessWidget {
  const _CameraCaptureConfirmDialog({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(path),
                width: 260,
                height: 260,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('\uCDE8\uC18C'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4663CF),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('\uC804\uC1A1'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceMessageSheet extends StatefulWidget {
  const _VoiceMessageSheet();

  @override
  State<_VoiceMessageSheet> createState() => _VoiceMessageSheetState();
}

class _VoiceMessageSheetState extends State<_VoiceMessageSheet> {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  int _elapsedSeconds = 0;
  String? _path;
  bool _recording = false;
  bool _recorded = false;

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _start() async {
    final permitted = await _recorder.hasPermission();
    if (!permitted) {
      if (mounted) {
        showAvaToast(
          context,
          '\uB9C8\uC774\uD06C \uAD8C\uD55C\uC774 \uD544\uC694\uD569\uB2C8\uB2E4',
        );
      }
      return;
    }
    final directory = Directory.systemTemp;
    final path =
        '${directory.path}${Platform.pathSeparator}ava_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsedSeconds++);
      }
    });
    setState(() {
      _path = path;
      _recording = true;
      _recorded = false;
      _elapsedSeconds = 0;
    });
  }

  Future<void> _stop() async {
    final path = await _recorder.stop();
    _timer?.cancel();
    setState(() {
      _path = path ?? _path;
      _recording = false;
      _recorded = true;
    });
  }

  Future<void> _send() async {
    final path = _path;
    if (path == null || path.isEmpty) {
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        showAvaToast(
          context,
          '\uB179\uC74C \uD30C\uC77C\uC744 \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4',
        );
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).pop(
        _SelectedUploadFile(
          path: path,
          name: path.split(RegExp(r'[\\/]')).last,
          size: await file.length(),
        ),
      );
    }
  }

  String _timeLabel() {
    final minutes = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, 14, bottom + 12),
      decoration: const BoxDecoration(
        color: Color(0xFF202124),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF5E6065),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '\uC74C\uC131\uBA54\uC2DC\uC9C0',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _recording || _recorded
                  ? const Color(0xFFFFDF00)
                  : const Color(0xFF3A3B3D),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                if (_recorded)
                  const Icon(Icons.play_arrow, color: Colors.black, size: 20),
                Expanded(
                  child: CustomPaint(
                    painter: _VoiceWavePainter(active: _recording || _recorded),
                    child: const SizedBox(height: 24),
                  ),
                ),
                Text(
                  _timeLabel(),
                  style: TextStyle(
                    color: _recording || _recorded
                        ? Colors.black
                        : const Color(0xFFBFC1C5),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  '\uCDE8\uC18C',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: _recording
                      ? const Color(0xFFE9E9E9)
                      : const Color(0xFFFF744C),
                  foregroundColor: _recording ? Colors.black : Colors.white,
                ),
                onPressed: _recording ? _stop : _start,
                icon: Icon(_recording ? Icons.stop : Icons.circle),
              ),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFFFDF00),
                  foregroundColor: Colors.black,
                ),
                onPressed: _recorded ? _send : null,
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
          const Divider(color: Color(0xFF303236), height: 24),
          Row(
            children: [
              const Icon(Icons.radio_button_unchecked, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                '\uAC04\uD3B8\uB179\uC74C \uBC84\uD2BC \uC0AC\uC6A9',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.86),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VoiceWavePainter extends CustomPainter {
  const _VoiceWavePainter({
    required this.active,
    this.activeColor = Colors.black,
    this.inactiveColor = const Color(0xFFBFC1C5),
  });

  final bool active;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = active ? activeColor : inactiveColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final count = 28;
    for (var i = 0; i < count; i++) {
      final x = size.width * (i + 0.5) / count;
      final factor = 0.25 + 0.75 * math.sin(i * 0.72).abs();
      final h = size.height * factor;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWavePainter oldDelegate) {
    return oldDelegate.active != active ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}

class _LeaveRoomConfirmDialog extends StatelessWidget {
  const _LeaveRoomConfirmDialog({required this.roomTitle});

  final String roomTitle;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('\uCC44\uD305\uBC29 \uB098\uAC00\uAE30'),
      content: Text(
        '$roomTitle\uC5D0\uC11C \uB098\uAC00\uC2DC\uACA0\uC2B5\uB2C8\uAE4C?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('\uCDE8\uC18C'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('\uB098\uAC00\uAE30'),
        ),
      ],
    );
  }
}

class _InviteMembersResult {
  const _InviteMembersResult({required this.userIds, this.title});

  final List<String> userIds;
  final String? title;
}

class _InviteMembersDialog extends StatefulWidget {
  const _InviteMembersDialog({
    required this.users,
    this.showTitleField = false,
  });

  final List<PersonProfile> users;
  final bool showTitleField;

  @override
  State<_InviteMembersDialog> createState() => _InviteMembersDialogState();
}

class _InviteMembersDialogState extends State<_InviteMembersDialog> {
  final Set<String> _selectedIds = {};
  final TextEditingController _titleController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  bool get _canSubmit => _selectedIds.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430, maxHeight: 560),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFF),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 30,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 16, 14),
                child: Row(
                  children: [
                    const Icon(
                      Icons.person_add_alt_1_rounded,
                      color: Color(0xFF4F63CF),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '\uCD08\uB300\uD558\uAE30',
                        style: TextStyle(
                          color: Color(0xFF0B1730),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF506178),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFDCE6F2)),
              if (widget.showTitleField)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                  child: TextField(
                    controller: _titleController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      color: Color(0xFF0B1730),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          '\uCC44\uD305\uBC29 \uC774\uB984 (\uC120\uD0DD)',
                      hintStyle: const TextStyle(
                        color: Color(0xFF96A4B7),
                        fontWeight: FontWeight.w700,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(
                        Icons.edit_note_rounded,
                        color: Color(0xFF4F63CF),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFD5E0EF)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: Color(0xFF4F63CF),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  itemCount: widget.users.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final user = widget.users[index];
                    final userId = user.id;
                    final enabled = userId != null && userId.isNotEmpty;
                    final selected = enabled && _selectedIds.contains(userId);
                    return Material(
                      color: selected ? const Color(0xFFE9F0FF) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: !enabled
                            ? null
                            : () => setState(() {
                                if (selected) {
                                  _selectedIds.remove(userId);
                                } else {
                                  _selectedIds.add(userId);
                                }
                              }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              ProfileAvatar(profile: user, size: 42),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF0B1730),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    if ((user.department ?? '').isNotEmpty ||
                                        (user.position ?? '').isNotEmpty)
                                      Text(
                                        [
                                          if ((user.department ?? '')
                                              .isNotEmpty)
                                            user.department!,
                                          if ((user.position ?? '').isNotEmpty)
                                            user.position!,
                                        ].join(' ??'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF738299),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                color: selected
                                    ? const Color(0xFF4F63CF)
                                    : const Color(0xFFB6C1CF),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4F63CF),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFD8DFEC),
                      disabledForegroundColor: const Color(0xFF7E8EA6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: !_canSubmit
                        ? null
                        : () => Navigator.of(context).pop(
                            _InviteMembersResult(
                              userIds: _selectedIds.toList(growable: false),
                              title: _titleController.text.trim(),
                            ),
                          ),
                    child: Text(
                      widget.showTitleField
                          ? '\uC0C8 \uCC44\uD305\uBC29 \uB9CC\uB4E4\uAE30'
                          : '\uCD08\uB300\uD558\uAE30',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
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
              '${message.sender.name} ??${message.time}',
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
                child: const Text('\uC811\uAE30'),
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
            '\uBA54\uC2DC\uC9C0 \uC635\uC158\uC774 \uC801\uC6A9\uB418\uC5C8\uC2B5\uB2C8\uB2E4.',
            style: TextStyle(
              color: Colors.black,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '\uD544\uC694\uD55C \uACBD\uC6B0 \uC544\uB798 \uBC84\uD2BC\uC73C\uB85C \uC635\uC158\uC744 \uC811\uC744 \uC218 \uC788\uC2B5\uB2C8\uB2E4.',
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
              child: const Text('\uC811\uAE30'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageDeleteModeDialog extends StatefulWidget {
  const _MessageDeleteModeDialog();

  @override
  State<_MessageDeleteModeDialog> createState() =>
      _MessageDeleteModeDialogState();
}

class _MessageDeleteModeDialogState extends State<_MessageDeleteModeDialog> {
  _MessageDeleteMode _mode = _MessageDeleteMode.forEveryone;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFF2F7FC),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text(
        '\uBA54\uC2DC\uC9C0 \uC0AD\uC81C',
        style: TextStyle(
          color: Color(0xFF0B1730),
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DeleteOptionTile(
            label: '\uBAA8\uB450\uC5D0\uAC8C\uC11C \uC0AD\uC81C',
            selected: _mode == _MessageDeleteMode.forEveryone,
            onTap: () => setState(() => _mode = _MessageDeleteMode.forEveryone),
          ),
          _DeleteOptionTile(
            label: '\uB098\uC5D0\uAC8C\uC11C\uB9CC \uC0AD\uC81C',
            selected: _mode == _MessageDeleteMode.forMe,
            onTap: () => setState(() => _mode = _MessageDeleteMode.forMe),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('\uCDE8\uC18C'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_mode),
          child: const Text('\uD655\uC778'),
        ),
      ],
    );
  }
}

class _DeleteOptionTile extends StatelessWidget {
  const _DeleteOptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF0B1730),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected
                  ? const Color(0xFF2FAF72)
                  : const Color(0xFF7C8D9C),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageDeleteForMeDialog extends StatelessWidget {
  const _MessageDeleteForMeDialog({required this.messageLabel});

  final String messageLabel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFF2F7FC),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text(
        '\uBA54\uC2DC\uC9C0 \uC0AD\uC81C',
        style: TextStyle(
          color: Color(0xFF0B1730),
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
      content: const Text(
        '\uC774 \uBA54\uC2DC\uC9C0\uB97C \uB098\uC5D0\uAC8C\uC11C\uB9CC \uC0AD\uC81C\uD560\uAE4C\uC694?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('\uCDE8\uC18C'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('\uD655\uC778'),
        ),
      ],
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
      onLongPressStart: (details) {
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
                      _MessageMeta(
                        time: first.time,
                        unreadCount: first.unreadCount,
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                _MessageMeta(
                  time: first.time,
                  unreadCount: first.unreadCount,
                  crossAxisAlignment: CrossAxisAlignment.end,
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

class _MessageMeta extends StatelessWidget {
  const _MessageMeta({
    required this.time,
    required this.unreadCount,
    required this.crossAxisAlignment,
  });

  final String time;
  final int unreadCount;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        if (unreadCount > 0)
          Text(
            '$unreadCount',
            key: ValueKey('message-unread-count-$unreadCount'),
            style: const TextStyle(
              color: Color(0xFFFFF263),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        Text(
          time,
          style: const TextStyle(color: Color(0xFF4D6370), fontSize: 10),
        ),
      ],
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
    required this.searchQuery,
    required this.onContextMenu,
    super.key,
  });

  final ChatMessage message;
  final String searchQuery;
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
            searchQuery: widget.searchQuery,
            onRevealSpoiler: () => setState(() => _spoilerRevealed = true),
          )
        : _OtherMessage(
            message: message,
            searchQuery: widget.searchQuery,
            onRevealSpoiler: () => setState(() => _spoilerRevealed = true),
          );

    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTapDown: (details) {
        widget.onContextMenu(widget.message, details.globalPosition);
      },
      onLongPressStart: (details) {
        widget.onContextMenu(widget.message, details.globalPosition);
      },
      child: child,
    );
  }
}

class _OtherMessage extends ConsumerWidget {
  const _OtherMessage({
    required this.message,
    required this.searchQuery,
    required this.onRevealSpoiler,
  });

  final ChatMessage message;
  final String searchQuery;
  final VoidCallback onRevealSpoiler;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = ref
        .watch(authControllerProvider)
        .value
        ?.session
        ?.user
        .id;
    final highlightMentions = message.mentionsUser(currentUserId);
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
                            mentions: message.mentions,
                            highlightMentions: highlightMentions,
                            searchQuery: searchQuery,
                            onRevealSpoiler: onRevealSpoiler,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _MessageMeta(
                        time: message.time,
                        unreadCount: message.unreadCount,
                        crossAxisAlignment: CrossAxisAlignment.start,
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
  const _MineMessage({
    required this.message,
    required this.searchQuery,
    required this.onRevealSpoiler,
  });

  final ChatMessage message;
  final String searchQuery;
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
                _MessageMeta(
                  time: message.time,
                  unreadCount: message.unreadCount,
                  crossAxisAlignment: CrossAxisAlignment.end,
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
                  mentions: message.mentions,
                  highlightMentions: false,
                  searchQuery: searchQuery,
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
    required this.mentions,
    required this.highlightMentions,
    required this.searchQuery,
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
  final List<ChatMention> mentions;
  final bool highlightMentions;
  final String searchQuery;
  final VoidCallback onRevealSpoiler;

  @override
  Widget build(BuildContext context) {
    final shouldBlur = isSpoiler && !spoilerRevealed;
    final currentAttachment = attachment;
    if (currentAttachment == null &&
        text == '\uC0AD\uC81C\uB41C \uBA54\uC2DC\uC9C0\uC785\uB2C8\uB2E4') {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFE7EEF5),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(8),
            topRight: const Radius.circular(8),
            bottomLeft: Radius.circular(isMine ? 8 : 2),
            bottomRight: Radius.circular(isMine ? 2 : 8),
          ),
          border: Border.all(color: const Color(0xFFD1DFEC)),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Text(
            '\uC0AD\uC81C\uB41C \uBA54\uC2DC\uC9C0\uC785\uB2C8\uB2E4',
            style: TextStyle(
              color: Color(0xFF6A7C8D),
              fontSize: 13,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    final stickerId = currentAttachment == null
        ? _stickerIdFromText(text)
        : null;
    final link = currentAttachment == null && stickerId == null
        ? _firstLink(text)
        : null;
    final hasLink = link != null;
    Widget content;
    if (currentAttachment != null) {
      content = currentAttachment.isVideo
          ? _VideoBubbleContent(
              attachment: currentAttachment,
              senderName: senderName,
              sentAt: sentAt,
            )
          : currentAttachment.isAudio
          ? _VoiceMessageBubbleContent(attachment: currentAttachment)
          : _AttachmentBubbleContent(
              attachment: currentAttachment,
              senderName: senderName,
              sentAt: sentAt,
            );
    } else if (stickerId != null) {
      content = _ChatStickerBubble(stickerId: stickerId);
    } else {
      final textWidget = _MentionText(
        text: text,
        mentions: mentions,
        highlight: highlightMentions,
        searchQuery: searchQuery,
      );
      content = link == null
          ? textWidget
          : _LinkPreviewCard(url: link, dark: true, bubble: true);
      if (shouldBlur) {
        content = ClipRect(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 3.4, sigmaY: 3.4),
            child: content,
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
              ? stickerId == null
                    ? hasLink
                          ? Colors.transparent
                          : color
                    : Colors.transparent
              : currentAttachment.isVideo
              ? Colors.transparent
              : currentAttachment.isAudio
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
              ? stickerId == null
                    ? hasLink
                          ? EdgeInsets.zero
                          : const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 7,
                            )
                    : EdgeInsets.zero
              : currentAttachment.isVideo
              ? EdgeInsets.zero
              : currentAttachment.isAudio
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: content,
        ),
      ),
    );
  }
}

class _MentionText extends StatelessWidget {
  const _MentionText({
    required this.text,
    required this.mentions,
    required this.highlight,
    required this.searchQuery,
  });

  final String text;
  final List<ChatMention> mentions;
  final bool highlight;
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    final baseStyle = const TextStyle(
      color: Colors.black,
      fontSize: 13,
      height: 1.28,
    );
    final ranges = _styleRanges(text, mentions, searchQuery);
    if (ranges.isEmpty) {
      return Text(text, softWrap: true, style: baseStyle);
    }

    final mentionStyle = baseStyle.copyWith(
      color: const Color(0xFF1268B3),
      fontWeight: FontWeight.w700,
      backgroundColor: highlight ? const Color(0xFFD8EAFB) : null,
    );
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final range in ranges) {
      if (range.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, range.start)));
      }
      final isMention = range.type == _TextRangeType.mention;
      spans.add(
        TextSpan(
          text: text.substring(range.start, range.end),
          style: isMention
              ? mentionStyle.copyWith(
                  backgroundColor: range.highlightSearch
                      ? const Color(0xFFFFF59D)
                      : mentionStyle.backgroundColor,
                )
              : baseStyle.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                  backgroundColor: const Color(0xFFFFF59D),
                ),
        ),
      );
      cursor = range.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
      softWrap: true,
    );
  }

  List<_StyledTextRange> _styleRanges(
    String text,
    List<ChatMention> mentions,
    String searchQuery,
  ) {
    final ranges = <_StyledTextRange>[];
    final labels = mentions
        .map((mention) => mention.displayName.trim())
        .where((name) => name.isNotEmpty)
        .map((name) => '@$name')
        .toSet();
    for (final label in labels) {
      var index = text.indexOf(label);
      while (index >= 0) {
        ranges.add(
          _StyledTextRange(index, index + label.length, _TextRangeType.mention),
        );
        index = text.indexOf(label, index + label.length);
      }
    }
    final query = searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      final lowerText = text.toLowerCase();
      var index = lowerText.indexOf(query);
      while (index >= 0) {
        ranges.add(
          _StyledTextRange(index, index + query.length, _TextRangeType.search),
        );
        index = lowerText.indexOf(query, index + query.length);
      }
    }
    ranges.sort((a, b) => a.start.compareTo(b.start));
    final merged = <_StyledTextRange>[];
    for (final range in ranges) {
      if (merged.isNotEmpty && range.start < merged.last.end) {
        final previous = merged.last;
        if (previous.type == _TextRangeType.mention &&
            range.type == _TextRangeType.search) {
          merged[merged.length - 1] = previous.copyWith(highlightSearch: true);
        }
        continue;
      }
      merged.add(range);
    }
    return merged;
  }
}

enum _TextRangeType { mention, search }

class _StyledTextRange {
  const _StyledTextRange(
    this.start,
    this.end,
    this.type, {
    this.highlightSearch = false,
  });

  final int start;
  final int end;
  final _TextRangeType type;
  final bool highlightSearch;

  _StyledTextRange copyWith({bool? highlightSearch}) {
    return _StyledTextRange(
      start,
      end,
      type,
      highlightSearch: highlightSearch ?? this.highlightSearch,
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
      unawaited(_rememberAttachmentLocalPath(widget.attachment, localPath));
      return;
    }
    _localPath = null;
    _savedAt = null;
    _duration = null;
    unawaited(_hydrateRememberedLocalPath(widget.attachment.id));
  }

  Future<void> _hydrateRememberedLocalPath(String attachmentId) async {
    final path = await _rememberedAttachmentLocalPath(widget.attachment);
    if (!mounted || attachmentId != widget.attachment.id) {
      return;
    }
    if (path == null || path.isEmpty || !await File(path).exists()) {
      return;
    }
    setState(() {
      _localPath = path;
      _savedAt = DateTime.now();
    });
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
      showAvaToast(
        context,
        '\uB85C\uADF8\uC778\uC774 \uD544\uC694\uD569\uB2C8\uB2E4.',
      );
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
      unawaited(_rememberAttachmentLocalPath(widget.attachment, targetPath));
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
      showAvaToast(
        context,
        '\uBA3C\uC800 \uB3D9\uC601\uC0C1\uC744 \uB2E4\uC6B4\uB85C\uB4DC\uD574\uC8FC\uC138\uC694.',
      );
      return;
    }
    final opened = await _showAvaVideoViewer(
      path: path,
      fileName: widget.attachment.fileName,
      senderName: widget.senderName,
      sentAt: widget.sentAt ?? _savedAt ?? DateTime.now(),
    );
    if (!opened && mounted) {
      showAvaToast(
        context,
        '\uB3D9\uC601\uC0C1\uC744 \uC5F4 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.',
      );
    }
  }

  Future<void> _openMobileVideoViewer() async {
    if (_isSaving || widget.attachment.transferInProgress) {
      return;
    }

    String? path = _localPath;
    if (path == null || path.isEmpty || !await File(path).exists()) {
      if (!mounted) {
        return;
      }
      final session = ref.read(authControllerProvider).value?.session;
      if (session == null || session.accessToken.isEmpty) {
        showAvaToast(
          context,
          '\uB85C\uADF8\uC778\uC774 \uD544\uC694\uD569\uB2C8\uB2E4.',
        );
        return;
      }
      setState(() {
        _isSaving = true;
        _progress = 0;
      });
      try {
        path = await _downloadAttachmentToTemp(
          ref,
          widget.attachment,
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
        final downloadedPath = path;
        final hasDownloadedFile =
            downloadedPath != null &&
            downloadedPath.isNotEmpty &&
            await File(downloadedPath).exists();
        if (!mounted) {
          return;
        }
        if (!hasDownloadedFile) {
          showAvaToast(
            context,
            '\uB3D9\uC601\uC0C1\uC744 \uBD88\uB7EC\uC624\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.',
          );
          return;
        }
        path = downloadedPath;
        setState(() {
          _localPath = path;
          _savedAt = DateTime.now();
          _progress = 1;
        });
        unawaited(_rememberAttachmentLocalPath(widget.attachment, path));
      } on Object catch (error) {
        if (mounted) {
          showAvaToast(context, authErrorMessage(error));
        }
        return;
      } finally {
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
    }

    final videoPath = path;
    if (!mounted || videoPath.isEmpty) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _MobileVideoViewerPage(
          attachment: widget.attachment.copyWith(
            localPath: videoPath,
            cachedAt: _savedAt ?? DateTime.now(),
          ),
          localPath: videoPath,
          senderName: widget.senderName,
          sentAt: widget.sentAt ?? _savedAt ?? DateTime.now(),
        ),
      ),
    );
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
          : !Platform.isWindows
          ? _openMobileVideoViewer
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
                  onTap: !Platform.isWindows
                      ? _openMobileVideoViewer
                      : hasLocalVideo
                      ? _playVideo
                      : _saveVideo,
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
  VideoPlayerController? _previewController;
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

  @override
  void dispose() {
    _previewController?.dispose();
    super.dispose();
  }

  Future<void> _loadThumbnail() async {
    if (_isLoading) {
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
    if (_loadedSource == localPath &&
        _previewController?.value.isInitialized == true) {
      return;
    }

    _isLoading = true;
    try {
      if (!Platform.isWindows) {
        final controller = VideoPlayerController.file(File(localPath));
        await controller.initialize();
        await controller.pause();
        await controller.seekTo(Duration.zero);
        if (!mounted) {
          await controller.dispose();
          return;
        }
        final previous = _previewController;
        widget.onDurationChanged(controller.value.duration);
        setState(() {
          _previewController = controller;
          _thumbnailFile = null;
          _loadedSource = localPath;
        });
        await previous?.dispose();
        return;
      }
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
        final previous = _previewController;
        setState(() {
          _thumbnailFile = File(thumbnailPath);
          _previewController = null;
          _loadedSource = localPath;
        });
        await previous?.dispose();
      } else {
        final previous = _previewController;
        setState(() {
          _thumbnailFile = null;
          _previewController = null;
          _loadedSource = localPath;
        });
        await previous?.dispose();
      }
    } on Object {
      if (mounted) {
        final previous = _previewController;
        setState(() {
          _thumbnailFile = null;
          _previewController = null;
          _loadedSource = localPath;
        });
        await previous?.dispose();
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
        unawaited(_rememberAttachmentLocalPath(widget.attachment, previewPath));
        return previewPath;
      }
      await ref
          .read(chatApiProvider)
          .downloadAttachment(
            accessToken: accessToken,
            downloadUrl: widget.attachment.downloadUrl,
            savePath: previewPath,
          );
      await _rememberAttachmentLocalPath(widget.attachment, previewPath);
      return previewPath;
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _previewController;
    if (controller != null && controller.value.isInitialized) {
      final size = controller.value.size;
      if (size.width > 0 && size.height > 0) {
        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(controller),
          ),
        );
      }
    }
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

class _VoiceMessageBubbleContent extends ConsumerStatefulWidget {
  const _VoiceMessageBubbleContent({required this.attachment});

  final ChatAttachment attachment;

  @override
  ConsumerState<_VoiceMessageBubbleContent> createState() =>
      _VoiceMessageBubbleContentState();
}

class _VoiceMessageBubbleContentState
    extends ConsumerState<_VoiceMessageBubbleContent> {
  String? _localPath;
  DateTime? _cachedAt;
  bool _isLoading = false;
  bool _isPlaying = false;
  Duration _elapsed = Duration.zero;
  Duration? _duration;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.attachment.hasFreshLocalFile) {
      _localPath = widget.attachment.localPath;
      _cachedAt = widget.attachment.cachedAt;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_isPlaying) {
      unawaited(_MobileAudioPlayback.stop());
    }
    super.dispose();
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

  Future<String?> _ensureLocalFile() async {
    if (_hasFreshLocalFile) {
      return _localPath;
    }
    final path = await _downloadAttachmentToTemp(ref, widget.attachment);
    if (path == null || path.isEmpty || !await File(path).exists()) {
      return null;
    }
    if (mounted) {
      setState(() {
        _localPath = path;
        _cachedAt = DateTime.now();
      });
    }
    return path;
  }

  Future<void> _togglePlayback() async {
    if (_isLoading) {
      return;
    }
    if (_isPlaying) {
      await _stopPlayback(resetElapsed: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final path = await _ensureLocalFile();
      if (!mounted) {
        return;
      }
      if (path == null) {
        showAvaToast(
          context,
          '\uC74C\uC131\uBA54\uC2DC\uC9C0\uB97C \uBD88\uB7EC\uC624\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.',
        );
        return;
      }
      if (!Platform.isAndroid) {
        showAvaToast(
          context,
          '\uBAA8\uBC14\uC77C\uC5D0\uC11C\uB9CC \uC74C\uC131\uBA54\uC2DC\uC9C0 \uC7AC\uC0DD\uC744 \uC9C0\uC6D0\uD569\uB2C8\uB2E4.',
        );
        return;
      }
      final duration = await _MobileAudioPlayback.play(path);
      if (!mounted) {
        return;
      }
      setState(() {
        _duration = duration;
        _elapsed = Duration.zero;
        _isPlaying = true;
      });
      _startTimer();
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || !_isPlaying) {
        return;
      }
      final next = _elapsed + const Duration(milliseconds: 250);
      final duration = _duration;
      if (duration != null && duration > Duration.zero && next >= duration) {
        unawaited(_stopPlayback(resetElapsed: true));
        return;
      }
      setState(() => _elapsed = next);
    });
  }

  Future<void> _stopPlayback({required bool resetElapsed}) async {
    _timer?.cancel();
    _timer = null;
    await _MobileAudioPlayback.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _isPlaying = false;
      if (resetElapsed) {
        _elapsed = Duration.zero;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final durationLabel = _isPlaying
        ? _formatVideoDuration(_elapsed)
        : _formatFileSize(widget.attachment.size);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlayback,
      child: Container(
        width: 238,
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF2F3033),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 34,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Icon(
                        _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: CustomPaint(
                painter: _VoiceWavePainter(
                  active: _isPlaying,
                  activeColor: Colors.white,
                  inactiveColor: const Color(0xFFBFC1C5),
                ),
                child: const SizedBox(height: 28),
              ),
            ),
            const SizedBox(width: 9),
            Text(
              durationLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentBubbleContent extends ConsumerStatefulWidget {
  const _AttachmentBubbleContent({
    required this.attachment,
    required this.senderName,
    required this.sentAt,
  });

  final ChatAttachment attachment;
  final String senderName;
  final DateTime? sentAt;

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
      showAvaToast(
        context,
        '\uB85C\uADF8\uC778\uC774 \uD544\uC694\uD569\uB2C8\uB2E4.',
      );
      return;
    }
    setState(() {
      _isDownloading = true;
      _progress = 0;
    });
    try {
      var localPath = _hasFreshLocalFile ? _localPath : null;
      localPath ??= await _downloadAttachmentToTemp(
        ref,
        widget.attachment,
        onReceiveProgress: (received, total) {
          if (!mounted || total <= 0) {
            return;
          }
          setState(() {
            _progress = (received / total).clamp(0, 1).toDouble();
          });
        },
      );
      if (localPath == null ||
          localPath.isEmpty ||
          !await File(localPath).exists()) {
        if (mounted) {
          showAvaToast(
            context,
            '\uD30C\uC77C\uC744 \uB2E4\uC6B4\uB85C\uB4DC\uD558\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.',
          );
        }
        return;
      }
      var openPath = localPath;
      if (Platform.isAndroid) {
        await WindowControl.saveAttachmentToMediaStore(
          sourcePath: localPath,
          fileName: widget.attachment.fileName,
          mimeType: widget.attachment.contentType,
          notify: true,
        );
      } else if (Platform.isWindows) {
        final downloads = await _downloadsDirectory();
        if (!_isPathInDirectory(localPath, downloads)) {
          openPath = await _nextDownloadPath(widget.attachment.fileName);
          await File(localPath).copy(openPath);
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _localPath = openPath;
        _cachedAt = DateTime.now();
        _progress = 1;
      });
      showAvaToast(
        context,
        '\uB2E4\uC6B4\uB85C\uB4DC\uAC00 \uC644\uB8CC\uB418\uC5C8\uC2B5\uB2C8\uB2E4.',
      );
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
      showAvaToast(
        context,
        '\uD30C\uC77C\uC744 \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.',
      );
      return;
    }
    if (Platform.isWindows) {
      await Process.run('rundll32.exe', ['url.dll,FileProtocolHandler', path]);
    } else {
      showAvaToast(
        context,
        '\uD30C\uC77C \uC5F4\uAE30\uB294 Windows\uC5D0\uC11C\uB9CC \uC9C0\uC6D0\uB429\uB2C8\uB2E4.',
      );
    }
  }

  Future<void> _openMobileFileViewer() async {
    final path = await _ensureDownloadsLocalPath();
    if (!mounted) {
      return;
    }
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      showAvaToast(
        context,
        '\uBA3C\uC800 \uD30C\uC77C\uC744 \uB2E4\uC6B4\uB85C\uB4DC\uD574\uC8FC\uC138\uC694.',
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _MobileFileViewerPage(
          attachment: widget.attachment.copyWith(
            localPath: path,
            cachedAt: _cachedAt ?? DateTime.now(),
          ),
          localPath: path,
          senderName: widget.senderName,
          sentAt: widget.sentAt ?? _cachedAt ?? DateTime.now(),
        ),
      ),
    );
  }

  Future<void> _openFolder() async {
    final path = await _ensureDownloadsLocalPath();
    if (!mounted) {
      return;
    }
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      showAvaToast(
        context,
        '\uD30C\uC77C\uC744 \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.',
      );
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
      showAvaToast(
        context,
        '\uD30C\uC77C \uC704\uCE58 \uC5F4\uAE30\uB294 Windows\uC5D0\uC11C\uB9CC \uC9C0\uC6D0\uB429\uB2C8\uB2E4.',
      );
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
    if (!Platform.isWindows) {
      return path;
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
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    if (isMobile) {
      return SizedBox(
        width: 236,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.insert_drive_file_rounded,
              size: 34,
              color: Color(0xFF7EB1D4),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: canOpen ? _openMobileFileViewer : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.attachment.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF0B1730),
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\uC720\uD6A8\uAE30\uAC04 ~${_expiryLabel()}',
                      style: const TextStyle(
                        color: Color(0xFF6A7C8D),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '\uC6A9\uB7C9 ${_formatFileSize(widget.attachment.size)}',
                      style: const TextStyle(
                        color: Color(0xFF6A7C8D),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            _AttachmentActionIcon(
              isDownloading: _isDownloading,
              progress: _progress,
              canOpen: canOpen,
              onDownload: _download,
              onOpen: _openMobileFileViewer,
            ),
          ],
        ),
      );
    }
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
                onOpen: Platform.isWindows ? _openFile : _openMobileFileViewer,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '\uC720\uD6A8\uAE30\uAC04 ~${_expiryLabel()}',
            style: const TextStyle(color: Color(0xFF777777), fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            '\uC6A9\uB7C9: ${_formatFileSize(widget.attachment.size)}',
            style: const TextStyle(color: Color(0xFF777777), fontSize: 11),
          ),
          const SizedBox(height: 8),
          if (canOpen)
            Row(
              children: [
                _AttachmentTextButton(label: '\uC5F4\uAE30', onTap: _openFile),
                const Text(
                  ' | ',
                  style: TextStyle(color: Color(0xFF1D63AA), fontSize: 11),
                ),
                _AttachmentTextButton(
                  label: '\uD3F4\uB354 \uC5F4\uAE30',
                  onTap: _openFolder,
                ),
              ],
            )
          else
            _AttachmentTextButton(
              label: _isDownloading
                  ? '\uB2E4\uC6B4\uB85C\uB4DC \uC911'
                  : '\uB2E4\uC6B4\uB85C\uB4DC',
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
    required this.onOpen,
  });

  final bool isDownloading;
  final double progress;
  final bool canOpen;
  final VoidCallback onDownload;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (canOpen) {
      return IconButton(
        onPressed: onOpen,
        padding: EdgeInsets.zero,
        tooltip: '\uC5F4\uAE30',
        icon: const Icon(
          Icons.inventory_2_outlined,
          size: 30,
          color: Color(0xFF6C7B89),
        ),
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
    required this.onAttachImages,
    required this.onAttachVideos,
    required this.onCaptureCamera,
    required this.onSendVoiceMessage,
    required this.onTypingChanged,
    required this.enabled,
    required this.members,
    required this.currentUserId,
    this.mobileLayout = false,
  });

  final Future<void> Function(String content, [_SendOptions options]) onSend;
  final VoidCallback onAttachFiles;
  final VoidCallback onAttachImages;
  final VoidCallback onAttachVideos;
  final VoidCallback onCaptureCamera;
  final Future<void> Function(_SelectedUploadFile file) onSendVoiceMessage;
  final ValueChanged<bool> onTypingChanged;
  final bool enabled;
  final List<PersonProfile> members;
  final String? currentUserId;
  final bool mobileLayout;

  @override
  State<_MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<_MessageComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  Timer? _typingStopTimer;
  Timer? _mentionBlurTimer;
  bool _canSend = false;
  bool _isSending = false;
  bool _isTyping = false;
  bool _mobileToolsOpen = false;
  bool _emojiPanelOpen = false;
  double _transparency = 0;
  _MentionQuery? _mentionQuery;
  String? _previewStickerId;
  final List<String> _recentStickerIds = <String>[];
  final Map<String, ChatMentionDto> _selectedMentions = {};

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChanged);
    _textFocusNode.addListener(_handleFocusChanged);
    unawaited(_loadRecentStickerIds());
  }

  @override
  void didUpdateWidget(covariant _MessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUserId != widget.currentUserId) {
      _recentStickerIds.clear();
      unawaited(_loadRecentStickerIds());
    }
    if (!widget.enabled && oldWidget.enabled) {
      _setTyping(false);
      _controller.clear();
      _canSend = false;
      _mobileToolsOpen = false;
      _emojiPanelOpen = false;
      _previewStickerId = null;
    }
  }

  @override
  void dispose() {
    _setTyping(false);
    _typingStopTimer?.cancel();
    _mentionBlurTimer?.cancel();
    _controller.removeListener(_handleTextChanged);
    _textFocusNode.removeListener(_handleFocusChanged);
    _textFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  String get _recentStickerStorageKey {
    final userKey = (widget.currentUserId?.trim().isNotEmpty ?? false)
        ? widget.currentUserId!.trim()
        : 'anonymous';
    return 'ava.messenger.recent_stickers.$userKey';
  }

  Future<void> _loadRecentStickerIds() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_recentStickerStorageKey) ?? const [];
    final normalized = saved
        .map(_normalizeStickerId)
        .whereType<String>()
        .where((id) => _avaStickerIds.contains(id))
        .toSet()
        .take(16)
        .toList();
    if (!mounted) {
      return;
    }
    setState(() {
      _recentStickerIds
        ..clear()
        ..addAll(normalized);
    });
  }

  Future<void> _saveRecentStickerIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentStickerStorageKey, _recentStickerIds);
  }

  String? _normalizeStickerId(String stickerId) {
    final raw = RegExp(r'(\d+)$').firstMatch(stickerId)?.group(1);
    final number = int.tryParse(raw ?? '');
    if (number == null || number < 1 || number > 30) {
      return null;
    }
    return 'kakao_friends_${number.toString().padLeft(2, '0')}';
  }

  void _handleFocusChanged() {
    if (!_textFocusNode.hasFocus && _mentionQuery != null) {
      _mentionBlurTimer?.cancel();
      _mentionBlurTimer = Timer(const Duration(milliseconds: 180), () {
        if (!mounted || _textFocusNode.hasFocus) {
          return;
        }
        setState(() {
          _mentionQuery = null;
        });
      });
    } else if (_textFocusNode.hasFocus) {
      _mentionBlurTimer?.cancel();
    }
    if (_textFocusNode.hasFocus && _emojiPanelOpen) {
      setState(() {
        _emojiPanelOpen = false;
        _previewStickerId = null;
      });
    }
    if (!_textFocusNode.hasFocus || !_mobileToolsOpen) {
      return;
    }
    setState(() {
      _mobileToolsOpen = false;
    });
  }

  void _handleTextChanged() {
    if (!widget.enabled) {
      _setTyping(false);
      return;
    }
    final canSend = _controller.text.trim().isNotEmpty;
    final mentionQuery = _activeMentionQuery();
    if (canSend) {
      _refreshTypingTimer();
    } else {
      _setTyping(false);
    }
    if (canSend == _canSend && mentionQuery == _mentionQuery) {
      return;
    }
    setState(() {
      _canSend = canSend;
      _mentionQuery = mentionQuery;
    });
  }

  _MentionQuery? _activeMentionQuery() {
    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return null;
    }
    final cursor = selection.baseOffset;
    if (cursor <= 0 || cursor > _controller.text.length) {
      return null;
    }
    final text = _controller.text;
    var start = cursor - 1;
    while (start >= 0 && !_isMentionBoundary(text.codeUnitAt(start))) {
      start--;
    }
    start++;
    if (start >= cursor || text[start] != '@') {
      return null;
    }
    return _MentionQuery(
      start: start,
      end: cursor,
      query: text.substring(start + 1, cursor),
    );
  }

  bool _isMentionBoundary(int codeUnit) {
    return codeUnit == 0x20 ||
        codeUnit == 0x09 ||
        codeUnit == 0x0A ||
        codeUnit == 0x0D;
  }

  List<PersonProfile> _mentionSuggestions() {
    final query = _mentionQuery?.query.trim().toLowerCase() ?? '';
    final seen = <String>{};
    final candidates = <PersonProfile>[];
    for (final member in widget.members) {
      final userId = member.id;
      if (userId == null || userId.isEmpty || userId == widget.currentUserId) {
        continue;
      }
      if (!seen.add(userId)) {
        continue;
      }
      final name = _mentionDisplayName(member);
      final haystack = [
        name,
        member.nickname ?? '',
        member.email ?? '',
      ].join(' ').toLowerCase();
      if (query.isEmpty || haystack.contains(query)) {
        candidates.add(member);
      }
    }
    return candidates;
  }

  String _mentionDisplayName(PersonProfile profile) {
    final nickname = profile.nickname?.trim() ?? '';
    if (nickname.isNotEmpty) {
      return nickname;
    }
    return profile.name.trim().isEmpty
        ? (profile.email ?? '')
        : profile.name.trim();
  }

  bool _isUsableMentionQuery(_MentionQuery? query) {
    if (query == null) {
      return false;
    }
    final text = _controller.text;
    if (query.start < 0 ||
        query.end <= query.start ||
        query.end > text.length ||
        text[query.start] != '@') {
      return false;
    }
    for (var i = query.start; i < query.end; i++) {
      if (_isMentionBoundary(text.codeUnitAt(i))) {
        return false;
      }
    }
    return true;
  }

  _MentionQuery? _fallbackMentionQuery() {
    final text = _controller.text;
    if (text.isEmpty) {
      return null;
    }
    final selection = _controller.selection;
    final cursor = selection.isValid
        ? selection.baseOffset.clamp(0, text.length).toInt()
        : text.length;
    var start = text.lastIndexOf('@', cursor);
    if (start < 0 && cursor == text.length) {
      start = text.lastIndexOf('@');
    }
    if (start < 0) {
      return null;
    }
    for (var i = start + 1; i < cursor; i++) {
      if (_isMentionBoundary(text.codeUnitAt(i))) {
        return null;
      }
    }
    if (start > 0 && !_isMentionBoundary(text.codeUnitAt(start - 1))) {
      return null;
    }
    return _MentionQuery(
      start: start,
      end: cursor,
      query: text.substring(start + 1, cursor),
    );
  }

  void _selectMention(PersonProfile profile, {_MentionQuery? queryOverride}) {
    _MentionQuery? query;
    if (_isUsableMentionQuery(queryOverride)) {
      query = queryOverride;
    } else if (_isUsableMentionQuery(_mentionQuery)) {
      query = _mentionQuery;
    } else {
      query = _fallbackMentionQuery();
    }
    if (query == null) {
      return;
    }
    final displayName = _mentionDisplayName(profile);
    if (displayName.isEmpty) {
      return;
    }
    final userId = profile.id?.trim() ?? '';
    _mentionBlurTimer?.cancel();
    final mentionText = '@$displayName ';
    final text = _controller.text.replaceRange(
      query.start,
      query.end,
      mentionText,
    );
    final offset = query.start + mentionText.length;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
    if (userId.isNotEmpty) {
      _selectedMentions[userId] = ChatMentionDto(
        userId: userId,
        displayName: displayName,
      );
    }
    if (mounted) {
      setState(() {
        _mentionQuery = null;
        _mobileToolsOpen = false;
      });
    }
    _handleTextChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _textFocusNode.requestFocus();
      }
    });
  }

  List<ChatMentionDto> _mentionsForContent(String content) {
    final mentions = <String, ChatMentionDto>{};
    for (final mention in _selectedMentions.values) {
      if (content.contains('@${mention.displayName}')) {
        mentions[mention.userId] = mention;
      }
    }
    for (final member in widget.members) {
      final userId = member.id;
      if (userId == null || userId.isEmpty || userId == widget.currentUserId) {
        continue;
      }
      final displayName = _mentionDisplayName(member);
      if (displayName.isEmpty || !content.contains('@$displayName')) {
        continue;
      }
      mentions[userId] = ChatMentionDto(
        userId: userId,
        displayName: displayName,
      );
    }
    return mentions.values.toList();
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
    if (!widget.enabled || _isSending) {
      return;
    }
    final stickerId = _previewStickerId;
    if (stickerId != null) {
      await _sendSticker(stickerId);
      return;
    }
    if (!_canSend) {
      return;
    }

    final content = _controller.text.trim();
    final mentions = _mentionsForContent(content);
    setState(() {
      _isSending = true;
    });
    try {
      await widget.onSend(content, options.withMentions(mentions));
      if (!mounted) {
        return;
      }
      _setTyping(false);
      _controller.clear();
      _selectedMentions.clear();
      setState(() {
        _canSend = false;
        _mobileToolsOpen = false;
        _emojiPanelOpen = false;
        _mentionQuery = null;
        _previewStickerId = null;
      });
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
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

  void _showReadyToast() {
    final renderBox = context.findRenderObject() as RenderBox?;
    final globalCenter = renderBox?.localToGlobal(
      Offset(renderBox.size.width / 2, -38),
    );
    showAvaToast(context, '\uC900\uBE44\uC911', globalCenter: globalCenter);
  }

  void _toggleMobileTools() {
    if (!widget.enabled) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _mobileToolsOpen = !_mobileToolsOpen;
      if (_mobileToolsOpen) {
        _emojiPanelOpen = false;
        _previewStickerId = null;
      }
    });
  }

  void _toggleEmojiPanel() {
    if (!widget.enabled) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _emojiPanelOpen = !_emojiPanelOpen;
      if (_emojiPanelOpen) {
        _mobileToolsOpen = false;
        _mentionQuery = null;
      } else {
        _previewStickerId = null;
      }
    });
  }

  Future<void> _sendSticker(String stickerId) async {
    if (!widget.enabled || _isSending) {
      return;
    }
    final normalizedStickerId = _normalizeStickerId(stickerId) ?? stickerId;
    setState(() {
      _isSending = true;
    });
    try {
      await widget.onSend(_stickerToken(normalizedStickerId));
      if (!mounted) {
        return;
      }
      _recentStickerIds.remove(normalizedStickerId);
      _recentStickerIds.insert(0, normalizedStickerId);
      if (_recentStickerIds.length > 16) {
        _recentStickerIds.removeRange(16, _recentStickerIds.length);
      }
      unawaited(_saveRecentStickerIds());
      setState(() {
        _emojiPanelOpen = false;
        _previewStickerId = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  void _handleMobileAttachFiles() {
    setState(() {
      _mobileToolsOpen = false;
      _emojiPanelOpen = false;
      _previewStickerId = null;
    });
    widget.onAttachFiles();
  }

  void _handleMobileAttachImages() {
    setState(() {
      _mobileToolsOpen = false;
      _emojiPanelOpen = false;
      _previewStickerId = null;
    });
    widget.onAttachImages();
  }

  void _handleMobileAttachVideos() {
    setState(() {
      _mobileToolsOpen = false;
      _emojiPanelOpen = false;
      _previewStickerId = null;
    });
    widget.onAttachVideos();
  }

  void _handleMobileCaptureCamera() {
    setState(() {
      _mobileToolsOpen = false;
      _emojiPanelOpen = false;
      _previewStickerId = null;
    });
    widget.onCaptureCamera();
  }

  Future<void> _handleMobileVoiceMessage() async {
    setState(() {
      _mobileToolsOpen = false;
      _emojiPanelOpen = false;
      _previewStickerId = null;
    });
    final file = await showModalBottomSheet<_SelectedUploadFile>(
      context: context,
      useSafeArea: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => const _VoiceMessageSheet(),
    );
    if (file != null) {
      await widget.onSendVoiceMessage(file);
    }
  }

  void _handleMobileSchedule() {
    setState(() {
      _mobileToolsOpen = false;
      _emojiPanelOpen = false;
      _previewStickerId = null;
    });
    _showReadyToast();
  }

  @override
  Widget build(BuildContext context) {
    final sendEnabled =
        widget.enabled &&
        (_canSend || _previewStickerId != null) &&
        !_isSending;

    if (widget.mobileLayout) {
      return _buildMobileComposer(context, sendEnabled: sendEnabled);
    }

    final composer = Container(
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
                        focusNode: _textFocusNode,
                        enabled: widget.enabled,
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
                  onPressed: _toggleEmojiPanel,
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
    final mentionQuery = _mentionQuery;
    final mentionSuggestions = mentionQuery == null
        ? const <PersonProfile>[]
        : _mentionSuggestions();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mentionSuggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 28, bottom: 10),
            child: TextFieldTapRegion(
              child: _DesktopMentionPopup(
                users: mentionSuggestions,
                onSelect: (profile) =>
                    _selectMention(profile, queryOverride: mentionQuery),
              ),
            ),
          ),
        if (_emojiPanelOpen && _previewStickerId != null)
          _StickerPreviewCard(
            stickerId: _previewStickerId!,
            compact: false,
            onClose: () => setState(() => _previewStickerId = null),
          ),
        composer,
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _emojiPanelOpen
              ? _EmojiPanel(
                  recentStickerIds: _recentStickerIds,
                  onSendSticker: _sendSticker,
                  previewStickerId: _previewStickerId,
                  onPreviewSticker: (stickerId) =>
                      setState(() => _previewStickerId = stickerId),
                  compact: false,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _buildMobileComposer(
    BuildContext context, {
    required bool sendEnabled,
  }) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final composer = Material(
      key: const ValueKey('mobile-composer-root'),
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 48,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
                child: Row(
                  children: [
                    _MobileComposerCircleButton(
                      key: const ValueKey('mobile-composer-tools-toggle'),
                      icon: _mobileToolsOpen ? Icons.close : Icons.add,
                      tooltip: _mobileToolsOpen
                          ? '\uCCA8\uBD80 \uBA54\uB274 \uB2EB\uAE30'
                          : '\uCCA8\uBD80 \uBA54\uB274 \uC5F4\uAE30',
                      onPressed: _toggleMobileTools,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Container(
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Focus(
                                onKeyEvent: _handleComposerKey,
                                child: TextField(
                                  controller: _controller,
                                  focusNode: _textFocusNode,
                                  enabled: widget.enabled,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 14,
                                  ),
                                  cursorColor: Colors.black,
                                  decoration: const InputDecoration(
                                    hintText: '\uBA54\uC2DC\uC9C0 \uC785\uB825',
                                    hintStyle: TextStyle(
                                      color: Color(0xFF9A9A9A),
                                      fontSize: 14,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.fromLTRB(
                                      12,
                                      8,
                                      8,
                                      8,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            _MobileComposerInlineButton(
                              icon: Icons.sentiment_satisfied_alt_outlined,
                              tooltip: '\uC774\uBAA8\uD2F0\uCF58',
                              onPressed: _toggleEmojiPanel,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    sendEnabled
                        ? _MobileComposerSendButton(
                            isSending: _isSending,
                            onPressed: _handleSend,
                          )
                        : _MobileComposerCircleButton(
                            key: const ValueKey('mobile-composer-hashtag'),
                            icon: Icons.tag,
                            tooltip: '#\uD0DC\uADF8',
                            onPressed: _showReadyToast,
                          ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _mobileToolsOpen
                  ? _MobileComposerToolsMenu(
                      onAttachImages: _handleMobileAttachImages,
                      onAttachVideos: _handleMobileAttachVideos,
                      onCaptureCamera: _handleMobileCaptureCamera,
                      onAttachFiles: _handleMobileAttachFiles,
                      onVoiceMessage: _handleMobileVoiceMessage,
                      onSchedule: _handleMobileSchedule,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
    final mentionQuery = _mentionQuery;
    final mentionSuggestions = mentionQuery == null
        ? const <PersonProfile>[]
        : _mentionSuggestions();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (mentionQuery != null && mentionSuggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextFieldTapRegion(
              child: _MobileMentionPopup(
                users: mentionSuggestions,
                onSelect: (profile) =>
                    _selectMention(profile, queryOverride: mentionQuery),
              ),
            ),
          ),
        if (_emojiPanelOpen && _previewStickerId != null)
          _StickerPreviewCard(
            stickerId: _previewStickerId!,
            compact: true,
            onClose: () => setState(() => _previewStickerId = null),
          ),
        composer,
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _emojiPanelOpen
              ? _EmojiPanel(
                  recentStickerIds: _recentStickerIds,
                  onSendSticker: _sendSticker,
                  previewStickerId: _previewStickerId,
                  onPreviewSticker: (stickerId) =>
                      setState(() => _previewStickerId = stickerId),
                  compact: true,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _MentionQuery {
  const _MentionQuery({
    required this.start,
    required this.end,
    required this.query,
  });

  final int start;
  final int end;
  final String query;

  @override
  bool operator ==(Object other) {
    return other is _MentionQuery &&
        other.start == start &&
        other.end == end &&
        other.query == query;
  }

  @override
  int get hashCode => Object.hash(start, end, query);
}

class _DesktopMentionPopup extends StatefulWidget {
  const _DesktopMentionPopup({required this.users, required this.onSelect});

  final List<PersonProfile> users;
  final ValueChanged<PersonProfile> onSelect;

  @override
  State<_DesktopMentionPopup> createState() => _DesktopMentionPopupState();
}

class _DesktopMentionPopupState extends State<_DesktopMentionPopup> {
  final ScrollController _scrollController = ScrollController();
  int? _hoveredIndex;
  bool _selectionSubmitted = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const popupWidth = 250.0;
    const rowHeight = 55.0;
    final shouldScroll = widget.users.length >= 5;

    return SizedBox(
      width: popupWidth,
      child: Material(
        elevation: 14,
        color: Colors.white,
        shadowColor: const Color(0x66000000),
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFC8C8C8)),
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: RawScrollbar(
              controller: _scrollController,
              thumbVisibility: shouldScroll,
              radius: const Radius.circular(999),
              thickness: 4,
              thumbColor: const Color(0xFFB7B7B7),
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: ListView.builder(
                  controller: _scrollController,
                  primary: false,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: widget.users.length,
                  itemBuilder: (context, index) {
                    final user = widget.users[index];
                    final isHovered = _hoveredIndex == index;
                    final isDefaultHighlighted =
                        _hoveredIndex == null && index == 0;
                    final backgroundColor = isHovered
                        ? const Color(0xFFE8F1FF)
                        : isDefaultHighlighted
                        ? const Color(0xFFEDEDED)
                        : Colors.white;
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onEnter: (_) => _setHoveredIndex(index),
                      onExit: (_) {
                        if (_hoveredIndex == index) {
                          _setHoveredIndex(null);
                        }
                      },
                      child: InkWell(
                        hoverColor: Colors.transparent,
                        splashColor: const Color(0xFFE0E0E0),
                        highlightColor: const Color(0xFFE0E0E0),
                        onTapDown: (_) => _submitSelection(user),
                        onTap: () => _submitSelection(user),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 90),
                          curve: Curves.easeOutCubic,
                          height: rowHeight,
                          color: backgroundColor,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              ProfileAvatar(profile: user, size: 38),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  user.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF111111),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setHoveredIndex(int? index) {
    if (_hoveredIndex == index || !mounted) {
      return;
    }
    setState(() {
      _hoveredIndex = index;
    });
  }

  void _submitSelection(PersonProfile user) {
    if (_selectionSubmitted) {
      return;
    }
    _selectionSubmitted = true;
    widget.onSelect(user);
  }
}

class _MobileMentionPopup extends StatefulWidget {
  const _MobileMentionPopup({required this.users, required this.onSelect});

  final List<PersonProfile> users;
  final ValueChanged<PersonProfile> onSelect;

  @override
  State<_MobileMentionPopup> createState() => _MobileMentionPopupState();
}

class _MobileMentionPopupState extends State<_MobileMentionPopup> {
  final ScrollController _scrollController = ScrollController();
  bool _selectionSubmitted = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shouldScroll = widget.users.length >= 5;

    return Material(
      elevation: 10,
      color: const Color(0xFF2E2E2F),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 210),
        child: RawScrollbar(
          controller: _scrollController,
          thumbVisibility: shouldScroll,
          radius: const Radius.circular(999),
          thickness: 4,
          thumbColor: const Color(0xFF6E6E73),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: ListView.builder(
              controller: _scrollController,
              primary: false,
              padding: const EdgeInsets.symmetric(vertical: 8),
              shrinkWrap: true,
              itemCount: widget.users.length,
              itemBuilder: (context, index) {
                final user = widget.users[index];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => _submitSelection(user),
                  onTap: () => _submitSelection(user),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        ProfileAvatar(profile: user, size: 34),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _submitSelection(PersonProfile user) {
    if (_selectionSubmitted) {
      return;
    }
    _selectionSubmitted = true;
    widget.onSelect(user);
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (mounted) {
        _selectionSubmitted = false;
      }
    });
  }
}

enum _EmojiPanelMode { recent, all, ava }

class _EmojiPanel extends StatefulWidget {
  const _EmojiPanel({
    required this.recentStickerIds,
    required this.onSendSticker,
    required this.previewStickerId,
    required this.onPreviewSticker,
    required this.compact,
  });

  final List<String> recentStickerIds;
  final ValueChanged<String> onSendSticker;
  final String? previewStickerId;
  final ValueChanged<String> onPreviewSticker;
  final bool compact;

  @override
  State<_EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<_EmojiPanel> {
  _EmojiPanelMode _mode = _EmojiPanelMode.ava;

  List<String> get _visibleStickerIds {
    return switch (_mode) {
      _EmojiPanelMode.recent => widget.recentStickerIds,
      _EmojiPanelMode.all => _avaStickerIds,
      _EmojiPanelMode.ava => _avaStickerIds,
    };
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.compact ? 404.0 : 324.0;
    final columns = widget.compact ? 4 : 8;
    final stickers = _visibleStickerIds;
    return Material(
      color: const Color(0xFF202124),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 7),
            Container(
              width: 34,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF6B6F78),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Container(
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2F33),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '\uC774\uBAA8\uD2F0\uCF58',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 42,
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  _EmojiModeButton(
                    selected: _mode == _EmojiPanelMode.recent,
                    icon: Icons.history_rounded,
                    label: '',
                    onTap: () => setState(() {
                      _mode = _EmojiPanelMode.recent;
                    }),
                  ),
                  _EmojiModeButton(
                    selected: _mode == _EmojiPanelMode.all,
                    icon: null,
                    label: 'ALL',
                    onTap: () => setState(() {
                      _mode = _EmojiPanelMode.all;
                    }),
                  ),
                  _EmojiModeButton(
                    selected: _mode == _EmojiPanelMode.ava,
                    icon: Icons.pets_rounded,
                    label: '',
                    onTap: () => setState(() {
                      _mode = _EmojiPanelMode.ava;
                    }),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.storefront_outlined,
                    color: Color(0xFFC8CDD5),
                    size: 22,
                  ),
                  const SizedBox(width: 14),
                ],
              ),
            ),
            Expanded(
              child: stickers.isEmpty
                  ? const Center(
                      child: Text(
                        '\uC544\uC9C1 \uC0AC\uC6A9\uD560 \uC218 \uC788\uB294 \uC774\uBAA8\uD2F0\uCF58\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.\n\uC774\uBAA8\uD2F0\uCF58\uC744 \uCD94\uAC00\uD558\uBA74 \uC5EC\uAE30\uC5D0\uC11C \uBC14\uB85C \uBCF4\uC785\uB2C8\uB2E4.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFC4C8CE),
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    )
                  : CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                            child: Text(
                              _mode == _EmojiPanelMode.recent
                                  ? '\uCD5C\uADFC \uC0AC\uC6A9'
                                  : 'Kakao Frends',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                          sliver: SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final stickerId = stickers[index];
                              final selected =
                                  widget.previewStickerId == stickerId;
                              return InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => widget.onPreviewSticker(stickerId),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? const Color(0xFF30343C)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    border: selected
                                        ? Border.all(
                                            color: const Color(0xFFFFD400),
                                          )
                                        : null,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(3),
                                    child: Image.asset(
                                      _stickerAssetPath(stickerId),
                                      fit: BoxFit.contain,
                                      gaplessPlayback: true,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              CustomPaint(
                                                painter: _AvaStickerPainter(
                                                  stickerId: stickerId,
                                                  progress: 0,
                                                ),
                                              ),
                                    ),
                                  ),
                                ),
                              );
                            }, childCount: stickers.length),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiModeButton extends StatelessWidget {
  const _EmojiModeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData? icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 36,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF4B4F57) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: label.isEmpty
                ? null
                : Border.all(color: const Color(0xFF8D929B)),
          ),
          child: icon == null
              ? Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : Icon(icon, color: Colors.white, size: 19),
        ),
      ),
    );
  }
}

class _StickerPreviewCard extends StatelessWidget {
  const _StickerPreviewCard({
    required this.stickerId,
    required this.compact,
    required this.onClose,
  });

  final String stickerId;
  final bool compact;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final width = compact ? 236.0 : 268.0;
    final height = compact ? 142.0 : 152.0;
    final stickerSize = compact ? 108.0 : 118.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, compact ? 8 : 10, 18, 10),
      child: Align(
        alignment: Alignment.center,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFF2C2D31),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.star_border_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () {},
                ),
              ),
              Center(
                child: SizedBox.square(
                  dimension: stickerSize,
                  child: Image.asset(
                    _stickerAssetPath(stickerId),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) => CustomPaint(
                      painter: _AvaStickerPainter(
                        stickerId: stickerId,
                        progress: 0.18,
                        preview: true,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: onClose,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileComposerCircleButton extends StatelessWidget {
  const _MobileComposerCircleButton({
    super.key,
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
      dimension: 30,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFFF4F4F4),
          foregroundColor: _chatIconColor,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      ),
    );
  }
}

class _MobileComposerInlineButton extends StatelessWidget {
  const _MobileComposerInlineButton({
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
      dimension: 30,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        color: const Color(0xFF777777),
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      ),
    );
  }
}

class _MobileComposerSendButton extends StatelessWidget {
  const _MobileComposerSendButton({
    required this.isSending,
    required this.onPressed,
  });

  final bool isSending;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 32,
      child: IconButton(
        tooltip: '\uC804\uC1A1',
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFFFFDF00),
          foregroundColor: Colors.black,
        ),
        onPressed: isSending ? null : onPressed,
        icon: Icon(
          isSending ? Icons.more_horiz : Icons.arrow_upward_rounded,
          size: 20,
        ),
      ),
    );
  }
}

class _MobileComposerToolsMenu extends StatelessWidget {
  const _MobileComposerToolsMenu({
    required this.onAttachImages,
    required this.onAttachVideos,
    required this.onCaptureCamera,
    required this.onAttachFiles,
    required this.onVoiceMessage,
    required this.onSchedule,
  });

  final VoidCallback onAttachImages;
  final VoidCallback onAttachVideos;
  final VoidCallback onCaptureCamera;
  final VoidCallback onAttachFiles;
  final VoidCallback onVoiceMessage;
  final VoidCallback onSchedule;

  @override
  Widget build(BuildContext context) {
    final items = <_MobileComposerToolItemData>[
      _MobileComposerToolItemData(
        '\uC0AC\uC9C4',
        Icons.image_rounded,
        onAttachImages,
      ),
      _MobileComposerToolItemData(
        '\uB3D9\uC601\uC0C1',
        Icons.movie_rounded,
        onAttachVideos,
      ),
      _MobileComposerToolItemData(
        '\uCE74\uBA54\uB77C',
        Icons.photo_camera_rounded,
        onCaptureCamera,
      ),
      _MobileComposerToolItemData(
        '\uD30C\uC77C',
        Icons.insert_drive_file_rounded,
        onAttachFiles,
      ),
      _MobileComposerToolItemData(
        '\uC74C\uC131\uBA54\uC2DC\uC9C0',
        Icons.graphic_eq_rounded,
        onVoiceMessage,
      ),
      _MobileComposerToolItemData(
        '\uC77C\uC815',
        Icons.event_available_rounded,
        onSchedule,
      ),
    ];
    return Container(
      key: const ValueKey('mobile-composer-tools-menu'),
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFF7F9FC),
        border: Border(top: BorderSide(color: Color(0xFFE1E8F0))),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: GridView.builder(
        shrinkWrap: true,
        primary: false,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          mainAxisExtent: 66,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemBuilder: (context, index) {
          return _MobileComposerToolItem(data: items[index]);
        },
      ),
    );
  }
}

class _MobileComposerToolItemData {
  const _MobileComposerToolItemData(this.label, this.icon, this.onTap);

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _MobileComposerToolItem extends StatelessWidget {
  const _MobileComposerToolItem({required this.data});

  final _MobileComposerToolItemData data;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: data.onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF1FA),
              shape: BoxShape.circle,
            ),
            child: Icon(data.icon, color: Color(0xFF4663CF), size: 21),
          ),
          const SizedBox(height: 7),
          Text(
            data.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF263238),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
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
