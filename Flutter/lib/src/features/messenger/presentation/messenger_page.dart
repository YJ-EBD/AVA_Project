import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_version.dart';
import '../data/mock_messenger_data.dart';
import '../data/chat_api.dart';
import '../data/chat_realtime_client.dart';
import '../domain/messenger_models.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/company_scope.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/data/auth_models.dart';
import '../../azoom/data/azoom_api.dart';
import '../../azoom/presentation/azoom_page.dart';
import '../../ava_stock/presentation/ava_stock_page.dart';
import '../../calendar/domain/calendar_models.dart';
import '../../calendar/presentation/calendar_page.dart';
import '../../ai/presentation/ava_ai_page.dart';
import '../../push/application/mobile_push_controller.dart';
import '../../../config/app_config.dart';
import '../../../platform/window_control.dart';
import '../../../shared/ava_toast.dart';
import '../application/notification_center_controller.dart';
import 'widgets/bottom_banner.dart';
import 'widgets/chat_room_panel.dart';
import 'widgets/chats_panel.dart';
import 'widgets/app_window_title_bar.dart';
import 'widgets/friends_panel.dart';
import 'widgets/messenger_side_nav.dart';
import 'widgets/more_panel.dart';
import 'widgets/notification_center_panel.dart';

const double _sideNavWidth = 64;
const double _compactPrimaryPanelWidth = 396;
const double _mobileMessengerBreakpoint = 720;
const String _presenceOnline = '\uC628\uB77C\uC778';
const String _presenceBackground = '\uBC31\uADF8\uB77C\uC6B4\uB4DC';
const String _presenceOffline = '\uC624\uD504\uB77C\uC778';
const Duration _presenceHeartbeatInterval = Duration(seconds: 20);
const Duration _inboxReconcileInterval = Duration(seconds: 30);
const int _silentChatWarmupRoomLimit = 16;
const int _silentChatWarmupMessageLimit = 160;
const String _appSetupCompletedPrefix = 'ava.app_setup.completed.v3';
const String _appSetupInstallCompletedKey =
    'ava.app_setup.install_completed.v2';
const String _appSetupCompletedVersionKey =
    'ava.app_setup.completed_version.v1';
const String _chatRoomsPrefsPrefix = 'ava.chat.rooms.v2.';

bool _isAzoomRoomCode(String roomCode) {
  return roomCode.startsWith('azoom-') ||
      roomCode.startsWith('azoom:') ||
      roomCode.startsWith('azoom_');
}

bool _isMobileRuntime() {
  return Platform.isAndroid ||
      Platform.isIOS ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

File? _avaLocalCacheFile(String prefix, String scopedKey) {
  try {
    final basePath = _isMobileRuntime()
        ? Directory.systemTemp.path
        : Platform.environment['APPDATA'] ??
              Platform.environment['HOME'] ??
              Directory.current.path;
    final directory = Directory('$basePath${Platform.pathSeparator}AVA')
      ..createSync(recursive: true);
    final fileName = base64Url
        .encode(utf8.encode(scopedKey))
        .replaceAll('=', '');
    return File(
      '${directory.path}${Platform.pathSeparator}${prefix}_$fileName.json',
    );
  } on Object {
    return null;
  }
}

final activeMessengerTabProvider =
    NotifierProvider<ActiveMessengerTab, MessengerTab>(ActiveMessengerTab.new);

final chatRoomsProvider = NotifierProvider<ChatRooms, List<ChatRoom>>(
  ChatRooms.new,
);

final unreadOnlyFilterProvider = NotifierProvider<UnreadOnlyFilter, bool>(
  UnreadOnlyFilter.new,
);

const unreadChatFolderId = 'system-unread';

final activeChatFolderProvider = NotifierProvider<ActiveChatFolder, String?>(
  ActiveChatFolder.new,
);

final chatFoldersProvider = NotifierProvider<ChatFolders, List<ChatFolder>>(
  ChatFolders.new,
);

final chatFilterOrderProvider = NotifierProvider<ChatFilterOrder, List<String>>(
  ChatFilterOrder.new,
);

final quietChatRoomsProvider = NotifierProvider<QuietChatRooms, List<String>>(
  QuietChatRooms.new,
);

enum ChatSortMode { latest, unread, favorite }

final chatSortModeProvider =
    NotifierProvider<ChatSortModeController, ChatSortMode>(
      ChatSortModeController.new,
    );

final nativePopupDimProvider = NotifierProvider<NativePopupDim, bool>(
  NativePopupDim.new,
);

final selectedChatRoomProvider = NotifierProvider<SelectedChatRoom, ChatRoom?>(
  SelectedChatRoom.new,
);

final focusedChatRoomIdProvider = NotifierProvider<FocusedChatRoomId, String?>(
  FocusedChatRoomId.new,
);

final focusedChatMessageIdProvider =
    NotifierProvider<FocusedChatMessageId, String?>(FocusedChatMessageId.new);

void resetMessengerToCompanyPage(WidgetRef ref) {
  ref.read(activeMessengerTabProvider.notifier).setTab(MessengerTab.friends);
  ref.read(selectedChatRoomProvider.notifier).close();
  ref.read(focusedChatRoomIdProvider.notifier).clear();
  ref.read(focusedChatMessageIdProvider.notifier).clear();
}

String _windowTitleForTab(MessengerTab tab) {
  return switch (tab) {
    MessengerTab.azoom => 'AZOOM',
    MessengerTab.avaStock => 'AVA_stock',
    MessengerTab.avaAi => 'AVA AI',
    MessengerTab.calendar => 'AVA Calendar',
    MessengerTab.friends ||
    MessengerTab.chats ||
    MessengerTab.notifications ||
    MessengerTab.more => 'Abba-Talk',
  };
}

bool _isAdminMoreSession(AuthSession? session) {
  final role = session?.user.role.toUpperCase();
  return role == 'ADMIN' || role == 'SUPERUSER';
}

String chatMessageListPreview(ChatMessageDto? message) {
  if (message == null) {
    return '';
  }
  final attachment = message.attachment;
  if (attachment != null) {
    return chatAttachmentPreview(attachment.fileName, attachment.contentType);
  }
  return normalizeChatRoomPreview(message.content);
}

String chatAttachmentPreview(String fileName, String contentType) {
  final safeName = fileName.trim().isEmpty ? 'attachment' : fileName.trim();
  final lowerType = contentType.toLowerCase();
  final lowerName = safeName.toLowerCase();
  if (lowerType.startsWith('image/') ||
      lowerName.endsWith('.jpg') ||
      lowerName.endsWith('.jpeg') ||
      lowerName.endsWith('.png') ||
      lowerName.endsWith('.gif') ||
      lowerName.endsWith('.bmp') ||
      lowerName.endsWith('.webp') ||
      lowerName.endsWith('.heic') ||
      lowerName.endsWith('.heif') ||
      lowerName.endsWith('.tif') ||
      lowerName.endsWith('.tiff')) {
    return '[\uC774\uBBF8\uC9C0]';
  }
  if (lowerType.startsWith('video/') ||
      lowerName.endsWith('.mp4') ||
      lowerName.endsWith('.m4v') ||
      lowerName.endsWith('.mov') ||
      lowerName.endsWith('.avi') ||
      lowerName.endsWith('.mkv') ||
      lowerName.endsWith('.webm') ||
      lowerName.endsWith('.wmv') ||
      lowerName.endsWith('.mpg') ||
      lowerName.endsWith('.mpeg') ||
      lowerName.endsWith('.3gp') ||
      lowerName.endsWith('.3gpp')) {
    return '[\uB3D9\uC601\uC0C1]';
  }
  return '[\uD30C\uC77C] $safeName';
}

String normalizeChatRoomPreview(String preview) {
  final trimmed = preview.trim();
  if (trimmed.isEmpty) {
    return preview;
  }
  if (_isImageRoomPreview(trimmed)) {
    return '[\uC774\uBBF8\uC9C0]';
  }
  if (_isVideoRoomPreview(trimmed)) {
    return '[\uB3D9\uC601\uC0C1]';
  }
  return preview;
}

bool _isImageRoomPreview(String preview) {
  final lower = preview.toLowerCase();
  if (preview.startsWith('[\uC774\uBBF8\uC9C0]') ||
      preview.contains('[\uC774\uBBF8\uC9C0]')) {
    return true;
  }
  return _isBareMediaPreview(lower, const [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.webp',
    '.heic',
    '.heif',
    '.tif',
    '.tiff',
  ]);
}

bool _isVideoRoomPreview(String preview) {
  final lower = preview.toLowerCase();
  if (preview.startsWith('[\uB3D9\uC601\uC0C1]') ||
      preview.contains('[\uB3D9\uC601\uC0C1]')) {
    return true;
  }
  return _isBareMediaPreview(lower, const [
    '.mp4',
    '.m4v',
    '.mov',
    '.avi',
    '.mkv',
    '.webm',
    '.wmv',
    '.mpg',
    '.mpeg',
    '.3gp',
    '.3gpp',
  ]);
}

bool _isBareMediaPreview(String lowerPreview, List<String> extensions) {
  final compact = lowerPreview.trim();
  if (compact.contains(' ')) {
    return false;
  }
  return extensions.any(compact.endsWith);
}

final currentUserProfileProvider = Provider<PersonProfile>((ref) {
  final user = ref.watch(authControllerProvider).value?.session?.user;
  if (user == null) {
    return selfProfile;
  }
  final fallback = personProfileFromAuthUser(user);
  final serverProfiles = ref.watch(userProfilesProvider).value ?? const [];
  for (final profile in serverProfiles) {
    if ((profile.id != null && profile.id == user.id) ||
        (profile.email != null && profile.email == user.email)) {
      return profile;
    }
  }
  return fallback;
});

final userProfilesProvider =
    AsyncNotifierProvider<UserProfiles, List<PersonProfile>>(UserProfiles.new);

final friendGroupsProvider = Provider<List<UserGroup>>((ref) {
  final users = ref.watch(userProfilesProvider).value ?? const [];
  if (users.isEmpty) {
    return const [];
  }
  final currentProfile = ref.watch(currentUserProfileProvider);
  final ownDepartment = _departmentTitle(currentProfile.department);

  final grouped = <String, List<PersonProfile>>{};
  for (final user in users) {
    final department = _departmentTitle(user.department);
    grouped.putIfAbsent(department, () => []).add(user);
  }

  final titles = grouped.keys.toList()
    ..sort((a, b) {
      const unspecified = '\uBBF8\uC9C0\uC815';
      final aOwnDepartment = a == ownDepartment;
      final bOwnDepartment = b == ownDepartment;
      if (aOwnDepartment != bOwnDepartment) {
        return aOwnDepartment ? -1 : 1;
      }
      if (ownDepartment != unspecified) {
        final aUnspecified = a == unspecified;
        final bUnspecified = b == unspecified;
        if (aUnspecified != bUnspecified) {
          return aUnspecified ? 1 : -1;
        }
      }
      return a.compareTo(b);
    });
  return [
    for (final title in titles)
      UserGroup(
        title: title,
        users: grouped[title]!
          ..sort(
            (a, b) => _compareProfilesForCurrentUser(
              a,
              b,
              currentProfile,
              title == ownDepartment,
            ),
          ),
      ),
  ];
});

String _departmentTitle(String? department) {
  final trimmed = department?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return '\uBBF8\uC9C0\uC815';
  }
  return trimmed;
}

final updatedUserProfilesProvider = Provider<List<PersonProfile>>((ref) {
  final users = ref.watch(userProfilesProvider).value ?? const [];
  if (users.isEmpty) {
    return const [];
  }
  return users.take(5).toList();
});

class UserProfiles extends AsyncNotifier<List<PersonProfile>> {
  @override
  Future<List<PersonProfile>> build() async {
    final session = ref.watch(authControllerProvider).value?.session;
    ref.watch(activeCompanyProvider);
    if (session == null || session.accessToken.isEmpty) {
      return const [];
    }

    final profiles = await ref.read(chatApiProvider).users(session.accessToken);
    return [for (final profile in profiles) personProfileFromDto(profile)];
  }
}

class ActiveMessengerTab extends Notifier<MessengerTab> {
  @override
  MessengerTab build() => MessengerTab.friends;

  void setTab(MessengerTab tab) {
    state = tab;
  }
}

class ChatRooms extends Notifier<List<ChatRoom>> {
  String? _loadedUserKey;
  bool _hasLoadedRemoteRooms = false;
  bool _isLoadingRemoteRooms = false;
  Future<void>? _remoteRoomsLoadFuture;
  Timer? _localRoomsSaveTimer;
  List<ChatRoom> _cachedRooms = const [];

  bool get hasLoadedRemoteRooms => _hasLoadedRemoteRooms;

  bool get isLoadingRemoteRooms => _isLoadingRemoteRooms;

  @override
  List<ChatRoom> build() {
    ref.onDispose(() => _localRoomsSaveTimer?.cancel());
    final session = ref.watch(authControllerProvider).value?.session;
    final activeCompany = ref.watch(activeCompanyProvider);
    final userKey = _userKey(session);
    if (session == null || session.accessToken.isEmpty || userKey == null) {
      _loadedUserKey = null;
      _hasLoadedRemoteRooms = false;
      _isLoadingRemoteRooms = false;
      _remoteRoomsLoadFuture = null;
      _localRoomsSaveTimer?.cancel();
      _cachedRooms = const [];
      return const [];
    }
    final scopedUserKey = '$userKey:${activeCompany ?? ''}';
    if (_loadedUserKey != scopedUserKey) {
      _loadedUserKey = scopedUserKey;
      _hasLoadedRemoteRooms = false;
      _isLoadingRemoteRooms = false;
      _remoteRoomsLoadFuture = null;
      _cachedRooms = _readLocalRooms(scopedUserKey);
      Future<void>.microtask(() => _loadLocalRoomsThenRefresh(scopedUserKey));
      return _cachedRooms;
    }
    return state;
  }

  Future<void> _loadLocalRoomsThenRefresh(String scopedUserKey) async {
    await _loadMobilePreferenceRooms(scopedUserKey);
    if (_loadedUserKey == scopedUserKey) {
      await refreshFromServer(force: true);
    }
  }

  Future<void> _loadMobilePreferenceRooms(String scopedUserKey) async {
    if (!_isMobileRuntime() ||
        _cachedRooms.isNotEmpty ||
        state.isNotEmpty ||
        _hasLoadedRemoteRooms) {
      return;
    }
    final rooms = await _readLocalRoomsFromPreferences(scopedUserKey);
    if (_loadedUserKey != scopedUserKey ||
        rooms.isEmpty ||
        _hasLoadedRemoteRooms ||
        state.isNotEmpty) {
      return;
    }
    _cachedRooms = rooms;
    state = rooms;
  }

  Future<void> refreshFromServer({bool force = false}) async {
    if (_isLoadingRemoteRooms) {
      return _remoteRoomsLoadFuture ?? Future<void>.value();
    }
    if (_hasLoadedRemoteRooms && !force) {
      return;
    }
    final future = _refreshFromServer();
    _remoteRoomsLoadFuture = future;
    await future;
  }

  Future<void> _refreshFromServer() async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      return;
    }
    final userKey = _userKey(session);
    if (userKey == null) {
      return;
    }
    final activeCompany = ref.read(activeCompanyProvider);
    final scopedUserKey = '$userKey:${activeCompany ?? ''}';

    _isLoadingRemoteRooms = true;
    try {
      final remoteRooms = await ref
          .read(chatApiProvider)
          .rooms(session.accessToken);
      if (_loadedUserKey != scopedUserKey) {
        return;
      }
      final openRoomId = ref.read(selectedChatRoomProvider)?.id;
      final visibleRooms = remoteRooms.where(_shouldDisplayRemoteRoom);
      _commitRooms(
        _orderRooms(
          _dedupeRooms([
            for (final room in visibleRooms)
              _fromRemoteRoom(room, forceRead: room.code == openRoomId),
          ]),
        ),
      );
      _hasLoadedRemoteRooms = true;
    } on Object {
      // Keep the mock room list available when the API is unreachable.
    } finally {
      _isLoadingRemoteRooms = false;
      _remoteRoomsLoadFuture = null;
    }
  }

  String? _userKey(AuthSession? session) {
    final user = session?.user;
    if (user == null) {
      return null;
    }
    if (user.id.isNotEmpty) {
      return user.id;
    }
    if (user.email.isNotEmpty) {
      return user.email;
    }
    return null;
  }

  ChatRoom? markRead(String roomId) {
    ChatRoom? updatedRoom;
    var changed = false;
    final nextRooms = <ChatRoom>[];
    for (final room in state) {
      if (room.id != roomId) {
        nextRooms.add(room);
        continue;
      }
      if (room.unreadCount <= 0 && !room.hasUnreadMention) {
        updatedRoom = room;
        nextRooms.add(room);
        continue;
      }
      final readRoom = room.copyWith(unreadCount: 0, hasUnreadMention: false);
      updatedRoom = readRoom;
      nextRooms.add(readRoom);
      changed = true;
    }
    if (changed) {
      state = nextRooms;
      _persistLoadedRooms();
      _syncFloating(updatedRoom!);
    }
    return updatedRoom;
  }

  void togglePinned(String roomId) {
    ChatRoom? targetRoom;
    for (final room in state) {
      if (room.id == roomId) {
        targetRoom = room;
        break;
      }
    }
    final target = targetRoom;
    if (target == null) {
      return;
    }

    final nextPinned = !target.isPinned;
    final pinnedAt = nextPinned ? DateTime.now() : null;
    _commitRooms(
      _orderRooms([
        for (final room in state)
          if (room.id == roomId)
            room.copyWith(
              isPinned: nextPinned,
              pinnedAt: pinnedAt,
              clearPinnedAt: !nextPinned,
            )
          else
            room,
      ]),
    );
    _persistPinned(roomId, nextPinned);
  }

  ChatRoom? toggleMuted(String roomId) {
    ChatRoom? updatedRoom;
    state = [
      for (final room in state)
        if (room.id == roomId)
          updatedRoom = room.copyWith(isMuted: !room.isMuted)
        else
          room,
    ];
    if (updatedRoom != null) {
      _persistLoadedRooms();
      _syncFloating(updatedRoom);
    }
    return updatedRoom;
  }

  Future<void> _persistPinned(String roomId, bool pinned) async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      return;
    }

    try {
      final remoteRoom = await ref
          .read(chatApiProvider)
          .setPinned(
            accessToken: session.accessToken,
            roomCode: roomId,
            pinned: pinned,
          );
      _commitRooms(
        _orderRooms([
          for (final room in state)
            if (room.id == roomId)
              room.copyWith(
                isPinned: remoteRoom.pinned,
                pinnedAt: remoteRoom.pinnedAt,
                clearPinnedAt: !remoteRoom.pinned,
              )
            else
              room,
        ]),
      );
    } on Object {
      // Keep the optimistic local state if the API is temporarily unavailable.
    }
  }

  void noticeSet(String roomId, ChatNotice notice) {
    state = [
      for (final room in state)
        if (room.id == roomId) room.copyWith(notice: notice) else room,
    ];
    _persistLoadedRooms();
  }

  void messagePosted(
    String roomId,
    String content,
    DateTime? sentAt, {
    ChatRoom? fallbackRoom,
    bool spoiler = false,
  }) {
    final activityAt = sentAt ?? DateTime.now();
    final preview = normalizeChatRoomPreview(content);
    var wasUpdated = false;
    final updatedRooms = [
      for (final room in state)
        if (room.id == roomId)
          room.copyWith(
            preview: preview,
            previewIsSpoiler: spoiler,
            time: formatChatClockTime(activityAt),
            lastActivityAt: activityAt,
            isDraft: false,
          )
        else
          room,
    ];

    wasUpdated = state.any((room) => room.id == roomId);
    if (!wasUpdated && fallbackRoom != null) {
      for (var index = 0; index < updatedRooms.length; index++) {
        final room = updatedRooms[index];
        if (_sameRoomOrDirectPeer(room, fallbackRoom)) {
          updatedRooms[index] = room.copyWith(
            preview: preview,
            previewIsSpoiler: spoiler,
            time: formatChatClockTime(activityAt),
            lastActivityAt: activityAt,
            isDraft: false,
          );
          wasUpdated = true;
          break;
        }
      }
    }
    if (!wasUpdated && fallbackRoom != null) {
      updatedRooms.add(
        fallbackRoom.copyWith(
          preview: preview,
          previewIsSpoiler: spoiler,
          time: formatChatClockTime(activityAt),
          lastActivityAt: activityAt,
          isDraft: false,
        ),
      );
    }

    _commitRooms(_orderRooms(_dedupeRooms(updatedRooms)));
    for (final room in state) {
      if (room.id == roomId) {
        _syncFloating(room);
        break;
      }
    }
  }

  void upsert(ChatRoom room) {
    _commitRooms(
      _orderRooms(
        _dedupeRooms([
          for (final item in state)
            if (!_sameRoomOrDirectPeer(item, room)) item,
          room,
        ]),
      ),
    );
    _syncFloating(room);
  }

  void remove(String roomId) {
    state = [
      for (final room in state)
        if (room.id != roomId) room,
    ];
    _persistLoadedRooms();
    unawaited(WindowControl.closeChatFloating(roomId));
  }

  void realtimeRoomUpdated(
    ChatRoom room, {
    required bool incrementUnread,
    required bool isOpen,
  }) {
    ChatRoom? existingRoom;
    for (final item in state) {
      if (item.id == room.id) {
        existingRoom = item;
        break;
      }
    }

    final localUnreadCount =
        (existingRoom?.unreadCount ?? 0) + (incrementUnread ? 1 : 0);
    final unreadCount = isOpen
        ? 0
        : math.max(localUnreadCount, room.unreadCount);
    final merged = room.copyWith(
      unreadCount: unreadCount,
      hasUnreadMention: isOpen
          ? false
          : (room.hasUnreadMention || existingRoom?.hasUnreadMention == true),
      isPinned: existingRoom?.isPinned ?? room.isPinned,
      pinnedAt: existingRoom?.pinnedAt ?? room.pinnedAt,
      isMuted: existingRoom?.isMuted ?? room.isMuted,
      notice: room.notice ?? existingRoom?.notice,
    );

    _commitRooms(
      _orderRooms(
        _dedupeRooms([
          for (final item in state)
            if (!_sameRoomOrDirectPeer(item, merged)) item,
          merged,
        ]),
      ),
    );
    _syncFloating(merged);
  }

  ChatRoom roomFromRemoteRoom(
    ChatRoomDto room, {
    List<PersonProfile>? members,
  }) {
    return _fromRemoteRoom(room, members: members);
  }

  bool _shouldDisplayRemoteRoom(ChatRoomDto room) {
    if (_isAzoomRoomCode(room.code)) {
      return false;
    }
    if ((room.type == 'DIRECT' || room.type == 'SELF') &&
        !_remoteRoomIncludesCurrentUser(room)) {
      return false;
    }
    if (room.type == 'SELF' && room.lastMessage.trim().isEmpty) {
      return false;
    }
    return true;
  }

  bool _remoteRoomIncludesCurrentUser(ChatRoomDto room) {
    final user = ref.read(authControllerProvider).value?.session?.user;
    if (user == null) {
      return true;
    }
    final currentUserId = user.id.trim();
    final currentEmail = user.email.trim().toLowerCase();
    if (currentUserId.isEmpty && currentEmail.isEmpty) {
      return true;
    }
    for (final member in room.members) {
      final memberId = member.id.trim();
      final memberEmail = member.email.trim().toLowerCase();
      if (currentUserId.isNotEmpty && memberId == currentUserId) {
        return true;
      }
      if (currentEmail.isNotEmpty && memberEmail == currentEmail) {
        return true;
      }
    }
    return false;
  }

  ChatRoom _fromRemoteRoom(
    ChatRoomDto room, {
    List<PersonProfile>? members,
    bool forceRead = false,
  }) {
    ChatRoom? fallback;
    for (final item in [...state, ...chatRooms]) {
      if (item.id == room.code) {
        fallback = item;
        break;
      }
    }
    final currentUserId = ref
        .read(authControllerProvider)
        .value
        ?.session
        ?.user
        .id;
    final remoteMembers = [
      for (final member in room.members) personProfileFromDto(member),
    ];
    final visibleRemoteMembers = room.type == 'DIRECT' && currentUserId != null
        ? remoteMembers
              .where(
                (member) => member.id == null || member.id != currentUserId,
              )
              .toList()
        : remoteMembers;
    final currentProfile = currentUserId == null
        ? null
        : ref.read(currentUserProfileProvider);
    final resolvedMembers =
        members ??
        (room.type == 'SELF' && currentProfile != null
            ? [currentProfile]
            : visibleRemoteMembers.isNotEmpty
            ? visibleRemoteMembers
            : fallback?.members ?? _fallbackMembersFor(room));
    final resolvedTitle = room.type == 'SELF'
        ? '\uB098\uC640\uC758 \uCC44\uD305'
        : room.type == 'DIRECT' && resolvedMembers.isNotEmpty
        ? resolvedMembers.first.name
        : room.title;

    return ChatRoom(
      id: room.code,
      title: resolvedTitle,
      preview: normalizeChatRoomPreview(room.lastMessage),
      previewIsSpoiler: room.lastMessageSpoiler,
      time: formatChatClockTime(room.lastMessageAt),
      members: resolvedMembers,
      avatarImageUrl: room.avatarImageUrl.isEmpty
          ? fallback?.avatarImageUrl
          : room.avatarImageUrl,
      lastActivityAt: room.lastMessageAt,
      participantCount: room.participantCount,
      isPinned: room.pinned,
      pinnedAt: room.pinnedAt ?? fallback?.pinnedAt,
      unreadCount: forceRead ? 0 : room.unreadCount,
      hasUnreadMention: forceRead ? false : room.mentioned,
      isMuted: fallback?.isMuted ?? false,
      notice: _noticeFromRemote(room.notice),
    );
  }

  ChatNotice? _noticeFromRemote(ChatNoticeDto? notice) {
    if (notice == null || notice.content.isEmpty) {
      return null;
    }
    return ChatNotice(
      messageId: notice.messageId,
      senderId: notice.senderId,
      senderName: notice.senderName,
      content: notice.content,
      sentAt: notice.sentAt,
    );
  }

  List<PersonProfile> _fallbackMembersFor(ChatRoomDto room) {
    final color = room.type == 'DIRECT'
        ? const Color(0xFF8FC7D5)
        : const Color(0xFFA6C6EE);
    return [PersonProfile(name: room.title, color: color)];
  }

  void _syncFloating(ChatRoom room) {
    if (room.isDraft) {
      return;
    }
    final avatarColor = room.members.isEmpty
        ? const Color(0xFFA6C6EE)
        : room.members.first.color;
    unawaited(
      WindowControl.updateChatFloating(
        roomId: room.id,
        title: room.title,
        avatarColor: colorToHex(avatarColor),
        isGroup: !room.isDirectChat && !room.isSelfChat,
        isMuted: room.isMuted,
        unreadCount: room.unreadCount,
      ),
    );
  }

  List<ChatRoom> _dedupeRooms(List<ChatRoom> rooms) {
    final result = <ChatRoom>[];
    for (final room in rooms) {
      final index = result.indexWhere(
        (existing) => _sameRoomOrDirectPeer(existing, room),
      );
      if (index < 0) {
        result.add(room);
        continue;
      }
      result[index] = _preferredRoom(result[index], room);
    }
    return result;
  }

  ChatRoom _preferredRoom(ChatRoom existing, ChatRoom incoming) {
    if (existing.isDraft != incoming.isDraft) {
      return incoming.isDraft ? existing : incoming;
    }
    final existingActivity = existing.lastActivityAt;
    final incomingActivity = incoming.lastActivityAt;
    if (existingActivity != null && incomingActivity != null) {
      return incomingActivity.isAfter(existingActivity) ? incoming : existing;
    }
    if (incomingActivity != null && existingActivity == null) {
      return incoming;
    }
    return incoming;
  }

  bool _sameRoomOrDirectPeer(ChatRoom first, ChatRoom second) {
    if (first.id == second.id) {
      return true;
    }
    if (!_canDedupeAsDirect(first) || !_canDedupeAsDirect(second)) {
      return false;
    }
    final firstPeer = _directPeer(first);
    final secondPeer = _directPeer(second);
    if (firstPeer == null || secondPeer == null) {
      return false;
    }
    return _sameProfile(firstPeer, secondPeer) ||
        firstPeer.identityKey.toLowerCase() ==
            secondPeer.identityKey.toLowerCase();
  }

  bool _canDedupeAsDirect(ChatRoom room) {
    return room.isDraft ||
        room.id.startsWith('direct-') ||
        (room.members.length == 1 && room.isDirectChat);
  }

  PersonProfile? _directPeer(ChatRoom room) {
    if (room.members.isEmpty) {
      return null;
    }
    return room.members.first;
  }

  List<ChatRoom> _orderRooms(List<ChatRoom> rooms) {
    final indexed = rooms.indexed.toList();
    indexed.sort((a, b) {
      if (a.$2.isPinned != b.$2.isPinned) {
        return a.$2.isPinned ? -1 : 1;
      }
      if (a.$2.isPinned && b.$2.isPinned) {
        final aPinnedAt = a.$2.pinnedAt;
        final bPinnedAt = b.$2.pinnedAt;
        if (aPinnedAt != null && bPinnedAt != null) {
          final pinnedOrder = bPinnedAt.compareTo(aPinnedAt);
          if (pinnedOrder != 0) {
            return pinnedOrder;
          }
        } else if (aPinnedAt != null) {
          return -1;
        } else if (bPinnedAt != null) {
          return 1;
        }
      }
      if (!a.$2.isPinned && !b.$2.isPinned) {
        final aActivity = a.$2.lastActivityAt;
        final bActivity = b.$2.lastActivityAt;
        if (aActivity != null && bActivity != null) {
          final activityOrder = bActivity.compareTo(aActivity);
          if (activityOrder != 0) {
            return activityOrder;
          }
        } else if (aActivity != null) {
          return -1;
        } else if (bActivity != null) {
          return 1;
        }
      }
      return a.$1.compareTo(b.$1);
    });
    return [for (final item in indexed) item.$2];
  }

  void _commitRooms(List<ChatRoom> rooms) {
    _cachedRooms = rooms;
    state = rooms;
    _persistLoadedRooms();
  }

  void _persistLoadedRooms() {
    final scopedUserKey = _loadedUserKey;
    if (scopedUserKey == null) {
      return;
    }
    _cachedRooms = state;
    _localRoomsSaveTimer?.cancel();
    _localRoomsSaveTimer = Timer(const Duration(milliseconds: 650), () {
      _writeLocalRooms(scopedUserKey, _cachedRooms);
    });
  }

  List<ChatRoom> _readLocalRooms(String scopedUserKey) {
    final file = _localRoomsFile(scopedUserKey);
    if (file == null || !file.existsSync()) {
      return const [];
    }
    try {
      return _decodeLocalRooms(file.readAsStringSync());
    } on Object {
      return const [];
    }
  }

  Future<List<ChatRoom>> _readLocalRoomsFromPreferences(
    String scopedUserKey,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _decodeLocalRooms(
        prefs.getString(_localRoomsPreferencesKey(scopedUserKey)),
      );
    } on Object {
      return const [];
    }
  }

  List<ChatRoom> _decodeLocalRooms(String? payload) {
    if (payload == null || payload.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! List) {
        return const [];
      }
      return _orderRooms(
        [
          for (final item in decoded)
            if (item is Map) _roomFromCacheJson(item.cast<String, dynamic>()),
        ].whereType<ChatRoom>().toList(),
      );
    } on Object {
      return const [];
    }
  }

  void _writeLocalRooms(String scopedUserKey, List<ChatRoom> rooms) {
    try {
      final payload = jsonEncode([
        for (final room in rooms.take(120)) _roomToCacheJson(room),
      ]);
      final file = _localRoomsFile(scopedUserKey);
      if (file != null) {
        unawaited(_writeLocalRoomsFile(file, payload));
      }
      if (_isMobileRuntime()) {
        unawaited(_writeLocalRoomsPreferences(scopedUserKey, payload));
      }
    } on Object {
      // Local room summaries are an acceleration path only.
    }
  }

  Future<void> _writeLocalRoomsFile(File file, String payload) async {
    try {
      await file.writeAsString(payload);
    } on Object {
      // Local room summaries are an acceleration path only.
    }
  }

  Future<void> _writeLocalRoomsPreferences(
    String scopedUserKey,
    String payload,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localRoomsPreferencesKey(scopedUserKey), payload);
    } on Object {
      // Local room summaries are an acceleration path only.
    }
  }

  String _localRoomsPreferencesKey(String scopedUserKey) {
    final suffix = base64Url
        .encode(utf8.encode(scopedUserKey))
        .replaceAll('=', '');
    return '$_chatRoomsPrefsPrefix$suffix';
  }

  File? _localRoomsFile(String scopedUserKey) {
    return _avaLocalCacheFile('chat_rooms', scopedUserKey);
  }

  Map<String, Object?> _roomToCacheJson(ChatRoom room) {
    return {
      'id': room.id,
      'title': room.title,
      'preview': room.preview,
      'time': room.time,
      'members': [
        for (final member in room.members) _profileToCacheJson(member),
      ],
      'avatarImageUrl': room.avatarImageUrl,
      'previewIsSpoiler': room.previewIsSpoiler,
      'lastActivityAt': room.lastActivityAt?.toIso8601String(),
      'participantCount': room.participantCount,
      'unreadCount': room.unreadCount,
      'hasUnreadMention': room.hasUnreadMention,
      'isPinned': room.isPinned,
      'pinnedAt': room.pinnedAt?.toIso8601String(),
      'isDraft': room.isDraft,
      'isMuted': room.isMuted,
      'notice': room.notice == null ? null : _noticeToCacheJson(room.notice!),
    };
  }

  ChatRoom? _roomFromCacheJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final title = json['title'] as String? ?? '';
    if (id.isEmpty || title.isEmpty) {
      return null;
    }
    return ChatRoom(
      id: id,
      title: title,
      preview: json['preview'] as String? ?? '',
      time: json['time'] as String? ?? '',
      members: [
        for (final item in json['members'] as List<dynamic>? ?? const [])
          if (item is Map) _profileFromCacheJson(item.cast<String, dynamic>()),
      ].whereType<PersonProfile>().toList(),
      avatarImageUrl: json['avatarImageUrl'] as String?,
      previewIsSpoiler: json['previewIsSpoiler'] as bool? ?? false,
      lastActivityAt: DateTime.tryParse(
        json['lastActivityAt'] as String? ?? '',
      ),
      participantCount: (json['participantCount'] as num?)?.toInt(),
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      hasUnreadMention: json['hasUnreadMention'] as bool? ?? false,
      isPinned: json['isPinned'] as bool? ?? false,
      pinnedAt: DateTime.tryParse(json['pinnedAt'] as String? ?? ''),
      isDraft: json['isDraft'] as bool? ?? false,
      isMuted: json['isMuted'] as bool? ?? false,
      notice: json['notice'] is Map
          ? _noticeFromCacheJson(
              (json['notice'] as Map).cast<String, dynamic>(),
            )
          : null,
    );
  }

  Map<String, Object?> _profileToCacheJson(PersonProfile profile) {
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
      'imageUrl': profile.imageUrl,
      'status': profile.status,
      'statusMessage': profile.statusMessage,
      'profileBackgroundColor': profile.profileBackgroundColor == null
          ? null
          : colorToHex(profile.profileBackgroundColor!),
      'profileBackgroundImageUrl': profile.profileBackgroundImageUrl,
      'blocked': profile.blocked,
    };
  }

  PersonProfile? _profileFromCacheJson(Map<String, dynamic> json) {
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

  Map<String, Object?> _noticeToCacheJson(ChatNotice notice) {
    return {
      'messageId': notice.messageId,
      'senderId': notice.senderId,
      'senderName': notice.senderName,
      'content': notice.content,
      'sentAt': notice.sentAt?.toIso8601String(),
    };
  }

  ChatNotice? _noticeFromCacheJson(Map<String, dynamic> json) {
    final senderName = json['senderName'] as String? ?? '';
    final content = json['content'] as String? ?? '';
    if (senderName.isEmpty || content.isEmpty) {
      return null;
    }
    return ChatNotice(
      messageId: json['messageId'] as String?,
      senderId: json['senderId'] as String?,
      senderName: senderName,
      content: content,
      sentAt: DateTime.tryParse(json['sentAt'] as String? ?? ''),
    );
  }
}

int _compareProfiles(PersonProfile a, PersonProfile b) {
  final nameOrder = a.name.compareTo(b.name);
  if (nameOrder != 0) {
    return nameOrder;
  }
  return (a.email ?? '').compareTo(b.email ?? '');
}

int _compareProfilesForCurrentUser(
  PersonProfile a,
  PersonProfile b,
  PersonProfile currentProfile,
  bool ownDepartment,
) {
  if (ownDepartment) {
    final aCurrent = _sameProfile(a, currentProfile);
    final bCurrent = _sameProfile(b, currentProfile);
    if (aCurrent != bCurrent) {
      return aCurrent ? -1 : 1;
    }
  }
  return _compareProfiles(a, b);
}

bool _sameProfile(PersonProfile a, PersonProfile b) {
  final aId = a.id?.trim();
  final bId = b.id?.trim();
  if (aId != null && aId.isNotEmpty && bId != null && bId.isNotEmpty) {
    return aId == bId;
  }
  final aEmail = a.email?.trim().toLowerCase();
  final bEmail = b.email?.trim().toLowerCase();
  return aEmail != null &&
      aEmail.isNotEmpty &&
      bEmail != null &&
      bEmail.isNotEmpty &&
      aEmail == bEmail;
}

PersonProfile personProfileFromAuthUser(AuthUser user) {
  return PersonProfile(
    id: user.id.isEmpty ? null : user.id,
    name: user.name?.isNotEmpty == true ? user.name! : user.displayName,
    nickname: user.nickname,
    phoneNumber: user.phoneNumber,
    email: user.email,
    companyName: user.companyName,
    position: user.position,
    role: user.role,
    department: user.department,
    birthDate: user.birthDate,
    color: avatarColorFromHex(user.avatarColor),
    imageUrl: user.avatarImageUrl,
    status: user.status ?? '\uC628\uB77C\uC778',
    statusMessage: user.statusMessage,
    profileBackgroundColor: avatarColorFromHex(user.profileBackgroundColor),
    profileBackgroundImageUrl: user.profileBackgroundImageUrl,
  );
}

PersonProfile personProfileFromDto(UserProfileDto profile) {
  return PersonProfile(
    id: profile.id.isEmpty ? null : profile.id,
    name: profile.name.isNotEmpty ? profile.name : profile.displayName,
    nickname: profile.nickname.isEmpty ? null : profile.nickname,
    phoneNumber: profile.phoneNumber.isEmpty ? null : profile.phoneNumber,
    email: profile.email.isEmpty ? null : profile.email,
    companyName: profile.companyName.isEmpty ? null : profile.companyName,
    position: profile.position.isEmpty ? null : profile.position,
    role: profile.role.isEmpty ? null : profile.role,
    department: profile.department.isEmpty ? null : profile.department,
    birthDate: profile.birthDate,
    color: avatarColorFromHex(profile.avatarColor),
    imageUrl: profile.avatarImageUrl.isEmpty ? null : profile.avatarImageUrl,
    status: profile.status.isEmpty ? '\uC628\uB77C\uC778' : profile.status,
    statusMessage: profile.statusMessage.isEmpty ? null : profile.statusMessage,
    profileBackgroundColor: avatarColorFromHex(profile.profileBackgroundColor),
    profileBackgroundImageUrl: profile.profileBackgroundImageUrl.isEmpty
        ? null
        : profile.profileBackgroundImageUrl,
    blocked: profile.blocked,
  );
}

Color avatarColorFromHex(String? hex) {
  final normalized = (hex ?? '').replaceFirst('#', '');
  final value = int.tryParse(normalized, radix: 16);
  if (value == null) {
    return const Color(0xFF7AA06A);
  }
  return Color(0xFF000000 | value);
}

String colorToHex(Color color) {
  final value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

class UnreadOnlyFilter extends Notifier<bool> {
  @override
  bool build() => false;

  void showAll() {
    state = false;
  }

  void showUnreadOnly() {
    state = true;
  }
}

class ActiveChatFolder extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? folderId) {
    state = folderId;
    ref.read(unreadOnlyFilterProvider.notifier).showAll();
  }
}

class ChatSortModeController extends Notifier<ChatSortMode> {
  @override
  ChatSortMode build() => ChatSortMode.latest;

  void setMode(ChatSortMode mode) {
    state = mode;
  }
}

class NativePopupDim extends Notifier<bool> {
  @override
  bool build() => false;

  void show() {
    state = true;
  }

  void hide() {
    state = false;
  }
}

class ChatFolders extends Notifier<List<ChatFolder>> {
  Timer? _saveTimer;
  String? _loadedUserKey;
  bool _isLoading = false;
  bool _dirtyWhileLoading = false;
  List<ChatFolder> _cachedFolders = const [];

  @override
  List<ChatFolder> build() {
    ref.onDispose(() => _saveTimer?.cancel());
    final session = ref.watch(authControllerProvider).value?.session;
    final userKey = _userKey(session);
    if (session == null || session.accessToken.isEmpty || userKey == null) {
      _saveTimer?.cancel();
      _loadedUserKey = null;
      _isLoading = false;
      _dirtyWhileLoading = false;
      _cachedFolders = const [];
      return const [];
    }

    if (_loadedUserKey != userKey && !_isLoading) {
      _loadedUserKey = userKey;
      _isLoading = true;
      _dirtyWhileLoading = false;
      _cachedFolders = _readLocalFolders(userKey);
      Future<void>.microtask(
        () => _loadFromServer(session.accessToken, userKey),
      );
      return _cachedFolders;
    }

    return _cachedFolders;
  }

  void create({
    required String name,
    required String icon,
    required List<String> roomIds,
    bool isFavorite = false,
  }) {
    final normalized = _normalizeRoomIds(roomIds);
    _commit([
      ...state,
      ChatFolder(
        id: isFavorite
            ? 'favorite'
            : 'folder-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        icon: icon,
        roomIds: normalized,
        isFavorite: isFavorite,
      ),
    ]);
  }

  void update(ChatFolder folder) {
    _commit([
      for (final item in state)
        if (item.id == folder.id) folder else item,
    ]);
  }

  void reorder(List<String> orderedIds) {
    final byId = {for (final folder in state) folder.id: folder};
    final reordered = <ChatFolder>[];
    for (final id in orderedIds) {
      final folder = byId.remove(id);
      if (folder != null) {
        reordered.add(folder);
      }
    }
    reordered.addAll(state.where((folder) => byId.containsKey(folder.id)));
    _commit(reordered);
  }

  void delete(String folderId) {
    _commit([
      for (final folder in state)
        if (folder.id != folderId) folder,
    ]);
    ref.read(chatFilterOrderProvider.notifier).reorder([
      for (final id in ref.read(chatFilterOrderProvider))
        if (id != folderId) id,
    ]);
    if (ref.read(activeChatFolderProvider) == folderId) {
      ref.read(activeChatFolderProvider.notifier).select(null);
    }
  }

  void addRoom(String folderId, String roomId) {
    _commit([
      for (final folder in state)
        if (folder.id == folderId)
          folder.copyWith(
            roomIds: _normalizeRoomIds([...folder.roomIds, roomId]),
          )
        else
          folder,
    ]);
  }

  void removeRoom(String folderId, String roomId) {
    _commit([
      for (final folder in state)
        if (folder.id == folderId)
          folder.copyWith(
            roomIds: [
              for (final id in folder.roomIds)
                if (id != roomId) id,
            ],
          )
        else
          folder,
    ]);
  }

  void setRooms(String folderId, List<String> roomIds) {
    _commit([
      for (final folder in state)
        if (folder.id == folderId)
          folder.copyWith(roomIds: _normalizeRoomIds(roomIds))
        else
          folder,
    ]);
  }

  void ensureFavoriteFolder() {
    if (state.any((folder) => folder.isFavorite)) {
      return;
    }
    create(name: '즐겨찾기', icon: '⭐', roomIds: const [], isFavorite: true);
  }

  void toggleFavoriteRoom(String roomId) {
    ensureFavoriteFolder();
    _commit([
      for (final folder in state)
        if (folder.isFavorite)
          folder.copyWith(
            roomIds: folder.roomIds.contains(roomId)
                ? [
                    for (final id in folder.roomIds)
                      if (id != roomId) id,
                  ]
                : _normalizeRoomIds([...folder.roomIds, roomId]),
          )
        else
          folder,
    ]);
  }

  bool isFavoriteRoom(String roomId) {
    for (final folder in state) {
      if (folder.isFavorite && folder.roomIds.contains(roomId)) {
        return true;
      }
    }
    return false;
  }

  List<String> _normalizeRoomIds(List<String> roomIds) {
    return [
      for (final id in <String>{...roomIds})
        if (id.isNotEmpty) id,
    ];
  }

  Future<void> _loadFromServer(String accessToken, String userKey) async {
    try {
      final remoteFolders = await ref
          .read(chatApiProvider)
          .chatFolders(accessToken);
      if (_loadedUserKey != userKey) {
        return;
      }
      if (_dirtyWhileLoading) {
        _scheduleSave();
        return;
      }
      if (remoteFolders.isEmpty && _cachedFolders.isNotEmpty) {
        _scheduleSave();
        return;
      }
      _cachedFolders = [
        for (final folder in remoteFolders) _folderFromDto(folder),
      ];
      _writeLocalFolders(userKey, _cachedFolders);
      state = _cachedFolders;
    } on Object {
      // Folder settings should never block chat usage.
    } finally {
      if (_loadedUserKey == userKey) {
        _isLoading = false;
        _dirtyWhileLoading = false;
      }
    }
  }

  void _commit(List<ChatFolder> folders) {
    _cachedFolders = folders;
    state = folders;
    final userKey = _loadedUserKey;
    if (userKey != null) {
      _writeLocalFolders(userKey, folders);
    }
    if (_isLoading) {
      _dirtyWhileLoading = true;
    }
    _scheduleSave();
  }

  void _scheduleSave() {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null ||
        session.accessToken.isEmpty ||
        _userKey(session) == null) {
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), () {
      final folders = state;
      unawaited(_saveToServer(session.accessToken, folders));
    });
  }

  Future<void> _saveToServer(
    String accessToken,
    List<ChatFolder> folders,
  ) async {
    try {
      await ref
          .read(chatApiProvider)
          .saveChatFolders(
            accessToken: accessToken,
            folders: [for (final folder in folders) _folderToDto(folder)],
          );
    } on Object {
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(seconds: 5), _scheduleSave);
    }
  }

  List<ChatFolder> _readLocalFolders(String userKey) {
    final file = _localFolderFile(userKey);
    if (file == null || !file.existsSync()) {
      return const [];
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! List) {
        return const [];
      }
      return [
        for (final item in decoded)
          if (item is Map)
            ChatFolder(
              id: item['id'] as String? ?? '',
              name: item['name'] as String? ?? '',
              icon: item['icon'] as String? ?? '',
              roomIds: [
                for (final roomId in item['roomIds'] as List? ?? const [])
                  if (roomId is String && roomId.isNotEmpty) roomId,
              ],
              isFavorite:
                  item['favorite'] as bool? ??
                  item['isFavorite'] as bool? ??
                  false,
            ),
      ].where((folder) => folder.id.isNotEmpty).toList();
    } on Object {
      return const [];
    }
  }

  void _writeLocalFolders(String userKey, List<ChatFolder> folders) {
    final file = _localFolderFile(userKey);
    if (file == null) {
      return;
    }
    try {
      file.writeAsStringSync(
        jsonEncode([
          for (final folder in folders)
            {
              'id': folder.id,
              'name': folder.name,
              'icon': folder.icon,
              'roomIds': _normalizeRoomIds(folder.roomIds),
              'favorite': folder.isFavorite,
            },
        ]),
      );
    } on Object {
      // Local cache is best-effort; server persistence remains authoritative.
    }
  }

  File? _localFolderFile(String userKey) {
    return _avaLocalCacheFile('chat_folders', userKey);
  }

  String? _userKey(AuthSession? session) {
    final user = session?.user;
    if (user == null) {
      return null;
    }
    if (user.id.isNotEmpty) {
      return user.id;
    }
    if (user.email.isNotEmpty) {
      return user.email;
    }
    return null;
  }

  ChatFolder _folderFromDto(ChatFolderDto dto) {
    return ChatFolder(
      id: dto.id,
      name: dto.name,
      icon: dto.icon,
      roomIds: _normalizeRoomIds(dto.roomIds),
      isFavorite: dto.favorite,
    );
  }

  ChatFolderDto _folderToDto(ChatFolder folder) {
    return ChatFolderDto(
      id: folder.id,
      name: folder.name,
      icon: folder.icon,
      roomIds: _normalizeRoomIds(folder.roomIds),
      favorite: folder.isFavorite,
    );
  }
}

class ChatFilterOrder extends Notifier<List<String>> {
  Timer? _saveTimer;
  String? _loadedUserKey;
  bool _isLoading = false;
  bool _dirtyWhileLoading = false;
  List<String> _cachedIds = const [unreadChatFolderId];

  @override
  List<String> build() {
    ref.onDispose(() => _saveTimer?.cancel());
    final session = ref.watch(authControllerProvider).value?.session;
    final userKey = _userKey(session);
    if (session == null || session.accessToken.isEmpty || userKey == null) {
      _saveTimer?.cancel();
      _loadedUserKey = null;
      _isLoading = false;
      _dirtyWhileLoading = false;
      _cachedIds = const [unreadChatFolderId];
      return _cachedIds;
    }

    if (_loadedUserKey != userKey && !_isLoading) {
      _loadedUserKey = userKey;
      _isLoading = true;
      _dirtyWhileLoading = false;
      _cachedIds = _readLocalIds(userKey);
      Future<void>.microtask(
        () => _loadFromServer(session.accessToken, userKey),
      );
      return _cachedIds;
    }

    return _cachedIds;
  }

  void reorder(List<String> orderedIds) {
    _commit(_normalizeFilterIds(orderedIds));
  }

  Future<void> _loadFromServer(String accessToken, String userKey) async {
    try {
      final remoteIds = await ref
          .read(chatApiProvider)
          .chatFolderOrder(accessToken);
      if (_loadedUserKey != userKey) {
        return;
      }
      if (_dirtyWhileLoading) {
        _scheduleSave();
        return;
      }
      if (remoteIds.isEmpty && _cachedIds.isNotEmpty) {
        _scheduleSave();
        return;
      }
      _cachedIds = _normalizeFilterIds(remoteIds);
      _writeLocalIds(userKey, _cachedIds);
      state = _cachedIds;
    } on Object {
      // Filter order is cosmetic and should never block chat usage.
    } finally {
      if (_loadedUserKey == userKey) {
        _isLoading = false;
        _dirtyWhileLoading = false;
      }
    }
  }

  void _commit(List<String> ids) {
    _cachedIds = ids;
    state = ids;
    final userKey = _loadedUserKey;
    if (userKey != null) {
      _writeLocalIds(userKey, ids);
    }
    if (_isLoading) {
      _dirtyWhileLoading = true;
    }
    _scheduleSave();
  }

  void _scheduleSave() {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null ||
        session.accessToken.isEmpty ||
        _userKey(session) == null) {
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), () {
      final ids = state;
      unawaited(_saveToServer(session.accessToken, ids));
    });
  }

  Future<void> _saveToServer(String accessToken, List<String> ids) async {
    try {
      await ref
          .read(chatApiProvider)
          .saveChatFolderOrder(accessToken: accessToken, filterIds: ids);
    } on Object {
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(seconds: 5), _scheduleSave);
    }
  }

  List<String> _readLocalIds(String userKey) {
    final file = _localFile(userKey);
    if (file == null || !file.existsSync()) {
      return const [unreadChatFolderId];
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! List) {
        return const [unreadChatFolderId];
      }
      return _normalizeFilterIds([
        for (final item in decoded)
          if (item is String) item,
      ]);
    } on Object {
      return const [unreadChatFolderId];
    }
  }

  void _writeLocalIds(String userKey, List<String> ids) {
    final file = _localFile(userKey);
    if (file == null) {
      return;
    }
    try {
      file.writeAsStringSync(jsonEncode(_normalizeFilterIds(ids)));
    } on Object {
      // Local cache is best-effort; server persistence remains authoritative.
    }
  }

  File? _localFile(String userKey) {
    return _avaLocalCacheFile('chat_filter_order', userKey);
  }

  List<String> _normalizeFilterIds(List<String> ids) {
    final normalized = <String>[];
    for (final id in ids) {
      if (id.isEmpty || normalized.contains(id)) {
        continue;
      }
      normalized.add(id);
    }
    if (!normalized.contains(unreadChatFolderId)) {
      normalized.insert(0, unreadChatFolderId);
    }
    return normalized;
  }

  String? _userKey(AuthSession? session) {
    final user = session?.user;
    if (user == null) {
      return null;
    }
    if (user.id.isNotEmpty) {
      return user.id;
    }
    if (user.email.isNotEmpty) {
      return user.email;
    }
    return null;
  }
}

class QuietChatRooms extends Notifier<List<String>> {
  Timer? _saveTimer;
  String? _loadedUserKey;
  bool _isLoading = false;
  bool _dirtyWhileLoading = false;
  List<String> _cachedRoomIds = const [];

  @override
  List<String> build() {
    ref.onDispose(() => _saveTimer?.cancel());
    final session = ref.watch(authControllerProvider).value?.session;
    final userKey = _userKey(session);
    if (session == null || session.accessToken.isEmpty || userKey == null) {
      _saveTimer?.cancel();
      _loadedUserKey = null;
      _isLoading = false;
      _dirtyWhileLoading = false;
      _cachedRoomIds = const [];
      return const [];
    }

    if (_loadedUserKey != userKey && !_isLoading) {
      _loadedUserKey = userKey;
      _isLoading = true;
      _dirtyWhileLoading = false;
      _cachedRoomIds = _readLocalRoomIds(userKey);
      Future<void>.microtask(
        () => _loadFromServer(session.accessToken, userKey),
      );
      return _cachedRoomIds;
    }

    return _cachedRoomIds;
  }

  void add(String roomId) {
    final normalized = _normalizeRoomIds([...state, roomId]);
    _commit(normalized);
    unawaited(WindowControl.closeChatFloating(roomId));
  }

  void remove(String roomId) {
    _commit([
      for (final id in state)
        if (id != roomId) id,
    ]);
  }

  void clear() {
    _commit(const []);
  }

  bool contains(String roomId) => state.contains(roomId);

  Future<void> _loadFromServer(String accessToken, String userKey) async {
    try {
      final remoteIds = await ref
          .read(chatApiProvider)
          .quietChatRooms(accessToken);
      if (_loadedUserKey != userKey) {
        return;
      }
      if (_dirtyWhileLoading) {
        _scheduleSave();
        return;
      }
      if (remoteIds.isEmpty && _cachedRoomIds.isNotEmpty) {
        _scheduleSave();
        return;
      }
      _cachedRoomIds = _normalizeRoomIds(remoteIds);
      _writeLocalRoomIds(userKey, _cachedRoomIds);
      state = _cachedRoomIds;
    } on Object {
      // Quiet-room settings should never block chat usage.
    } finally {
      if (_loadedUserKey == userKey) {
        _isLoading = false;
        _dirtyWhileLoading = false;
      }
    }
  }

  void _commit(List<String> roomIds) {
    _cachedRoomIds = roomIds;
    state = roomIds;
    final userKey = _loadedUserKey;
    if (userKey != null) {
      _writeLocalRoomIds(userKey, roomIds);
    }
    if (_isLoading) {
      _dirtyWhileLoading = true;
    }
    _scheduleSave();
  }

  void _scheduleSave() {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null ||
        session.accessToken.isEmpty ||
        _userKey(session) == null) {
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), () {
      final roomIds = state;
      unawaited(_saveToServer(session.accessToken, roomIds));
    });
  }

  Future<void> _saveToServer(String accessToken, List<String> roomIds) async {
    try {
      await ref
          .read(chatApiProvider)
          .saveQuietChatRooms(accessToken: accessToken, roomIds: roomIds);
    } on Object {
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(seconds: 5), _scheduleSave);
    }
  }

  List<String> _readLocalRoomIds(String userKey) {
    final file = _localFile(userKey);
    if (file == null || !file.existsSync()) {
      return const [];
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! List) {
        return const [];
      }
      return _normalizeRoomIds([
        for (final item in decoded)
          if (item is String) item,
      ]);
    } on Object {
      return const [];
    }
  }

  void _writeLocalRoomIds(String userKey, List<String> roomIds) {
    final file = _localFile(userKey);
    if (file == null) {
      return;
    }
    try {
      file.writeAsStringSync(jsonEncode(_normalizeRoomIds(roomIds)));
    } on Object {
      // Local cache is best-effort; server persistence remains authoritative.
    }
  }

  File? _localFile(String userKey) {
    return _avaLocalCacheFile('quiet_chat_rooms', userKey);
  }

  List<String> _normalizeRoomIds(List<String> roomIds) {
    return [
      for (final id in <String>{...roomIds})
        if (id.isNotEmpty) id,
    ];
  }

  String? _userKey(AuthSession? session) {
    final user = session?.user;
    if (user == null) {
      return null;
    }
    if (user.id.isNotEmpty) {
      return user.id;
    }
    if (user.email.isNotEmpty) {
      return user.email;
    }
    return null;
  }
}

class SelectedChatRoom extends Notifier<ChatRoom?> {
  @override
  ChatRoom? build() => null;

  void open(ChatRoom room) {
    final needsReadSync = room.unreadCount > 0 || room.hasUnreadMention;
    state =
        (needsReadSync
            ? ref.read(chatRoomsProvider.notifier).markRead(room.id)
            : _roomFromCurrentList(room.id)) ??
        room.copyWith(unreadCount: 0, hasUnreadMention: false);
    if (needsReadSync) {
      unawaited(_markReadRemotely(room));
    }
  }

  ChatRoom? _roomFromCurrentList(String roomId) {
    for (final room in ref.read(chatRoomsProvider)) {
      if (room.id == roomId) {
        return room;
      }
    }
    return null;
  }

  void replaceIfOpen(ChatRoom room) {
    if (state?.id == room.id) {
      state = room.copyWith(unreadCount: 0);
    }
  }

  void close() {
    state = null;
  }

  Future<void> _markReadRemotely(ChatRoom room) async {
    if (room.isDraft) {
      return;
    }
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      return;
    }
    try {
      await ref
          .read(chatApiProvider)
          .markRead(accessToken: session.accessToken, roomCode: room.id);
      ref.read(chatRoomsProvider.notifier).markRead(room.id);
    } on Object {
      // Local unread state is already cleared; the room panel will retry.
    }
  }
}

class FocusedChatRoomId extends Notifier<String?> {
  @override
  String? build() => null;

  void focus(ChatRoom room) {
    state = room.id;
  }

  void clear() {
    state = null;
  }
}

class FocusedChatMessageId extends Notifier<String?> {
  @override
  String? build() => null;

  void focus(String? messageId) {
    state = (messageId == null || messageId.isEmpty) ? null : messageId;
  }

  void clear() {
    state = null;
  }
}

class MessengerPage extends ConsumerStatefulWidget {
  const MessengerPage({super.key, this.initialTab = MessengerTab.friends});

  final MessengerTab initialTab;

  @override
  ConsumerState<MessengerPage> createState() => _MessengerPageState();
}

class _MessengerPageState extends ConsumerState<MessengerPage>
    with WidgetsBindingObserver {
  ChatRoom? _visibleChatRoom;
  bool _isChatPanelClosing = false;
  String? _inboxAccessToken;
  ChatInboxRealtimeClient? _inboxClient;
  StreamSubscription<ChatRealtimeEventDto>? _inboxSubscription;
  Timer? _inboxReconcileTimer;
  Timer? _inboxEventReconcileTimer;
  Timer? _mentionNotificationRefreshTimer;
  bool _isReconcilingInbox = false;
  String? _runtimeSyncSignature;
  String? _presenceAccessToken;
  String _presenceStatus = _presenceOnline;
  Timer? _presenceTimer;
  String? _azoomNoticeAccessToken;
  String? _azoomNoticeCompany;
  AzoomVoiceRealtimeClient? _azoomNoticeClient;
  StreamSubscription<AzoomVoiceChannelDto>? _azoomNoticeSubscription;
  final Map<String, int> _azoomNoticeParticipantCounts = <String, int>{};
  final GlobalKey _azoomPageKey = GlobalKey(debugLabel: 'azoom-page-keepalive');
  String? _chatWarmupSignature;
  String? _chatWarmupScope;
  bool _chatCacheReady = false;
  bool _isAppSetupLoading = false;
  int _appSetupCompleted = 0;
  int _appSetupTotal = 0;
  String? _desktopWindowMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (widget.initialTab == MessengerTab.friends) {
          resetMessengerToCompanyPage(ref);
        } else {
          ref
              .read(activeMessengerTabProvider.notifier)
              .setTab(widget.initialTab);
        }
        _syncWindowTitle(ref.read(activeMessengerTabProvider));
        _syncRuntimeForCurrentSession(refreshRooms: true);
      }
    });
    WindowControl.setNotificationReplyHandler(_sendNotificationReply);
    WindowControl.setFloatingHandler(_handleFloatingAction);
    if (Platform.isAndroid) {
      unawaited(_ensureMobileNotificationPermission());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPresence();
    WindowControl.setNotificationReplyHandler(null);
    WindowControl.setFloatingHandler(null);
    _stopInboxRealtime();
    _mentionNotificationRefreshTimer?.cancel();
    _stopAzoomVoiceStartWatcher(clearNotifications: false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_handleLifecycleState(state));
  }

  Future<void> _handleLifecycleState(AppLifecycleState state) async {
    final nextStatus = switch (state) {
      AppLifecycleState.resumed => _presenceOnline,
      AppLifecycleState.inactive ||
      AppLifecycleState.hidden ||
      AppLifecycleState.paused => _presenceBackground,
      AppLifecycleState.detached => _presenceOffline,
    };
    if (nextStatus == _presenceBackground &&
        await WindowControl.isAvaForeground()) {
      _setPresenceStatus(_presenceOnline);
      _syncMobileActiveChatRoom();
      return;
    }
    _setPresenceStatus(nextStatus);
    if (state == AppLifecycleState.resumed) {
      _syncMobileActiveChatRoom();
    } else {
      _clearMobileActiveChatRoom();
    }
  }

  Future<void> _ensureMobileNotificationPermission() async {
    try {
      final status = await Permission.notification.status;
      if (!status.isGranted && !status.isLimited) {
        await Permission.notification.request();
      }
    } on Object {
      // Android 12L and older do not have a runtime notification permission.
    }
  }

  String? _warmupScopeFor(AuthSession? session, String? activeCompany) {
    if (session == null || session.accessToken.isEmpty) {
      return null;
    }
    final userKey = session.user.id.isNotEmpty
        ? session.user.id
        : session.user.email;
    if (userKey.isEmpty) {
      return null;
    }
    return '$userKey|${activeCompany ?? ''}';
  }

  String _setupCompletedKey(String scope) {
    return '$_appSetupCompletedPrefix.${base64Url.encode(utf8.encode(scope))}';
  }

  bool _hasAnyCompletedAppSetupMarker(SharedPreferences prefs) {
    for (final key in prefs.getKeys()) {
      if (key.startsWith('$_appSetupCompletedPrefix.') &&
          (prefs.getBool(key) ?? false)) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _readAppSetupCompleted(
    SharedPreferences prefs,
    String scope,
  ) async {
    if (prefs.getString(_appSetupCompletedVersionKey) == AppVersion.name) {
      return true;
    }
    final completed =
        (prefs.getBool(_setupCompletedKey(scope)) ?? false) ||
        _hasAnyCompletedAppSetupMarker(prefs);
    if (completed) {
      await prefs.setBool(_appSetupInstallCompletedKey, true);
      await prefs.setString(_appSetupCompletedVersionKey, AppVersion.name);
      return true;
    }
    return false;
  }

  void _ensureChatCacheScope({
    required AuthSession? session,
    required String? activeCompany,
  }) {
    final scope = _warmupScopeFor(session, activeCompany);
    if (scope == null) {
      _chatWarmupScope = null;
      _chatCacheReady = false;
      return;
    }
    if (_chatWarmupScope == scope) {
      return;
    }
    _chatWarmupScope = scope;
    _chatCacheReady = false;
    ref.read(chatMessageMemoryCacheProvider.notifier).configureScope(scope);
    unawaited(_hydrateChatCache(scope));
  }

  Future<void> _hydrateChatCache(String scope) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _readAppSetupCompleted(prefs, scope);
      await ref.read(chatMessageMemoryCacheProvider.notifier).hydrate(scope);
      if (!mounted || _chatWarmupScope != scope) {
        return;
      }
      setState(() {
        _chatCacheReady = true;
      });
    } on Object {
      if (!mounted || _chatWarmupScope != scope) {
        return;
      }
      setState(() {
        _chatCacheReady = true;
      });
    }
  }

  Future<void> _markAppSetupCompleted(String scope) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_setupCompletedKey(scope), true);
      await prefs.setBool(_appSetupInstallCompletedKey, true);
      await prefs.setString(_appSetupCompletedVersionKey, AppVersion.name);
    } on Object {
      // Missing the marker only means the next run will warm silently again.
    }
    if (!mounted || _chatWarmupScope != scope) {
      return;
    }
  }

  void _scheduleChatHistoryWarmup({
    required AuthSession? session,
    required String? activeCompany,
  }) {
    if (session == null || session.accessToken.isEmpty) {
      _chatWarmupSignature = null;
      if (_isAppSetupLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _isAppSetupLoading = false;
            _appSetupCompleted = 0;
            _appSetupTotal = 0;
          });
        });
      }
      return;
    }
    final scope = _warmupScopeFor(session, activeCompany);
    if (scope == null || _chatWarmupScope != scope || !_chatCacheReady) {
      return;
    }
    final fallbackRooms = _warmupEligibleRooms(
      ref.read(chatRoomsProvider),
    ).take(_silentChatWarmupRoomLimit).toList(growable: false);
    final notificationCache = ref.read(notificationCenterCacheProvider);
    final shouldPreloadNotifications =
        !notificationCache.hasLoaded && !notificationCache.loading;
    final signature =
        '$scope:${fallbackRooms.map((room) => room.id).join('|')}:notifications:v2';
    if (_chatWarmupSignature == signature || _isAppSetupLoading) {
      return;
    }

    final cache = ref.read(chatMessageMemoryCacheProvider.notifier);
    final hasPendingFallbackRoom = fallbackRooms.any(
      (room) => cache.messagesFor(room.id).isEmpty,
    );
    if (!hasPendingFallbackRoom && !shouldPreloadNotifications) {
      _chatWarmupSignature = signature;
      return;
    }

    _chatWarmupSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        _warmUpChatHistories(
          session: session,
          fallbackRooms: fallbackRooms,
          signature: signature,
          scope: scope,
          preloadNotifications: shouldPreloadNotifications,
          showSetupOverlay: false,
        ),
      );
    });
  }

  List<ChatRoom> _warmupEligibleRooms(List<ChatRoom> rooms) {
    return [
      for (final room in rooms)
        if (!room.isDraft && !room.id.startsWith('azoom-')) room,
    ];
  }

  Future<void> _warmUpChatHistories({
    required AuthSession session,
    required List<ChatRoom> fallbackRooms,
    required String signature,
    required String scope,
    required bool preloadNotifications,
    required bool showSetupOverlay,
  }) async {
    if (_isAppSetupLoading) {
      return;
    }
    if (showSetupOverlay) {
      setState(() {
        _isAppSetupLoading = true;
        _appSetupCompleted = 0;
        _appSetupTotal = 0;
      });
    }

    var completedSuccessfully = false;
    final resolvedRooms = await _resolveWarmupRooms(
      session: session,
      fallbackRooms: fallbackRooms,
      signature: signature,
      requireRemoteRooms: false,
    );
    if (resolvedRooms == null) {
      if (mounted && _chatWarmupSignature == signature) {
        _chatWarmupSignature = null;
        if (showSetupOverlay) {
          setState(() {
            _isAppSetupLoading = false;
            _appSetupCompleted = 0;
            _appSetupTotal = 0;
          });
        }
      }
      return;
    }
    final cache = ref.read(chatMessageMemoryCacheProvider.notifier);
    final rooms = [
      for (final room in resolvedRooms.take(
        showSetupOverlay ? resolvedRooms.length : _silentChatWarmupRoomLimit,
      ))
        if (cache.messagesFor(room.id).isEmpty) room,
    ];
    final setupTotal = rooms.length + (preloadNotifications ? 1 : 0);
    if (setupTotal == 0) {
      await cache.flush();
      await _markAppSetupCompleted(scope);
      if (mounted && _chatWarmupSignature == signature) {
        if (showSetupOverlay) {
          setState(() {
            _isAppSetupLoading = false;
            _appSetupCompleted = 0;
            _appSetupTotal = 0;
          });
        }
        completedSuccessfully = true;
      }
      return;
    }
    if (showSetupOverlay && mounted) {
      setState(() {
        _appSetupTotal = setupTotal;
      });
    }

    var nextIndex = 0;
    void markSetupUnitDone() {
      if (!mounted || !showSetupOverlay) {
        return;
      }
      setState(() {
        _appSetupCompleted = (_appSetupCompleted + 1).clamp(0, _appSetupTotal);
      });
    }

    final workerCount = showSetupOverlay ? math.min(4, rooms.length) : 1;
    Future<void> worker() async {
      while (mounted) {
        final index = nextIndex++;
        if (index >= rooms.length) {
          return;
        }
        await _warmUpChatRoom(session, rooms[index], signature);
        if (!mounted) {
          return;
        }
        markSetupUnitDone();
        if (!showSetupOverlay) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
      }
    }

    Future<void> notificationWorker() async {
      if (!preloadNotifications) {
        return;
      }
      await _warmUpNotificationCenter(session, signature);
      markSetupUnitDone();
    }

    try {
      await Future.wait([
        notificationWorker(),
        for (var i = 0; i < workerCount; i++) worker(),
      ]);
      await cache.flush();
      completedSuccessfully = true;
    } finally {
      if (mounted && _chatWarmupSignature == signature) {
        if (showSetupOverlay) {
          setState(() {
            _isAppSetupLoading = false;
            _appSetupCompleted = 0;
            _appSetupTotal = 0;
          });
        }
        if (completedSuccessfully) {
          await _markAppSetupCompleted(scope);
        } else {
          _chatWarmupSignature = null;
        }
      }
    }
  }

  Future<List<ChatRoom>?> _resolveWarmupRooms({
    required AuthSession session,
    required List<ChatRoom> fallbackRooms,
    required String signature,
    required bool requireRemoteRooms,
  }) async {
    final roomsNotifier = ref.read(chatRoomsProvider.notifier);
    await roomsNotifier.refreshFromServer();
    if (!mounted ||
        _chatWarmupSignature != signature ||
        ref.read(authControllerProvider).value?.session?.accessToken !=
            session.accessToken) {
      return null;
    }
    final remoteLoaded = roomsNotifier.hasLoadedRemoteRooms;
    final latestRooms = _warmupEligibleRooms(ref.read(chatRoomsProvider));
    if (latestRooms.isNotEmpty || remoteLoaded) {
      return latestRooms;
    }
    if (fallbackRooms.isNotEmpty) {
      return fallbackRooms;
    }
    if (requireRemoteRooms) {
      return null;
    }
    return const [];
  }

  Future<void> _warmUpNotificationCenter(
    AuthSession session,
    String signature,
  ) async {
    final currentSession = ref.read(authControllerProvider).value?.session;
    if (currentSession?.accessToken != session.accessToken) {
      return;
    }
    ref
        .read(notificationCenterCacheProvider.notifier)
        .beginLoading(silent: true);
    try {
      final notifications = await ref
          .read(chatApiProvider)
          .mentionNotifications(
            accessToken: session.accessToken,
            status: 'all',
            limit: 120,
          );
      if (!mounted ||
          _chatWarmupSignature != signature ||
          ref.read(authControllerProvider).value?.session?.accessToken !=
              session.accessToken) {
        return;
      }
      ref
          .read(notificationCenterCacheProvider.notifier)
          .setNotifications(notifications);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ref.read(notificationCenterCacheProvider.notifier).setError(error);
    }
  }

  void _scheduleMentionNotificationRefresh(AuthSession session) {
    _mentionNotificationRefreshTimer?.cancel();
    _mentionNotificationRefreshTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_refreshMentionNotificationCache(session)),
    );
  }

  Future<void> _refreshMentionNotificationCache(AuthSession session) async {
    final currentSession = ref.read(authControllerProvider).value?.session;
    if (!mounted || currentSession?.accessToken != session.accessToken) {
      return;
    }
    ref
        .read(notificationCenterCacheProvider.notifier)
        .beginLoading(silent: true);
    try {
      final notifications = await ref
          .read(chatApiProvider)
          .mentionNotifications(
            accessToken: session.accessToken,
            status: 'all',
            limit: 120,
          );
      if (!mounted ||
          ref.read(authControllerProvider).value?.session?.accessToken !=
              session.accessToken) {
        return;
      }
      ref
          .read(notificationCenterCacheProvider.notifier)
          .setNotifications(notifications);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ref.read(notificationCenterCacheProvider.notifier).setError(error);
    }
  }

  Future<void> _warmUpChatRoom(
    AuthSession session,
    ChatRoom room,
    String signature,
  ) async {
    final currentSession = ref.read(authControllerProvider).value?.session;
    if (currentSession?.accessToken != session.accessToken) {
      return;
    }
    try {
      final messages = await ref
          .read(chatApiProvider)
          .messages(
            accessToken: session.accessToken,
            roomCode: room.id,
            limit: _silentChatWarmupMessageLimit,
          );
      if (!mounted ||
          _chatWarmupSignature != signature ||
          ref.read(authControllerProvider).value?.session?.accessToken !=
              session.accessToken) {
        return;
      }
      final currentProfile = ref.read(currentUserProfileProvider);
      final mapped = [
        for (final message in messages)
          _warmupMessageFromDto(
            message,
            room: room,
            currentUserId: session.user.id,
            currentUserProfile: currentProfile,
          ),
      ];
      if (mapped.isNotEmpty) {
        ref
            .read(chatMessageMemoryCacheProvider.notifier)
            .put(room.id, mapped, persist: false);
      }
    } on Object {
      // Warm-up should never block the app; opening the room will retry normally.
    }
  }

  ChatMessage _warmupMessageFromDto(
    ChatMessageDto message, {
    required ChatRoom room,
    required String currentUserId,
    required PersonProfile currentUserProfile,
  }) {
    final isMine = message.senderId == currentUserId;
    return ChatMessage(
      id: message.id,
      senderId: message.senderId,
      sender: isMine
          ? currentUserProfile
          : _warmupSenderProfile(message, room: room),
      text: message.content,
      time: formatChatClockTime(message.sentAt),
      isMine: isMine,
      sentAt: message.sentAt,
      unreadCount: message.unreadCount,
      isSystem: message.systemMessage,
      isSilent: message.silent,
      isSpoiler: message.spoiler,
      attachment: _warmupAttachmentFromDto(message.attachment),
      mentions: [
        for (final mention in message.mentions)
          ChatMention(userId: mention.userId, displayName: mention.displayName),
      ],
    );
  }

  PersonProfile _warmupSenderProfile(
    ChatMessageDto message, {
    required ChatRoom room,
  }) {
    for (final member in room.members) {
      if ((member.id != null && member.id == message.senderId) ||
          member.name == message.senderName) {
        return member;
      }
    }
    final avatarColor = message.senderAvatarColor.isEmpty
        ? _warmupAvatarColorFor(message.senderId)
        : avatarColorFromHex(message.senderAvatarColor);
    return PersonProfile(
      id: message.senderId.isEmpty ? null : message.senderId,
      name: message.senderName.isEmpty ? room.title : message.senderName,
      nickname: message.senderNickname.isEmpty ? null : message.senderNickname,
      color: avatarColor,
      imageUrl: message.senderAvatarImageUrl.isEmpty
          ? null
          : message.senderAvatarImageUrl,
    );
  }

  ChatAttachment? _warmupAttachmentFromDto(ChatAttachmentDto? attachment) {
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

  Color _warmupAvatarColorFor(String senderId) {
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

  void _openChatPanel(ChatRoom room) {
    final current = _visibleChatRoom;
    if (!_isChatPanelClosing &&
        current != null &&
        _chatPanelShellEquals(current, room)) {
      unawaited(_resizeWindowForTab(ref.read(activeMessengerTabProvider)));
      _syncMobileActiveChatRoom();
      return;
    }
    setState(() {
      _visibleChatRoom = room;
      _isChatPanelClosing = false;
    });
    unawaited(_resizeWindowForTab(ref.read(activeMessengerTabProvider)));
    _syncMobileActiveChatRoom();
  }

  bool _chatPanelShellEquals(ChatRoom first, ChatRoom second) {
    if (first.id != second.id ||
        first.title != second.title ||
        first.avatarImageUrl != second.avatarImageUrl ||
        first.isDraft != second.isDraft ||
        first.isMuted != second.isMuted ||
        first.displayParticipantCount != second.displayParticipantCount ||
        first.members.length != second.members.length) {
      return false;
    }
    return _chatNoticeEquals(first.notice, second.notice);
  }

  bool _chatNoticeEquals(ChatNotice? first, ChatNotice? second) {
    if (identical(first, second)) {
      return true;
    }
    if (first == null || second == null) {
      return false;
    }
    return first.messageId == second.messageId &&
        first.senderId == second.senderId &&
        first.senderName == second.senderName &&
        first.content == second.content &&
        first.sentAt == second.sentAt;
  }

  void _requestCloseChatPanel({bool clearMobileFocus = false}) {
    if (_visibleChatRoom == null || _isChatPanelClosing) {
      return;
    }

    setState(() {
      _isChatPanelClosing = true;
    });

    _closeChatPanelNow(clearMobileFocus: clearMobileFocus);
  }

  void _closeChatPanelNow({bool clearMobileFocus = false}) {
    ref.read(selectedChatRoomProvider.notifier).close();
    if (clearMobileFocus) {
      ref.read(focusedChatRoomIdProvider.notifier).clear();
      ref.read(focusedChatMessageIdProvider.notifier).clear();
    }
    setState(() {
      _visibleChatRoom = null;
      _isChatPanelClosing = false;
    });
    _clearMobileActiveChatRoom();
    unawaited(_resizeWindowForTab(ref.read(activeMessengerTabProvider)));
  }

  void _clearChatPanel() {
    if (_visibleChatRoom == null && !_isChatPanelClosing) {
      return;
    }

    setState(() {
      _visibleChatRoom = null;
      _isChatPanelClosing = false;
    });
    _clearMobileActiveChatRoom();
  }

  void _syncMobileActiveChatRoom() {
    final visibleRoomId = _visibleChatRoom?.id;
    unawaited(
      ref.read(mobilePushControllerProvider).setActiveChatRoom(visibleRoomId),
    );
  }

  void _clearMobileActiveChatRoom() {
    unawaited(ref.read(mobilePushControllerProvider).setActiveChatRoom(null));
  }

  void _syncWindowTitle(MessengerTab tab) {
    unawaited(WindowControl.setWindowTitle(_windowTitleForTab(tab)));
  }

  Future<void> _resizeWindowForTab(MessengerTab tab) async {
    if (_visibleChatRoom != null && tab == MessengerTab.chats) {
      await _applyDesktopWindowMode('expanded');
      return;
    }
    switch (tab) {
      case MessengerTab.azoom:
        await _applyDesktopWindowMode('azoom');
      case MessengerTab.calendar:
      case MessengerTab.avaAi:
      case MessengerTab.avaStock:
        await _applyDesktopWindowMode('expanded');
      case MessengerTab.friends:
      case MessengerTab.chats:
      case MessengerTab.notifications:
        await _applyDesktopWindowMode('compact');
      case MessengerTab.more:
        if (_isAdminMoreSession(
          ref.read(authControllerProvider).value?.session,
        )) {
          await _applyDesktopWindowMode('expanded');
        } else {
          await _applyDesktopWindowMode('compact');
        }
    }
  }

  Future<void> _applyDesktopWindowMode(String mode) async {
    if (_desktopWindowMode == mode) {
      return;
    }
    _desktopWindowMode = mode;
    switch (mode) {
      case 'azoom':
        await WindowControl.openAzoomMessenger();
      case 'expanded':
        await WindowControl.expandMessenger();
      default:
        await WindowControl.compactMessenger();
    }
  }

  void _syncInboxRealtime(AuthSession? session) {
    if (session == null || session.accessToken.isEmpty) {
      _stopInboxRealtime();
      return;
    }
    if (_inboxAccessToken == session.accessToken) {
      if (_inboxReconcileTimer == null) {
        _startInboxReconcileTimer();
      }
      return;
    }

    _stopInboxRealtime();
    final client = ChatInboxRealtimeClient(
      websocketUrl: ref.read(appConfigProvider).websocketUrl,
      accessToken: session.accessToken,
    );
    _inboxAccessToken = session.accessToken;
    _inboxClient = client;
    _inboxSubscription = client.events.listen(
      (event) => _handleInboxEvent(event, session),
      onError: (_) {},
    );
    client.connect();
    _startInboxReconcileTimer();
  }

  void _syncPresence(AuthSession? session) {
    if (session == null || session.accessToken.isEmpty) {
      _stopPresence();
      return;
    }
    if (_presenceAccessToken == session.accessToken) {
      return;
    }

    _stopPresence();
    _presenceAccessToken = session.accessToken;
    _presenceStatus = _presenceOnline;
    _presenceTimer = Timer.periodic(
      _presenceHeartbeatInterval,
      (_) => _sendPresence(_presenceStatus),
    );
    _sendPresence(_presenceStatus, refreshProfiles: true);
  }

  void _stopPresence() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _presenceAccessToken = null;
  }

  void _setPresenceStatus(String status) {
    if (_presenceStatus == status) {
      return;
    }
    _presenceStatus = status;
    _sendPresence(status, refreshProfiles: true);
  }

  Future<void> _sendPresence(
    String status, {
    bool refreshProfiles = false,
  }) async {
    final accessToken = _presenceAccessToken;
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }
    try {
      await ref
          .read(authApiProvider)
          .updatePresence(accessToken: accessToken, status: status);
      if (!mounted) {
        return;
      }
      if (refreshProfiles) {
        ref.invalidate(userProfilesProvider);
      }
    } on Object {
      // Presence is best-effort; messaging should keep working while reconnecting.
    }
  }

  void _stopInboxRealtime() {
    _inboxAccessToken = null;
    _inboxReconcileTimer?.cancel();
    _inboxReconcileTimer = null;
    _inboxEventReconcileTimer?.cancel();
    _inboxEventReconcileTimer = null;
    _mentionNotificationRefreshTimer?.cancel();
    _mentionNotificationRefreshTimer = null;
    _isReconcilingInbox = false;
    _inboxSubscription?.cancel();
    _inboxSubscription = null;
    _inboxClient?.dispose();
    _inboxClient = null;
  }

  void _syncAzoomVoiceStartWatcher(
    AuthSession? session,
    String? activeCompany,
  ) {
    if (session == null || session.accessToken.isEmpty) {
      _stopAzoomVoiceStartWatcher();
      return;
    }
    final companyKey = activeCompany ?? '';
    if (_azoomNoticeAccessToken == session.accessToken &&
        _azoomNoticeCompany == companyKey) {
      return;
    }
    _stopAzoomVoiceStartWatcher();
    _azoomNoticeAccessToken = session.accessToken;
    _azoomNoticeCompany = companyKey;
    unawaited(_startAzoomVoiceStartWatcher(session.accessToken));
  }

  Future<void> _startAzoomVoiceStartWatcher(String accessToken) async {
    try {
      final channels = await ref.read(azoomApiProvider).channels(accessToken);
      if (!mounted || _azoomNoticeAccessToken != accessToken) {
        return;
      }
      _azoomNoticeParticipantCounts
        ..clear()
        ..addEntries(
          channels.voiceChannels.map(
            (channel) => MapEntry(channel.id, channel.participants.length),
          ),
        );
      for (final channel in channels.voiceChannels) {
        if (_isAllStaffVoiceMeeting(channel.name) &&
            channel.participants.isNotEmpty) {
          ref
              .read(azoomVoiceStartNotificationsProvider.notifier)
              .upsertStarted(
                channelId: channel.id,
                channelName: channel.name,
                roomName: channel.roomName,
                startedAt: channel.startedAt,
              );
        }
      }
      final roomNames = [
        for (final channel in channels.voiceChannels)
          if (channel.roomName.trim().isNotEmpty) channel.roomName.trim(),
      ];
      if (roomNames.isEmpty) {
        return;
      }
      final client = AzoomVoiceRealtimeClient(
        websocketUrl: ref.read(appConfigProvider).websocketUrl,
        accessToken: accessToken,
        roomNames: roomNames,
      );
      _azoomNoticeClient = client;
      _azoomNoticeSubscription = client.states.listen(
        _handleAzoomVoiceNoticeState,
        onError: (_) {},
      );
      client.connect();
    } on Object {
      // The AZOOM page also maintains its own connection; this watcher is
      // best-effort so chat and other pages never block on it.
    }
  }

  void _handleAzoomVoiceNoticeState(AzoomVoiceChannelDto state) {
    if (!mounted || state.id.isEmpty) {
      return;
    }
    final previous = _azoomNoticeParticipantCounts[state.id] ?? 0;
    final next = state.participants.length;
    _azoomNoticeParticipantCounts[state.id] = next;
    if (!_isAllStaffVoiceMeeting(state.name)) {
      return;
    }
    if (next <= 0) {
      ref
          .read(azoomVoiceStartNotificationsProvider.notifier)
          .removeChannel(state.id);
      return;
    }
    ref
        .read(azoomVoiceStartNotificationsProvider.notifier)
        .upsertStarted(
          channelId: state.id,
          channelName: state.name,
          roomName: state.roomName,
          startedAt: state.startedAt,
        );
    if (previous <= 0) {
      unawaited(_showAzoomVoiceStartedToast(state));
    }
  }

  bool _isAllStaffVoiceMeeting(String name) {
    final normalized = name.replaceAll(RegExp(r'\s+'), '');
    return normalized == '\uC804\uC9C1\uC6D0\uD68C\uC758' ||
        normalized == '\uC804\uC9C1\uC6D0';
  }

  Future<void> _showAzoomVoiceStartedToast(AzoomVoiceChannelDto state) async {
    if (!mounted || state.id.isEmpty) {
      return;
    }
    await WindowControl.showChatNotification(
      roomId: 'azoom-voice:${state.id}',
      roomTitle: state.name,
      senderName: 'AZOOM',
      senderNickname: 'AZOOM',
      avatarColor: '#5865F2',
      body:
          '${state.name} \uC74C\uC131\uCC44\uB110 \uD68C\uC758\uAC00 \uC2DC\uC791\uB418\uC5C8\uC2B5\uB2C8\uB2E4.',
    );
  }

  void _stopAzoomVoiceStartWatcher({bool clearNotifications = true}) {
    _azoomNoticeAccessToken = null;
    _azoomNoticeCompany = null;
    _azoomNoticeParticipantCounts.clear();
    if (clearNotifications) {
      ref.read(azoomVoiceStartNotificationsProvider.notifier).clear();
    }
    _azoomNoticeSubscription?.cancel();
    _azoomNoticeSubscription = null;
    _azoomNoticeClient?.dispose();
    _azoomNoticeClient = null;
  }

  void _syncRuntimeForCurrentSession({bool refreshRooms = false}) {
    _syncRuntimeForSession(
      ref.read(authControllerProvider).value?.session,
      ref.read(activeCompanyProvider),
      refreshRooms: refreshRooms,
    );
  }

  void _syncRuntimeForSession(
    AuthSession? session,
    String? activeCompany, {
    bool refreshRooms = false,
  }) {
    final signature = [
      session?.accessToken ?? '',
      session?.user.id ?? '',
      activeCompany ?? '',
    ].join('\u001F');
    final changed = _runtimeSyncSignature != signature;
    _runtimeSyncSignature = signature;

    _syncInboxRealtime(session);
    _syncPresence(session);
    _syncAzoomVoiceStartWatcher(session, activeCompany);
    unawaited(ref.read(mobilePushControllerProvider).sync(session));

    if (session != null &&
        session.accessToken.isNotEmpty &&
        (refreshRooms || changed)) {
      unawaited(ref.read(chatRoomsProvider.notifier).refreshFromServer());
    }
  }

  void _startInboxReconcileTimer() {
    _inboxReconcileTimer?.cancel();
    _inboxReconcileTimer = Timer.periodic(
      _inboxReconcileInterval,
      (_) => unawaited(_reconcileInboxRooms()),
    );
  }

  void _scheduleInboxEventReconcile() {
    if (_inboxEventReconcileTimer?.isActive == true) {
      return;
    }
    _inboxEventReconcileTimer = Timer(
      const Duration(milliseconds: 1200),
      () => unawaited(_reconcileInboxRooms()),
    );
  }

  Future<void> _reconcileInboxRooms() async {
    if (!mounted || _isReconcilingInbox) {
      return;
    }
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      return;
    }
    _isReconcilingInbox = true;
    try {
      await ref.read(chatRoomsProvider.notifier).refreshFromServer(force: true);
    } on Object {
      // WebSocket remains the primary path; this silent reconcile is a fallback.
    } finally {
      _isReconcilingInbox = false;
    }
  }

  Future<void> _handleInboxEvent(
    ChatRealtimeEventDto event,
    AuthSession session,
  ) async {
    if (!mounted || event.room.code.isEmpty) {
      return;
    }
    if (_isAzoomRoomCode(event.room.code)) {
      ref.read(chatRoomsProvider.notifier).remove(event.room.code);
      return;
    }

    if (event.type == 'room-deleted') {
      ref.read(chatRoomsProvider.notifier).remove(event.room.code);
      if (ref.read(selectedChatRoomProvider)?.id == event.room.code) {
        ref.read(selectedChatRoomProvider.notifier).close();
        WindowControl.compactMessenger();
      }
      return;
    }

    if (event.type == 'room') {
      final room = ref
          .read(chatRoomsProvider.notifier)
          .roomFromRemoteRoom(event.room);
      ref
          .read(chatRoomsProvider.notifier)
          .realtimeRoomUpdated(
            room,
            incrementUnread: false,
            isOpen: ref.read(selectedChatRoomProvider)?.id == room.id,
          );
      ref.read(selectedChatRoomProvider.notifier).replaceIfOpen(room);
      return;
    }

    final message = event.message;
    var room = ref
        .read(chatRoomsProvider.notifier)
        .roomFromRemoteRoom(event.room);
    final selectedRoom = ref.read(selectedChatRoomProvider);
    final isOpen = selectedRoom?.id == room.id;
    final isMine = message?.senderId == session.user.id;
    final mentionsMe =
        message?.mentions.any((mention) => mention.userId == session.user.id) ??
        false;
    if (!isOpen && !isMine && mentionsMe) {
      room = room.copyWith(hasUnreadMention: true);
    }
    if (mentionsMe && !isMine) {
      ref.read(notificationCenterRevisionProvider.notifier).bump();
      _scheduleMentionNotificationRefresh(session);
    }
    final preview = chatMessageListPreview(message);

    ref
        .read(chatRoomsProvider.notifier)
        .realtimeRoomUpdated(
          room,
          incrementUnread: !isOpen && !isMine && message?.systemMessage != true,
          isOpen: isOpen,
        );
    if (isOpen) {
      ref.read(selectedChatRoomProvider.notifier).replaceIfOpen(room);
    }
    _scheduleInboxEventReconcile();

    final displayedRoom = ref
        .read(chatRoomsProvider)
        .firstWhere((item) => item.id == room.id, orElse: () => room);

    if (isOpen ||
        displayedRoom.isMuted ||
        ref.read(quietChatRoomsProvider.notifier).contains(displayedRoom.id) ||
        isMine ||
        message == null ||
        message.silent ||
        preview.isEmpty ||
        message.systemMessage) {
      return;
    }
    if (Platform.isAndroid) {
      return;
    }

    final sender = _notificationSender(displayedRoom, message);
    final body = mentionsMe
        ? _mentionNotificationBody(message, session.user.id, preview)
        : preview;
    await WindowControl.showChatNotification(
      roomId: displayedRoom.id,
      roomTitle: displayedRoom.title,
      senderName: sender.name,
      senderNickname: sender.nickname?.isNotEmpty == true
          ? sender.nickname!
          : sender.name,
      avatarColor: colorToHex(sender.color),
      body: body,
    );
  }

  String _mentionNotificationBody(
    ChatMessageDto message,
    String currentUserId,
    String fallback,
  ) {
    ChatMentionDto? mention;
    for (final item in message.mentions) {
      if (item.userId == currentUserId) {
        mention = item;
        break;
      }
    }
    final mentionLabel = mention?.displayName.isNotEmpty == true
        ? '@${mention!.displayName}'
        : '@나';
    var content = message.content.trim();
    if (content.startsWith(mentionLabel)) {
      content = content.substring(mentionLabel.length).trim();
    }
    final body = content.isEmpty ? fallback : content;
    return '[나를 멘션] $mentionLabel${body.isEmpty ? '' : ' $body'}';
  }

  PersonProfile _notificationSender(ChatRoom room, ChatMessageDto message) {
    for (final member in room.members) {
      if ((member.id != null && member.id == message.senderId) ||
          member.name == message.senderName) {
        return member;
      }
    }
    return PersonProfile(
      name: message.senderName.isEmpty ? room.title : message.senderName,
      color: const Color(0xFF7AA06A),
    );
  }

  Future<void> _handleFloatingAction(String action, String roomId) async {
    if (action != 'openRoom' || roomId.isEmpty || !mounted) {
      return;
    }
    const azoomVoicePrefix = 'azoom-voice:';
    if (roomId.startsWith(azoomVoicePrefix)) {
      final channelId = roomId.substring(azoomVoicePrefix.length);
      if (channelId.isEmpty) {
        return;
      }
      ref.read(activeMessengerTabProvider.notifier).setTab(MessengerTab.azoom);
      ref.read(azoomPendingVoiceEntryProvider.notifier).open(channelId);
      await WindowControl.openAzoomMessenger();
      await WindowControl.showMessengerWindow();
      return;
    }
    ChatRoom? room;
    for (final item in ref.read(chatRoomsProvider)) {
      if (item.id == roomId) {
        room = item;
        break;
      }
    }
    final target = room;
    if (target == null) {
      return;
    }

    ref.read(activeMessengerTabProvider.notifier).setTab(MessengerTab.chats);
    ref.read(focusedChatRoomIdProvider.notifier).focus(target);
    ref.read(selectedChatRoomProvider.notifier).open(target);
    await WindowControl.expandMessenger();
    await WindowControl.showMessengerWindow();
  }

  ChatRoom? _findCalendarLinkedRoom(CalendarChatLink link) {
    final roomId = link.chatRoomId.trim();
    final roomName = link.chatRoomName?.trim().toLowerCase();
    for (final room in ref.read(chatRoomsProvider)) {
      if (room.id == roomId) {
        return room;
      }
      if (roomName != null &&
          roomName.isNotEmpty &&
          room.title.trim().toLowerCase() == roomName) {
        return room;
      }
    }
    return null;
  }

  Future<void> _openCalendarChatRoom(CalendarChatLink link) async {
    final roomId = link.chatRoomId.trim();
    if (roomId.isEmpty || !mounted) {
      return;
    }
    var room = _findCalendarLinkedRoom(link);
    if (room == null) {
      await ref.read(chatRoomsProvider.notifier).refreshFromServer(force: true);
      room = _findCalendarLinkedRoom(link);
    }
    if (!mounted) {
      return;
    }
    if (room == null) {
      showAvaToast(context, '연결된 채팅방을 찾지 못했습니다. 채팅방 ID: $roomId');
      return;
    }
    ref.read(activeMessengerTabProvider.notifier).setTab(MessengerTab.chats);
    ref.read(focusedChatRoomIdProvider.notifier).focus(room);
    ref.read(selectedChatRoomProvider.notifier).open(room);
    await WindowControl.expandMessenger();
    await WindowControl.showMessengerWindow();
  }

  Future<void> _openCalendarAzoomMeeting(CalendarAzoomLink link) async {
    final joinUrl = link.azoomJoinUrl?.trim();
    if (joinUrl != null && joinUrl.isNotEmpty) {
      final uri = Uri.tryParse(joinUrl);
      if (uri != null && uri.hasScheme) {
        final opened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (opened) {
          return;
        }
      }
    }

    final roomId = link.azoomRoomId?.trim().isNotEmpty == true
        ? link.azoomRoomId!.trim()
        : link.azoomMeetingId?.trim() ?? '';
    if (roomId.isEmpty) {
      if (mounted) {
        showAvaToast(context, '연결된 AZOOM 회의 ID 또는 입장 URL이 없습니다.');
      }
      return;
    }
    final channelId = roomId.startsWith('azoom-voice:')
        ? roomId.substring('azoom-voice:'.length)
        : roomId;
    ref.read(activeMessengerTabProvider.notifier).setTab(MessengerTab.azoom);
    ref.read(azoomPendingVoiceEntryProvider.notifier).open(channelId);
    await WindowControl.openAzoomMessenger();
    await WindowControl.showMessengerWindow();
  }

  Future<void> _sendNotificationReply(String roomId, String content) async {
    final trimmed = content.trim();
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty || trimmed.isEmpty) {
      return;
    }

    try {
      await ref
          .read(chatApiProvider)
          .markRead(accessToken: session.accessToken, roomCode: roomId);
      await ref
          .read(chatApiProvider)
          .send(
            accessToken: session.accessToken,
            roomCode: roomId,
            content: trimmed,
          );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      showAvaToast(context, authErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ChatRoom?>(selectedChatRoomProvider, (previous, next) {
      if (next != null) {
        _openChatPanel(next);
      } else if (!_isChatPanelClosing) {
        _clearChatPanel();
      }
    });
    ref.listen<MessengerTab>(activeMessengerTabProvider, (previous, next) {
      if (previous == next) {
        return;
      }
      if (next == MessengerTab.chats && _visibleChatRoom == null) {
        final selectedRoom = ref.read(selectedChatRoomProvider);
        if (selectedRoom != null) {
          _openChatPanel(selectedRoom);
        }
      }
      _syncWindowTitle(next);
      if (next == MessengerTab.azoom) {
        unawaited(_resizeWindowForTab(next));
        return;
      }
      if (previous == MessengerTab.azoom) {
        ref.read(azoomVoiceStageActiveProvider.notifier).setActive(false);
        unawaited(() async {
          await WindowControl.restoreMessengerFromAzoom();
          _desktopWindowMode = null;
          await _resizeWindowForTab(next);
        }());
        return;
      }
      if (next == MessengerTab.calendar ||
          next == MessengerTab.avaAi ||
          next == MessengerTab.avaStock ||
          next == MessengerTab.friends ||
          next == MessengerTab.chats ||
          next == MessengerTab.notifications ||
          next == MessengerTab.more) {
        unawaited(_resizeWindowForTab(next));
      }
    });
    ref.listen<AsyncValue<AuthState>>(authControllerProvider, (previous, next) {
      _syncRuntimeForSession(
        next.value?.session,
        ref.read(activeCompanyProvider),
        refreshRooms: true,
      );
    });
    ref.listen<String?>(activeCompanyProvider, (previous, next) {
      if (previous == next) {
        return;
      }
      _syncRuntimeForSession(
        ref.read(authControllerProvider).value?.session,
        next,
        refreshRooms: true,
      );
    });

    final authState = ref.watch(authControllerProvider);
    final session = authState.value?.session;
    final activeCompany = ref.watch(activeCompanyProvider);
    _ensureChatCacheScope(session: session, activeCompany: activeCompany);
    _scheduleChatHistoryWarmup(session: session, activeCompany: activeCompany);
    final activeTab = ref.watch(activeMessengerTabProvider);
    final windowTitle = _windowTitleForTab(activeTab);
    final azoomVoiceStageActive = ref.watch(azoomVoiceStageActiveProvider);
    final hideAzoomVoiceChrome =
        activeTab == MessengerTab.azoom && azoomVoiceStageActive;
    final keepHiddenAzoomPage =
        activeTab != MessengerTab.azoom && azoomVoiceStageActive;
    final dimNativePopup = ref.watch(nativePopupDimProvider);
    final visibleRoom = _visibleChatRoom;
    final rootMobileLayout =
        _isMobileRuntime() &&
        MediaQuery.sizeOf(context).width <= _mobileMessengerBreakpoint;
    final fullPageTab =
        activeTab == MessengerTab.azoom ||
        activeTab == MessengerTab.calendar ||
        activeTab == MessengerTab.avaStock ||
        activeTab == MessengerTab.avaAi ||
        activeTab == MessengerTab.notifications ||
        (activeTab == MessengerTab.more && _isAdminMoreSession(session));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Stack(
        children: [
          Column(
            children: [
              if (!hideAzoomVoiceChrome && !rootMobileLayout)
                AppWindowTitleBar(title: windowTitle),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final mobileLayout =
                        _isMobileRuntime() &&
                        constraints.maxWidth <= _mobileMessengerBreakpoint;
                    if (mobileLayout && activeTab == MessengerTab.azoom) {
                      return _buildMobileAzoomRoot(
                        dimNativePopup: dimNativePopup,
                      );
                    }
                    if (mobileLayout && !hideAzoomVoiceChrome) {
                      return _buildMobileLayout(
                        activeTab: activeTab,
                        visibleRoom: visibleRoom,
                        dimNativePopup: dimNativePopup,
                      );
                    }
                    final contentWidth = (constraints.maxWidth - _sideNavWidth)
                        .clamp(0.0, double.infinity);
                    final shouldReserveChatPanel =
                        visibleRoom != null || _isChatPanelClosing;
                    final listWidth = shouldReserveChatPanel
                        ? _compactPrimaryPanelWidth.clamp(0.0, contentWidth)
                        : contentWidth;
                    final chatWidth = (contentWidth - listWidth).clamp(
                      0.0,
                      double.infinity,
                    );

                    return Stack(
                      children: [
                        fullPageTab
                            ? Row(
                                children: [
                                  if (!hideAzoomVoiceChrome)
                                    MessengerSideNav(activeTab: activeTab),
                                  Expanded(
                                    child: _buildPrimaryPanel(activeTab),
                                  ),
                                  _SlidingChatPanel(
                                    room: shouldReserveChatPanel
                                        ? visibleRoom
                                        : null,
                                    width: chatWidth,
                                    visible: false,
                                    onClose: () => _requestCloseChatPanel(),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  MessengerSideNav(activeTab: activeTab),
                                  SizedBox(
                                    width: listWidth,
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: _buildPrimaryPanel(activeTab),
                                        ),
                                        const BottomBanner(),
                                      ],
                                    ),
                                  ),
                                  _SlidingChatPanel(
                                    room: shouldReserveChatPanel
                                        ? visibleRoom
                                        : null,
                                    width: chatWidth,
                                    visible: true,
                                    onClose: () => _requestCloseChatPanel(),
                                  ),
                                ],
                              ),
                        if (keepHiddenAzoomPage)
                          Positioned.fill(
                            child: Offstage(
                              offstage: true,
                              child: TickerMode(
                                enabled: false,
                                child: _buildAzoomPage(),
                              ),
                            ),
                          ),
                        if (dimNativePopup)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ColoredBox(
                                color: Colors.black.withValues(alpha: 0.32),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          if (_isAppSetupLoading)
            _AppSetupOverlay(
              completed: _appSetupCompleted,
              total: _appSetupTotal,
            ),
        ],
      ),
    );
  }

  Widget _buildPrimaryPanel(MessengerTab activeTab) {
    final activeCompany = ref.watch(activeCompanyProvider);
    return switch (activeTab) {
      MessengerTab.friends => const FriendsPanel(),
      MessengerTab.chats => const ChatsPanel(),
      MessengerTab.notifications => const NotificationCenterPanel(),
      MessengerTab.calendar => CalendarPage(
        onOpenChatRoom: _openCalendarChatRoom,
        onOpenAzoomMeeting: _openCalendarAzoomMeeting,
      ),
      MessengerTab.azoom => _buildAzoomPage(),
      MessengerTab.avaAi => AvaAiPage(
        key: ValueKey('ava-ai-${activeCompany ?? ''}'),
      ),
      MessengerTab.avaStock => const AvaStockPage(),
      MessengerTab.more => const MorePanel(),
    };
  }

  Widget _buildAzoomPage() {
    return AzoomPage(
      key: _azoomPageKey,
      currentUser: ref.watch(currentUserProfileProvider),
      mobileActiveTab: ref.watch(activeMessengerTabProvider),
      onMobileTabSelected: (tab) => _selectTab(ref, tab),
    );
  }

  Widget _buildMobileAzoomRoot({required bool dimNativePopup}) {
    return Stack(
      children: [
        Positioned.fill(child: _buildAzoomPage()),
        if (dimNativePopup)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.32)),
            ),
          ),
      ],
    );
  }

  Widget _buildMobileLayout({
    required MessengerTab activeTab,
    required ChatRoom? visibleRoom,
    required bool dimNativePopup,
  }) {
    final showChatRoom = visibleRoom != null;
    final showingAzoom = activeTab == MessengerTab.azoom && !showChatRoom;
    final hideMobileBottomNav =
        activeTab == MessengerTab.avaStock &&
        ref.watch(avaStockImmersiveMobileNavProvider);
    final primaryPanel = showingAzoom
        ? const ColoredBox(
            key: ValueKey('mobile-primary-azoom-shell'),
            color: Color(0xFF111214),
          )
        : _buildPrimaryPanel(activeTab);
    final mobileContent = showChatRoom
        ? ChatRoomPanel(
            key: ValueKey('mobile-chat-panel-${visibleRoom.id}'),
            room: visibleRoom,
            onClose: () => _requestCloseChatPanel(clearMobileFocus: true),
            mobileLayout: true,
          )
        : activeTab == MessengerTab.azoom || activeTab == MessengerTab.avaStock
        ? KeyedSubtree(
            key: ValueKey('mobile-primary-${activeTab.name}'),
            child: primaryPanel,
          )
        : _MobileStatusInset(
            key: ValueKey('mobile-primary-${activeTab.name}'),
            color: _mobileStatusBackground(activeTab),
            overlayStyle: _mobileOverlayStyle(activeTab),
            child: primaryPanel,
          );
    final azoomPage = _buildAzoomPage();
    return PopScope(
      canPop: !showChatRoom,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && showChatRoom) {
          _requestCloseChatPanel(clearMobileFocus: true);
        }
      },
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  reverseDuration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final keyValue = child.key is ValueKey
                        ? (child.key! as ValueKey).value.toString()
                        : '';
                    final shouldSlideIn =
                        keyValue.startsWith('mobile-chat-panel-') ||
                        keyValue == 'mobile-primary-azoom';
                    if (!shouldSlideIn) {
                      return FadeTransition(opacity: animation, child: child);
                    }
                    final slide = Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(animation);
                    return SlideTransition(position: slide, child: child);
                  },
                  child: mobileContent,
                ),
              ),
              if (!showChatRoom &&
                  activeTab != MessengerTab.azoom &&
                  !hideMobileBottomNav)
                _MobileBottomNav(activeTab: activeTab),
            ],
          ),
          Positioned.fill(
            child: showingAzoom
                ? azoomPage
                : Offstage(
                    offstage: true,
                    child: TickerMode(enabled: false, child: azoomPage),
                  ),
          ),
          if (dimNativePopup)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.32)),
              ),
            ),
        ],
      ),
    );
  }

  Color _mobileStatusBackground(MessengerTab activeTab) {
    return switch (activeTab) {
      MessengerTab.avaAi => const Color(0xFFE9F0F5),
      MessengerTab.calendar => const Color(0xFFF6F8FC),
      MessengerTab.avaStock => const Color(0xFFF6F8FC),
      MessengerTab.more =>
        _mobileCanOpenAdminPanel(ref.watch(currentUserProfileProvider).role)
            ? const Color(0xFF4663CF)
            : Colors.white,
      _ => Colors.white,
    };
  }

  SystemUiOverlayStyle _mobileOverlayStyle(MessengerTab activeTab) {
    final lightIcons =
        activeTab == MessengerTab.more &&
        _mobileCanOpenAdminPanel(ref.watch(currentUserProfileProvider).role);
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: lightIcons ? Brightness.light : Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.dark,
      statusBarBrightness: lightIcons ? Brightness.dark : Brightness.light,
    );
  }

  void _selectTab(WidgetRef ref, MessengerTab tab) {
    if (tab != MessengerTab.azoom) {
      ref.read(activeMessengerTabProvider.notifier).setTab(tab);
      return;
    }
    unawaited(_selectAzoomTab(ref));
  }

  Future<void> _selectAzoomTab(WidgetRef ref) async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      ref.read(activeMessengerTabProvider.notifier).setTab(MessengerTab.azoom);
      return;
    }
    final role = session.user.role.toUpperCase();
    if (role == 'ADMIN' || role == 'SUPERUSER') {
      ref.read(activeMessengerTabProvider.notifier).setTab(MessengerTab.azoom);
      return;
    }
    try {
      await ref.read(azoomApiProvider).channels(session.accessToken);
      if (!mounted) {
        return;
      }
      ref.read(activeMessengerTabProvider.notifier).setTab(MessengerTab.azoom);
    } on Object {
      if (mounted) {
        showAvaToast(context, '\uAD8C\uD55C\uC5C6\uC74C');
      }
    }
  }
}

bool _mobileCanOpenAdminPanel(String? role) {
  final normalized = (role ?? '').toUpperCase();
  return normalized == 'ADMIN' || normalized == 'SUPERUSER';
}

class _AppSetupOverlay extends StatelessWidget {
  const _AppSetupOverlay({required this.completed, required this.total});

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      key: const ValueKey('app-setup-overlay'),
      child: AbsorbPointer(
        child: ColoredBox(
          color: const Color(0xEEF6FAFE),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 58,
                  child: CircularProgressIndicator(
                    strokeWidth: 5,
                    semanticsValue: total > 0 ? '$completed/$total' : null,
                    color: const Color(0xFF2F80ED),
                    backgroundColor: const Color(0xFFD8E8F7),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '앱 설정중. . .',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF263B4E),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
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

class _MobileStatusInset extends StatelessWidget {
  const _MobileStatusInset({
    super.key,
    required this.color,
    required this.overlayStyle,
    required this.child,
  });

  final Color color;
  final SystemUiOverlayStyle overlayStyle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: ColoredBox(
        color: color,
        child: Column(
          children: [
            SizedBox(height: topInset),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _SlidingChatPanel extends StatelessWidget {
  const _SlidingChatPanel({
    required this.room,
    required this.width,
    required this.visible,
    required this.onClose,
  });

  final ChatRoom? room;
  final double width;
  final bool visible;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final room = this.room;
    if (room == null) {
      return const SizedBox.shrink();
    }

    final panelWidth = width.clamp(0.0, double.infinity);
    return SizedBox(
      width: visible ? panelWidth : 0,
      child: Offstage(
        offstage: !visible || panelWidth <= 0,
        child: ClipRect(
          child: SizedBox(
            width: panelWidth,
            child: RepaintBoundary(
              child: ChatRoomPanel(
                key: const ValueKey('desktop-chat-panel-state'),
                room: room,
                onClose: onClose,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileBottomNav extends ConsumerWidget {
  const _MobileBottomNav({required this.activeTab});

  final MessengerTab activeTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quietRoomIds = ref.watch(quietChatRoomsProvider).toSet();
    final unreadCount = ref
        .watch(chatRoomsProvider)
        .fold<int>(
          0,
          (count, room) =>
              quietRoomIds.contains(room.id) ? count : count + room.unreadCount,
        );
    final hasUnreadMention = ref
        .watch(chatRoomsProvider)
        .any((room) => room.hasUnreadMention);
    final hasActiveVoiceNotification = ref
        .watch(azoomVoiceStartNotificationsProvider)
        .any((item) => item.active && !item.checked);

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      key: const ValueKey('mobile-bottom-nav'),
      height: 58 + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFFEDEDED),
        border: Border(top: BorderSide(color: Color(0xFFDADADA))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _MobileBottomNavItem(
            key: const ValueKey('mobile-nav-friends'),
            icon: Icons.person,
            label: '친구',
            isActive: activeTab == MessengerTab.friends,
            onTap: () => _selectTab(context, ref, MessengerTab.friends),
          ),
          _MobileBottomNavItem(
            key: const ValueKey('mobile-nav-chats'),
            icon: Icons.chat_bubble,
            label: '채팅',
            isActive: activeTab == MessengerTab.chats,
            badge: unreadCount > 0 ? '$unreadCount' : null,
            onTap: () => _selectTab(context, ref, MessengerTab.chats),
          ),
          _MobileBottomNavItem(
            key: const ValueKey('mobile-nav-notifications'),
            icon: Icons.notifications,
            label: '알림',
            isActive: activeTab == MessengerTab.notifications,
            showDot: hasUnreadMention || hasActiveVoiceNotification,
            onTap: () => _selectTab(context, ref, MessengerTab.notifications),
          ),
          _MobileBottomNavItem(
            key: const ValueKey('mobile-nav-calendar'),
            icon: Icons.calendar_month,
            label: '캘린더',
            isActive: activeTab == MessengerTab.calendar,
            onTap: () => _selectTab(context, ref, MessengerTab.calendar),
          ),
          _MobileBottomNavItem(
            key: const ValueKey('mobile-nav-azoom'),
            icon: Icons.videocam,
            label: 'AZOOM',
            isActive: activeTab == MessengerTab.azoom,
            onTap: () => _selectTab(context, ref, MessengerTab.azoom),
          ),
          _MobileBottomNavItem(
            key: const ValueKey('mobile-nav-ava-stock'),
            icon: Icons.inventory_2_outlined,
            label: '재고',
            isActive: activeTab == MessengerTab.avaStock,
            onTap: () => _selectTab(context, ref, MessengerTab.avaStock),
          ),
          _MobileBottomNavItem(
            key: const ValueKey('mobile-nav-ai'),
            icon: Icons.auto_awesome,
            label: 'AI',
            isActive: activeTab == MessengerTab.avaAi,
            onTap: () => _selectTab(context, ref, MessengerTab.avaAi),
          ),
          _MobileBottomNavItem(
            key: const ValueKey('mobile-nav-more'),
            icon: Icons.more_horiz,
            label: '더보기',
            isActive: activeTab == MessengerTab.more,
            onTap: () => _selectTab(context, ref, MessengerTab.more),
          ),
        ],
      ),
    );
  }

  void _selectTab(BuildContext context, WidgetRef ref, MessengerTab tab) {
    if (tab != MessengerTab.azoom) {
      ref.read(activeMessengerTabProvider.notifier).setTab(tab);
      return;
    }
    unawaited(_selectAzoomTab(context, ref));
  }

  Future<void> _selectAzoomTab(BuildContext context, WidgetRef ref) async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      ref.read(activeMessengerTabProvider.notifier).setTab(MessengerTab.azoom);
      return;
    }
    final role = session.user.role.toUpperCase();
    if (role == 'ADMIN' || role == 'SUPERUSER') {
      ref.read(activeMessengerTabProvider.notifier).setTab(MessengerTab.azoom);
      return;
    }
    try {
      await ref.read(azoomApiProvider).channels(session.accessToken);
      if (!context.mounted) {
        return;
      }
      ref.read(activeMessengerTabProvider.notifier).setTab(MessengerTab.azoom);
    } on Object {
      if (context.mounted) {
        showAvaToast(context, '\uAD8C\uD55C\uC5C6\uC74C');
      }
    }
  }
}

class _MobileBottomNavItem extends StatelessWidget {
  const _MobileBottomNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.badge,
    this.showDot = false,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final String? badge;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Tooltip(
              message: label,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onTap,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        color: isActive
                            ? Colors.black
                            : const Color(0xFF7A7A7A),
                        size: 21,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isActive
                              ? Colors.black
                              : const Color(0xFF7A7A7A),
                          fontSize: 8.2,
                          fontWeight: isActive
                              ? FontWeight.w800
                              : FontWeight.w600,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (badge != null)
            Positioned(
              top: 4,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4B2B),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          if (badge == null && showDot)
            const Positioned(top: 6, right: 12, child: _MobileRedDot()),
        ],
      ),
    );
  }
}

class _MobileRedDot extends StatelessWidget {
  const _MobileRedDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        color: Color(0xFFFF5A55),
        shape: BoxShape.circle,
      ),
    );
  }
}
