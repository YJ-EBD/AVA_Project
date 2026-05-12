import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mock_messenger_data.dart';
import '../data/chat_api.dart';
import '../data/chat_realtime_client.dart';
import '../domain/messenger_models.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/data/auth_models.dart';
import '../../ai/presentation/ava_ai_page.dart';
import '../../../config/app_config.dart';
import '../../../platform/window_control.dart';
import '../../../shared/ava_toast.dart';
import 'widgets/bottom_banner.dart';
import 'widgets/chat_room_panel.dart';
import 'widgets/chats_panel.dart';
import 'widgets/app_window_title_bar.dart';
import 'widgets/friends_panel.dart';
import 'widgets/messenger_side_nav.dart';
import 'widgets/more_panel.dart';

const double _sideNavWidth = 64;
const double _compactPrimaryPanelWidth = 396;
const String _presenceOnline = '\uC628\uB77C\uC778';
const String _presenceBackground = '\uBC31\uADF8\uB77C\uC6B4\uB4DC';
const String _presenceOffline = '\uC624\uD504\uB77C\uC778';
const Duration _presenceHeartbeatInterval = Duration(seconds: 20);

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

void resetMessengerToCompanyPage(WidgetRef ref) {
  ref.read(activeMessengerTabProvider.notifier).setTab(MessengerTab.friends);
  ref.read(selectedChatRoomProvider.notifier).close();
  ref.read(focusedChatRoomIdProvider.notifier).clear();
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
    return userGroups;
  }

  final grouped = <String, List<PersonProfile>>{};
  for (final user in users) {
    final department = user.department?.trim().isNotEmpty == true
        ? user.department!.trim()
        : '\uBBF8\uC9C0\uC815';
    grouped.putIfAbsent(department, () => []).add(user);
  }

  final titles = grouped.keys.toList()
    ..sort((a, b) {
      const unspecified = '\uBBF8\uC9C0\uC815';
      final aUnspecified = a == unspecified;
      final bUnspecified = b == unspecified;
      if (aUnspecified != bUnspecified) {
        return aUnspecified ? 1 : -1;
      }
      return a.compareTo(b);
    });
  return [
    for (final title in titles)
      UserGroup(title: title, users: grouped[title]!..sort(_compareProfiles)),
  ];
});

final updatedUserProfilesProvider = Provider<List<PersonProfile>>((ref) {
  final users = ref.watch(userProfilesProvider).value ?? const [];
  if (users.isEmpty) {
    return updatedUsers;
  }
  return users.take(5).toList();
});

class UserProfiles extends AsyncNotifier<List<PersonProfile>> {
  @override
  Future<List<PersonProfile>> build() async {
    final session = ref.watch(authControllerProvider).value?.session;
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

  @override
  List<ChatRoom> build() {
    final session = ref.watch(authControllerProvider).value?.session;
    final userKey = _userKey(session);
    if (session == null || session.accessToken.isEmpty || userKey == null) {
      _loadedUserKey = null;
      _hasLoadedRemoteRooms = false;
      _isLoadingRemoteRooms = false;
      return const [];
    }
    if (_loadedUserKey != userKey) {
      _loadedUserKey = userKey;
      _hasLoadedRemoteRooms = false;
      _isLoadingRemoteRooms = false;
      Future<void>.microtask(() => refreshFromServer(force: true));
      return const [];
    }
    return state;
  }

  Future<void> refreshFromServer({bool force = false}) async {
    if (_isLoadingRemoteRooms || (_hasLoadedRemoteRooms && !force)) {
      return;
    }

    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      return;
    }
    final userKey = _userKey(session);
    if (userKey == null) {
      return;
    }

    _isLoadingRemoteRooms = true;
    try {
      final remoteRooms = await ref
          .read(chatApiProvider)
          .rooms(session.accessToken);
      if (_loadedUserKey != userKey) {
        return;
      }
      final visibleRooms = remoteRooms.where(_shouldDisplayRemoteRoom);
      state = _orderRooms([
        for (final room in visibleRooms) _fromRemoteRoom(room),
      ]);
      _hasLoadedRemoteRooms = true;
    } on Object {
      // Keep the mock room list available when the API is unreachable.
    } finally {
      _isLoadingRemoteRooms = false;
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
    state = [
      for (final room in state)
        if (room.id == roomId)
          updatedRoom = room.copyWith(unreadCount: 0)
        else
          room,
    ];
    if (updatedRoom != null) {
      _syncFloating(updatedRoom);
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
    state = _orderRooms([
      for (final room in state)
        if (room.id == roomId)
          room.copyWith(
            isPinned: nextPinned,
            pinnedAt: pinnedAt,
            clearPinnedAt: !nextPinned,
          )
        else
          room,
    ]);
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
      state = _orderRooms([
        for (final room in state)
          if (room.id == roomId)
            room.copyWith(
              isPinned: remoteRoom.pinned,
              pinnedAt: remoteRoom.pinnedAt,
              clearPinnedAt: !remoteRoom.pinned,
            )
          else
            room,
      ]);
    } on Object {
      // Keep the optimistic local state if the API is temporarily unavailable.
    }
  }

  void noticeSet(String roomId, ChatNotice notice) {
    state = [
      for (final room in state)
        if (room.id == roomId) room.copyWith(notice: notice) else room,
    ];
  }

  void messagePosted(
    String roomId,
    String content,
    DateTime? sentAt, {
    ChatRoom? fallbackRoom,
    bool spoiler = false,
  }) {
    final activityAt = sentAt ?? DateTime.now();
    var wasUpdated = false;
    final updatedRooms = [
      for (final room in state)
        if (room.id == roomId)
          room.copyWith(
            preview: content,
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
      updatedRooms.add(
        fallbackRoom.copyWith(
          preview: content,
          previewIsSpoiler: spoiler,
          time: formatChatClockTime(activityAt),
          lastActivityAt: activityAt,
          isDraft: false,
        ),
      );
    }

    state = _orderRooms(updatedRooms);
    for (final room in state) {
      if (room.id == roomId) {
        _syncFloating(room);
        break;
      }
    }
  }

  void upsert(ChatRoom room) {
    state = _orderRooms([
      for (final item in state)
        if (item.id != room.id) item,
      room,
    ]);
    _syncFloating(room);
  }

  void remove(String roomId) {
    state = [
      for (final room in state)
        if (room.id != roomId) room,
    ];
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

    final unreadCount = isOpen
        ? 0
        : (existingRoom?.unreadCount ?? 0) + (incrementUnread ? 1 : 0);
    final merged = room.copyWith(
      unreadCount: unreadCount,
      isPinned: existingRoom?.isPinned ?? room.isPinned,
      pinnedAt: existingRoom?.pinnedAt ?? room.pinnedAt,
      isMuted: existingRoom?.isMuted ?? room.isMuted,
      notice: room.notice ?? existingRoom?.notice,
    );

    state = _orderRooms([
      for (final item in state)
        if (item.id != room.id) item,
      merged,
    ]);
    _syncFloating(merged);
  }

  ChatRoom roomFromRemoteRoom(
    ChatRoomDto room, {
    List<PersonProfile>? members,
  }) {
    return _fromRemoteRoom(room, members: members);
  }

  bool _shouldDisplayRemoteRoom(ChatRoomDto room) {
    if (room.type == 'SELF' && room.lastMessage.trim().isEmpty) {
      return false;
    }
    return true;
  }

  ChatRoom _fromRemoteRoom(ChatRoomDto room, {List<PersonProfile>? members}) {
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
      preview: room.lastMessage,
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
}

int _compareProfiles(PersonProfile a, PersonProfile b) {
  final nameOrder = a.name.compareTo(b.name);
  if (nameOrder != 0) {
    return nameOrder;
  }
  return (a.email ?? '').compareTo(b.email ?? '');
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
    try {
      final basePath =
          Platform.environment['APPDATA'] ??
          Platform.environment['HOME'] ??
          Directory.current.path;
      final directory = Directory('$basePath${Platform.pathSeparator}AVA')
        ..createSync(recursive: true);
      final fileName = base64Url
          .encode(utf8.encode(userKey))
          .replaceAll('=', '');
      return File(
        '${directory.path}${Platform.pathSeparator}chat_folders_$fileName.json',
      );
    } on Object {
      return null;
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
    try {
      final basePath =
          Platform.environment['APPDATA'] ??
          Platform.environment['HOME'] ??
          Directory.current.path;
      final directory = Directory('$basePath${Platform.pathSeparator}AVA')
        ..createSync(recursive: true);
      final fileName = base64Url
          .encode(utf8.encode(userKey))
          .replaceAll('=', '');
      return File(
        '${directory.path}${Platform.pathSeparator}chat_filter_order_$fileName.json',
      );
    } on Object {
      return null;
    }
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
    try {
      final basePath =
          Platform.environment['APPDATA'] ??
          Platform.environment['HOME'] ??
          Directory.current.path;
      final directory = Directory('$basePath${Platform.pathSeparator}AVA')
        ..createSync(recursive: true);
      final fileName = base64Url
          .encode(utf8.encode(userKey))
          .replaceAll('=', '');
      return File(
        '${directory.path}${Platform.pathSeparator}quiet_chat_rooms_$fileName.json',
      );
    } on Object {
      return null;
    }
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
    state =
        ref.read(chatRoomsProvider.notifier).markRead(room.id) ??
        room.copyWith(unreadCount: 0);
  }

  void replaceIfOpen(ChatRoom room) {
    if (state?.id == room.id) {
      state = room.copyWith(unreadCount: 0);
    }
  }

  void close() {
    state = null;
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

class MessengerPage extends ConsumerStatefulWidget {
  const MessengerPage({super.key});

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
  String? _presenceAccessToken;
  String _presenceStatus = _presenceOnline;
  Timer? _presenceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        resetMessengerToCompanyPage(ref);
      }
    });
    WindowControl.setNotificationReplyHandler(_sendNotificationReply);
    WindowControl.setFloatingHandler(_handleFloatingAction);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPresence();
    WindowControl.setNotificationReplyHandler(null);
    WindowControl.setFloatingHandler(null);
    _stopInboxRealtime();
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
      return;
    }
    _setPresenceStatus(nextStatus);
  }

  void _openChatPanel(ChatRoom room) {
    setState(() {
      _visibleChatRoom = room;
      _isChatPanelClosing = false;
    });
  }

  void _requestCloseChatPanel() {
    if (_visibleChatRoom == null || _isChatPanelClosing) {
      return;
    }

    setState(() {
      _isChatPanelClosing = true;
    });

    _closeChatPanelNow();
  }

  void _closeChatPanelNow() {
    WindowControl.compactMessenger();
    ref.read(selectedChatRoomProvider.notifier).close();
    setState(() {
      _visibleChatRoom = null;
      _isChatPanelClosing = false;
    });
  }

  void _clearChatPanel() {
    if (_visibleChatRoom == null && !_isChatPanelClosing) {
      return;
    }

    setState(() {
      _visibleChatRoom = null;
      _isChatPanelClosing = false;
    });
  }

  void _syncInboxRealtime(AuthSession? session) {
    if (session == null || session.accessToken.isEmpty) {
      _stopInboxRealtime();
      return;
    }
    if (_inboxAccessToken == session.accessToken) {
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
      if (refreshProfiles ||
          ref.read(activeMessengerTabProvider) == MessengerTab.friends) {
        ref.invalidate(userProfilesProvider);
      }
    } on Object {
      // Presence is best-effort; messaging should keep working while reconnecting.
    }
  }

  void _stopInboxRealtime() {
    _inboxAccessToken = null;
    _inboxSubscription?.cancel();
    _inboxSubscription = null;
    _inboxClient?.dispose();
    _inboxClient = null;
  }

  Future<void> _handleInboxEvent(
    ChatRealtimeEventDto event,
    AuthSession session,
  ) async {
    if (!mounted || event.room.code.isEmpty) {
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

    final message = event.message;
    final room = ref
        .read(chatRoomsProvider.notifier)
        .roomFromRemoteRoom(event.room);
    final selectedRoom = ref.read(selectedChatRoomProvider);
    final isOpen = selectedRoom?.id == room.id;
    final isMine = message?.senderId == session.user.id;

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

    final displayedRoom = ref
        .read(chatRoomsProvider)
        .firstWhere((item) => item.id == room.id, orElse: () => room);

    if (isOpen ||
        displayedRoom.isMuted ||
        ref.read(quietChatRoomsProvider.notifier).contains(displayedRoom.id) ||
        isMine ||
        message == null ||
        message.silent ||
        message.content.isEmpty ||
        message.systemMessage) {
      return;
    }

    final sender = _notificationSender(displayedRoom, message);
    await WindowControl.showChatNotification(
      roomId: displayedRoom.id,
      senderName: sender.name,
      senderNickname: sender.nickname?.isNotEmpty == true
          ? sender.nickname!
          : sender.name,
      avatarColor: colorToHex(sender.color),
      body: message.content,
    );
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
    ref.listen<AsyncValue<AuthState>>(authControllerProvider, (previous, next) {
      _syncInboxRealtime(next.value?.session);
      _syncPresence(next.value?.session);
      if (next.value?.session != null) {
        ref.read(chatRoomsProvider.notifier).refreshFromServer();
      }
    });

    final authState = ref.watch(authControllerProvider);
    final session = authState.value?.session;
    if (session != null) {
      Future.microtask(() {
        if (!mounted) {
          return;
        }
        _syncInboxRealtime(session);
        _syncPresence(session);
        ref.read(chatRoomsProvider.notifier).refreshFromServer();
      });
    }
    final activeTab = ref.watch(activeMessengerTabProvider);
    final dimNativePopup = ref.watch(nativePopupDimProvider);
    final visibleRoom = _visibleChatRoom;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          const AppWindowTitleBar(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
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
                    activeTab == MessengerTab.avaAi
                        ? Row(
                            children: [
                              MessengerSideNav(activeTab: activeTab),
                              const Expanded(child: AvaAiPage()),
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
                                onClose: _requestCloseChatPanel,
                              ),
                            ],
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
    );
  }

  Widget _buildPrimaryPanel(MessengerTab activeTab) {
    return switch (activeTab) {
      MessengerTab.friends => const FriendsPanel(),
      MessengerTab.chats => const ChatsPanel(),
      MessengerTab.avaAi => const AvaAiPage(),
      MessengerTab.more => const MorePanel(),
    };
  }
}

class _SlidingChatPanel extends StatelessWidget {
  const _SlidingChatPanel({
    required this.room,
    required this.width,
    required this.onClose,
  });

  final ChatRoom? room;
  final double width;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final room = this.room;
    if (room == null || width <= 0) {
      return const SizedBox.shrink();
    }

    return ClipRect(
      child: SizedBox(
        width: width,
        child: ChatRoomPanel(
          key: ValueKey('chat-panel-${room.id}'),
          room: room,
          onClose: onClose,
        ),
      ),
    );
  }
}
