import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../platform/window_control.dart';
import '../../../../shared/ava_toast.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../auth/data/auth_api.dart';
import '../../data/chat_api.dart';
import '../../domain/messenger_models.dart';
import '../messenger_page.dart';
import 'panel_header.dart';
import 'profile_avatar.dart';

Map<String, Object?> _nativeMenuItem(
  String value,
  String label, {
  List<Map<String, Object?>>? children,
  bool checked = false,
}) {
  final item = <String, Object?>{'value': value, 'label': label};
  if (checked) {
    item['checked'] = true;
  }
  if (children != null) {
    item['children'] = children;
  }
  return item;
}

bool _isMobileRuntimeForChats() {
  return Platform.isAndroid ||
      Platform.isIOS ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

Map<String, Object?> _nativeMenuSeparator() => {'separator': true};

class _ChatSearchIntent extends Intent {
  const _ChatSearchIntent();
}

List<ChatRoom> _sortChatRooms(
  List<ChatRoom> rooms,
  ChatSortMode mode,
  List<ChatFolder> folders,
) {
  final indexed = rooms.indexed.toList();
  int latestOrder(ChatRoom a, ChatRoom b) {
    final aTime = a.lastActivityAt;
    final bTime = b.lastActivityAt;
    if (aTime != null && bTime != null) {
      final result = bTime.compareTo(aTime);
      if (result != 0) {
        return result;
      }
    } else if (aTime != null) {
      return -1;
    } else if (bTime != null) {
      return 1;
    }
    return a.title.compareTo(b.title);
  }

  ChatFolder? favoriteFolder;
  for (final folder in folders) {
    if (folder.isFavorite) {
      favoriteFolder = folder;
      break;
    }
  }
  final favoriteRank = <String, int>{};
  if (favoriteFolder != null) {
    for (final entry in favoriteFolder.roomIds.reversed.indexed) {
      favoriteRank[entry.$2] = entry.$1;
    }
  }

  indexed.sort((a, b) {
    if (a.$2.isPinned != b.$2.isPinned) {
      return a.$2.isPinned ? -1 : 1;
    }
    if (a.$2.isPinned && b.$2.isPinned) {
      final aPinnedAt = a.$2.pinnedAt;
      final bPinnedAt = b.$2.pinnedAt;
      if (aPinnedAt != null && bPinnedAt != null) {
        final result = bPinnedAt.compareTo(aPinnedAt);
        if (result != 0) {
          return result;
        }
      } else if (aPinnedAt != null) {
        return -1;
      } else if (bPinnedAt != null) {
        return 1;
      }
      return a.$1.compareTo(b.$1);
    }
    switch (mode) {
      case ChatSortMode.latest:
        return latestOrder(a.$2, b.$2);
      case ChatSortMode.unread:
        final aUnread = a.$2.unreadCount > 0;
        final bUnread = b.$2.unreadCount > 0;
        if (aUnread != bUnread) {
          return aUnread ? -1 : 1;
        }
        return latestOrder(a.$2, b.$2);
      case ChatSortMode.favorite:
        final aRank = favoriteRank[a.$2.id];
        final bRank = favoriteRank[b.$2.id];
        if (aRank != null && bRank != null) {
          return aRank.compareTo(bRank);
        }
        if (aRank != null) {
          return -1;
        }
        if (bRank != null) {
          return 1;
        }
        return latestOrder(a.$2, b.$2);
    }
  });
  return [for (final item in indexed) item.$2];
}

String _roomAvatarColor(ChatRoom room) {
  final color = room.members.isEmpty
      ? const Color(0xFFA6C6EE)
      : room.members.first.color;
  return colorToHex(color);
}

String _roomAvatarImageUrl(ChatRoom room) {
  final roomImageUrl = room.avatarImageUrl?.trim() ?? '';
  if (roomImageUrl.isNotEmpty) {
    return roomImageUrl;
  }
  if (room.members.isEmpty) {
    return '';
  }
  return room.members.first.imageUrl?.trim() ?? '';
}

List<Map<String, Object?>> _roomAvatarParts(ChatRoom room) {
  return [
    for (final member in room.members.take(4))
      {
        'color': colorToHex(member.color),
        'imageUrl': member.imageUrl?.trim() ?? '',
      },
  ];
}

List<Map<String, Object?>> _newChatUserPayload(List<PersonProfile> users) {
  final sortedUsers = [...users]
    ..sort((a, b) {
      final nameOrder = a.name.compareTo(b.name);
      if (nameOrder != 0) {
        return nameOrder;
      }
      return (a.email ?? '').compareTo(b.email ?? '');
    });
  return [
    for (final user in sortedUsers)
      if (user.id?.isNotEmpty == true)
        {
          'id': user.id,
          'name': user.name,
          'nickname': user.nickname ?? '',
          'email': user.email ?? '',
          'avatarColor': colorToHex(user.color),
          'avatarImageUrl': user.imageUrl?.trim() ?? '',
        },
  ];
}

class _ChatsHeader extends ConsumerStatefulWidget {
  const _ChatsHeader({
    required this.onMarkAllRead,
    required this.onManageFolders,
    required this.onLeaveMany,
    required this.onSearch,
    required this.onOpenChat,
    required this.onNewChat,
    required this.mobileLayout,
  });

  final Future<void> Function() onMarkAllRead;
  final Future<void> Function() onManageFolders;
  final Future<void> Function() onLeaveMany;
  final VoidCallback onSearch;
  final VoidCallback onOpenChat;
  final VoidCallback onNewChat;
  final bool mobileLayout;

  @override
  ConsumerState<_ChatsHeader> createState() => _ChatsHeaderState();
}

class _ChatsHeaderState extends ConsumerState<_ChatsHeader> {
  final GlobalKey _menuAnchorKey = GlobalKey();
  bool _isMenuOpen = false;

  Future<void> _showSortMenu() async {
    if (_isMenuOpen) {
      return;
    }
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final anchorBox =
        _menuAnchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (anchorBox == null) {
      return;
    }
    final topLeft = anchorBox.localToGlobal(Offset.zero, ancestor: overlay);
    final sortMode = ref.read(chatSortModeProvider);
    setState(() => _isMenuOpen = true);
    String? result;
    try {
      if (Platform.isWindows) {
        result = await WindowControl.showNativeMenu(
          items: [
            _nativeMenuItem(
              'latest',
              '최신 메시지 순',
              checked: sortMode == ChatSortMode.latest,
            ),
            _nativeMenuItem(
              'unread',
              '안 읽은 메시지 순',
              checked: sortMode == ChatSortMode.unread,
            ),
            _nativeMenuItem(
              'favorite',
              '즐겨찾기 순',
              checked: sortMode == ChatSortMode.favorite,
            ),
            _nativeMenuSeparator(),
            _nativeMenuItem('read-all', '모두 읽음 처리'),
            _nativeMenuSeparator(),
            _nativeMenuItem('folders', '채팅방 폴더 관리'),
            _nativeMenuItem('leave-many', '여러 채팅방 나가기'),
          ],
          x: topLeft.dx,
          y: topLeft.dy + anchorBox.size.height + 7,
        );
      } else {
        result = await showMenu<String>(
          context: context,
          position: RelativeRect.fromRect(
            Rect.fromLTWH(
              topLeft.dx,
              topLeft.dy + anchorBox.size.height + 7,
              0,
              0,
            ),
            Offset.zero & overlay.size,
          ),
          items: [
            PopupMenuItem(
              value: 'latest',
              child: Text(
                '${sortMode == ChatSortMode.latest ? '✓ ' : ''}최신 메시지 순',
              ),
            ),
            PopupMenuItem(
              value: 'unread',
              child: Text(
                '${sortMode == ChatSortMode.unread ? '✓ ' : ''}안 읽은 메시지 순',
              ),
            ),
            PopupMenuItem(
              value: 'favorite',
              child: Text(
                '${sortMode == ChatSortMode.favorite ? '✓ ' : ''}즐겨찾기 순',
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'read-all', child: Text('모두 읽음 처리')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'folders', child: Text('채팅방 폴더 관리')),
            const PopupMenuItem(value: 'leave-many', child: Text('여러 채팅방 나가기')),
          ],
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isMenuOpen = false);
      }
    }
    if (!mounted || result == null) {
      return;
    }
    switch (result) {
      case 'latest':
        ref.read(chatSortModeProvider.notifier).setMode(ChatSortMode.latest);
      case 'unread':
        ref.read(chatSortModeProvider.notifier).setMode(ChatSortMode.unread);
      case 'favorite':
        ref.read(chatSortModeProvider.notifier).setMode(ChatSortMode.favorite);
      case 'read-all':
        await widget.onMarkAllRead();
      case 'folders':
        await widget.onManageFolders();
      case 'leave-many':
        await widget.onLeaveMany();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 28, 16, 8),
      child: Row(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: _menuAnchorKey,
              behavior: HitTestBehavior.opaque,
              onTap: _showSortMenu,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '채팅',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isMenuOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    size: 18,
                    color: Colors.black,
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          HeaderIconButton(
            icon: Icons.search,
            tooltip: '검색 Ctrl+F',
            onPressed: widget.onSearch,
          ),
          HeaderIconButton(
            icon: Icons.forum_outlined,
            tooltip: '오픈채팅',
            onPressed: widget.onOpenChat,
          ),
          HeaderIconButton(
            icon: Icons.add_comment_outlined,
            tooltip: '새 채팅',
            onPressed: widget.onNewChat,
          ),
        ],
      ),
    );
  }
}

class _MobileChatsHeader extends ConsumerStatefulWidget {
  const _MobileChatsHeader({
    required this.onMarkAllRead,
    required this.onManageFolders,
    required this.onLeaveMany,
    required this.onSearch,
    required this.onNewChat,
  });

  final Future<void> Function() onMarkAllRead;
  final Future<void> Function() onManageFolders;
  final Future<void> Function() onLeaveMany;
  final VoidCallback onSearch;
  final VoidCallback onNewChat;

  @override
  ConsumerState<_MobileChatsHeader> createState() => _MobileChatsHeaderState();
}

class _MobileChatsHeaderState extends ConsumerState<_MobileChatsHeader> {
  final GlobalKey _settingsKey = GlobalKey();
  bool _isMenuOpen = false;

  Future<void> _showSettingsMenu() async {
    if (_isMenuOpen) {
      return;
    }
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final anchorBox =
        _settingsKey.currentContext?.findRenderObject() as RenderBox?;
    if (anchorBox == null) {
      return;
    }
    final topLeft = anchorBox.localToGlobal(Offset.zero, ancestor: overlay);
    final sortMode = ref.read(chatSortModeProvider);
    setState(() => _isMenuOpen = true);
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(topLeft.dx, topLeft.dy + anchorBox.size.height + 7, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'latest',
          child: Text(
            '${sortMode == ChatSortMode.latest ? '\u2713 ' : ''}\uCD5C\uC2E0\uC21C',
          ),
        ),
        PopupMenuItem(
          value: 'unread',
          child: Text(
            '${sortMode == ChatSortMode.unread ? '\u2713 ' : ''}\uC548\uC77D\uC740 \uCC44\uD305',
          ),
        ),
        PopupMenuItem(
          value: 'favorite',
          child: Text(
            '${sortMode == ChatSortMode.favorite ? '\u2713 ' : ''}\uC990\uACA8\uCC3E\uAE30',
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'read-all',
          child: Text('\uBAA8\uB450 \uC77D\uC74C \uCC98\uB9AC'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'folders',
          child: Text('\uCC44\uD305\uBC29 \uD3F4\uB354 \uAD00\uB9AC'),
        ),
        const PopupMenuItem(
          value: 'leave-many',
          child: Text('\uC5EC\uB7EC \uCC44\uD305\uBC29 \uB098\uAC00\uAE30'),
        ),
      ],
    );
    if (mounted) {
      setState(() => _isMenuOpen = false);
    }
    if (!mounted || result == null) {
      return;
    }
    switch (result) {
      case 'latest':
        ref.read(chatSortModeProvider.notifier).setMode(ChatSortMode.latest);
      case 'unread':
        ref.read(chatSortModeProvider.notifier).setMode(ChatSortMode.unread);
      case 'favorite':
        ref.read(chatSortModeProvider.notifier).setMode(ChatSortMode.favorite);
      case 'read-all':
        await widget.onMarkAllRead();
      case 'folders':
        await widget.onManageFolders();
      case 'leave-many':
        await widget.onLeaveMany();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 28, 16, 8),
      child: Row(
        children: [
          const Text(
            '\uCC44\uD305',
            style: TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const Spacer(),
          HeaderIconButton(
            icon: Icons.search,
            tooltip: '\uAC80\uC0C9',
            onPressed: widget.onSearch,
          ),
          HeaderIconButton(
            icon: Icons.add_comment_outlined,
            tooltip: '\uC0C8 \uCC44\uD305',
            onPressed: widget.onNewChat,
          ),
          HeaderIconButton(
            key: _settingsKey,
            icon: Icons.settings_outlined,
            tooltip: '\uCC44\uD305 \uC124\uC815',
            onPressed: _showSettingsMenu,
          ),
        ],
      ),
    );
  }
}

class _ChatSearchBar extends StatelessWidget {
  const _ChatSearchBar({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: focusNode,
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: focused ? Colors.white : const Color(0xFFF3F3F3),
                    border: Border.all(
                      color: focused
                          ? const Color(0xFF7E7E7E)
                          : const Color(0xFFF3F3F3),
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.search,
                        size: 18,
                        color: Color(0xFF9A9A9A),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          onChanged: onChanged,
                          decoration: const InputDecoration(
                            hintText:
                                '\uCC44\uD305\uBC29, \uCC38\uC5EC\uC790 \uAC80\uC0C9',
                            hintStyle: TextStyle(
                              color: Color(0xFF8B8B8B),
                              fontSize: 13,
                              height: 1.1,
                            ),
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.only(bottom: 2),
                          ),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                            height: 1.1,
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 18,
                        color: const Color(0xFFD7D7D7),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        '\uD1B5\uD569\uAC80\uC0C9',
                        style: TextStyle(
                          color: Color(0xFF8B8B8B),
                          fontSize: 12,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 13),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 9),
              SizedBox.square(
                dimension: 30,
                child: IconButton(
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  splashRadius: 15,
                  icon: const Icon(Icons.close, size: 22, color: Colors.black),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MobileNewChatResult {
  const _MobileNewChatResult({required this.userIds, required this.title});

  final List<String> userIds;
  final String title;
}

class _MobileNewChatDialog extends StatefulWidget {
  const _MobileNewChatDialog({required this.users});

  final List<PersonProfile> users;

  @override
  State<_MobileNewChatDialog> createState() => _MobileNewChatDialogState();
}

class _MobileNewChatDialogState extends State<_MobileNewChatDialog> {
  final TextEditingController _titleController = TextEditingController();
  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '\uC0C8 \uCC44\uD305',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  hintText: '\uCC44\uD305\uBC29 \uC774\uB984(\uC120\uD0DD)',
                  filled: true,
                  fillColor: const Color(0xFFF4F6F8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: widget.users.length,
                itemBuilder: (context, index) {
                  final user = widget.users[index];
                  final id = user.id ?? '';
                  final selected = _selectedIds.contains(id);
                  return CheckboxListTile(
                    value: selected,
                    onChanged: id.isEmpty
                        ? null
                        : (value) {
                            setState(() {
                              if (value == true) {
                                _selectedIds.add(id);
                              } else {
                                _selectedIds.remove(id);
                              }
                            });
                          },
                    secondary: ProfileAvatar(profile: user, size: 36),
                    title: Text(
                      user.name,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(user.email ?? ''),
                    controlAffinity: ListTileControlAffinity.trailing,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(
                          _MobileNewChatResult(
                            userIds: _selectedIds.toList(),
                            title: _titleController.text.trim(),
                          ),
                        ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4663CF),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('\uB9CC\uB4E4\uAE30'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatsPanel extends ConsumerStatefulWidget {
  const ChatsPanel({super.key});

  @override
  ConsumerState<ChatsPanel> createState() => _ChatsPanelState();
}

class _ChatsPanelState extends ConsumerState<ChatsPanel> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.keyF &&
        (keyboard.isControlPressed || keyboard.isMetaPressed)) {
      _openSearch();
      return true;
    }
    return false;
  }

  void _openSearch() {
    setState(() => _isSearching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _closeSearch() {
    setState(() {
      _isSearching = false;
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeFolderId = ref.watch(activeChatFolderProvider);
    final folders = ref.watch(chatFoldersProvider);
    final filterOrder = ref.watch(chatFilterOrderProvider);
    final quietRoomIds = ref.watch(quietChatRoomsProvider);
    final sortMode = ref.watch(chatSortModeProvider);
    final allRooms = ref.watch(chatRoomsProvider);
    final quietRoomIdSet = quietRoomIds.toSet();
    final quietRooms = [
      for (final room in allRooms)
        if (quietRoomIdSet.contains(room.id)) room,
    ];
    final countableRooms = [
      for (final room in allRooms)
        if (!quietRoomIdSet.contains(room.id)) room,
    ];
    ChatFolder? activeFolder;
    for (final folder in folders) {
      if (folder.id == activeFolderId) {
        activeFolder = folder;
        break;
      }
    }
    final List<ChatRoom> rooms;
    if (activeFolderId == unreadChatFolderId) {
      rooms = _sortChatRooms(
        allRooms
            .where(
              (room) =>
                  room.unreadCount > 0 && !quietRoomIdSet.contains(room.id),
            )
            .toList(),
        sortMode,
        folders,
      );
    } else {
      final folder = activeFolder;
      rooms = _sortChatRooms(
        (folder == null
                ? allRooms
                : allRooms.where((room) => folder.roomIds.contains(room.id)))
            .where((room) => !quietRoomIdSet.contains(room.id))
            .toList(),
        sortMode,
        folders,
      );
    }
    final searchQuery = _searchController.text.trim();
    final searchRooms = _filterRooms(
      _sortChatRooms(
        allRooms.where((room) => !quietRoomIdSet.contains(room.id)).toList(),
        sortMode,
        folders,
      ),
      searchQuery,
    );
    final displayedRooms = _isSearching ? searchRooms : rooms;
    final showQuietTile =
        !_isSearching && activeFolderId == null && quietRooms.isNotEmpty;
    final mobileLayout =
        _isMobileRuntimeForChats() && MediaQuery.sizeOf(context).width <= 720;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
            const _ChatSearchIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ChatSearchIntent: CallbackAction<_ChatSearchIntent>(
            onInvoke: (_) {
              _openSearch();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Container(
            color: Colors.white,
            child: Column(
              children: [
                if (mobileLayout)
                  _MobileChatsHeader(
                    onSearch: _openSearch,
                    onNewChat: () => _showNewChatPopup(context, ref),
                    onMarkAllRead: () => _markAllRoomsRead(context, ref),
                    onManageFolders: () =>
                        _showFolderManageDialog(context, ref),
                    onLeaveMany: () => _showMultiLeaveRoomsPopup(context, ref),
                  )
                else
                  _ChatsHeader(
                    mobileLayout: false,
                    onSearch: _openSearch,
                    onOpenChat: () => _showBlackToast(
                      context,
                      '\uBBF8 \uAD6C\uD604 \uAE30\uB2A5',
                    ),
                    onNewChat: () => _showNewChatPopup(context, ref),
                    onMarkAllRead: () => _markAllRoomsRead(context, ref),
                    onManageFolders: () =>
                        _showFolderManageDialog(context, ref),
                    onLeaveMany: () => _showMultiLeaveRoomsPopup(context, ref),
                  ),
                if (_isSearching)
                  _ChatSearchBar(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: (_) => setState(() {}),
                    onClose: _closeSearch,
                  ),
                _ChatFolderFilters(
                  folders: folders,
                  filterOrder: filterOrder,
                  rooms: countableRooms,
                  activeFolderId: activeFolderId,
                  unreadCount: countableRooms.fold<int>(
                    0,
                    (count, room) => count + room.unreadCount,
                  ),
                  onSelectFolder: (folderId) => ref
                      .read(activeChatFolderProvider.notifier)
                      .select(folderId),
                  onManageFolders: () => _showFolderManageDialog(context, ref),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 4, bottom: 16),
                    itemCount:
                        displayedRooms.length + (showQuietTile ? 1 : 0) + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return const _RotatingChatBanner();
                      }
                      final roomIndexBase = index - 1;
                      if (showQuietTile && roomIndexBase == 0) {
                        return _QuietChatRoomsTile(
                          rooms: quietRooms,
                          onDoubleTap: () =>
                              _showQuietRoomsDialog(context, ref, quietRooms),
                          onContextMenu: (position) =>
                              _showQuietRoomsContextMenu(
                                context,
                                ref,
                                quietRooms,
                                position,
                              ),
                        );
                      }
                      final room =
                          displayedRooms[roomIndexBase -
                              (showQuietTile ? 1 : 0)];
                      return _ChatRoomTileSelection(
                        key: ValueKey('chat-room-${room.id}'),
                        room: room,
                        mobileLayout: mobileLayout,
                        onTap: () {
                          ref
                              .read(focusedChatRoomIdProvider.notifier)
                              .focus(room);
                          if (mobileLayout) {
                            _openRoom(ref, room);
                          } else if (ref.read(selectedChatRoomProvider) !=
                              null) {
                            _openRoom(ref, room);
                          }
                        },
                        onDoubleTap: mobileLayout
                            ? () {}
                            : () => _openRoom(ref, room),
                        onContextMenu: (position) =>
                            _showRoomContextMenu(context, ref, room, position),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<ChatRoom> _filterRooms(List<ChatRoom> rooms, String query) {
    if (query.isEmpty) {
      return rooms;
    }
    final normalized = query.toLowerCase();
    return [
      for (final room in rooms)
        if (_roomSearchText(room).contains(normalized)) room,
    ];
  }

  String _roomSearchText(ChatRoom room) {
    return room.title.toLowerCase();
  }

  void _openRoom(WidgetRef ref, ChatRoom room) {
    ref.read(activeMessengerTabProvider.notifier).setTab(MessengerTab.chats);
    ref.read(focusedChatRoomIdProvider.notifier).focus(room);

    if (ref.read(selectedChatRoomProvider) != null) {
      ref.read(selectedChatRoomProvider.notifier).open(room);
      return;
    }

    ref.read(selectedChatRoomProvider.notifier).open(room);
    WindowControl.expandMessenger();
  }

  Future<void> _markAllRoomsRead(BuildContext context, WidgetRef ref) async {
    final rooms = ref.read(chatRoomsProvider);
    for (final room in rooms) {
      ref.read(chatRoomsProvider.notifier).markRead(room.id);
    }

    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      return;
    }
    for (final room in rooms) {
      if (room.isDraft || room.unreadCount <= 0) {
        continue;
      }
      try {
        await ref
            .read(chatApiProvider)
            .markRead(accessToken: session.accessToken, roomCode: room.id);
      } on Object catch (error) {
        if (!context.mounted) {
          return;
        }
        showAvaToast(context, authErrorMessage(error));
        return;
      }
    }
  }

  Future<void> _showMultiLeaveRoomsPopup(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final quietRoomIds = ref.read(quietChatRoomsProvider).toSet();
    final rooms = [
      for (final room in ref.read(chatRoomsProvider))
        if (!quietRoomIds.contains(room.id)) room,
    ];
    if (rooms.isEmpty) {
      return;
    }

    if (!Platform.isWindows) {
      return;
    }

    ref.read(nativePopupDimProvider.notifier).show();
    WindowControl.setMultiLeaveRoomsPopupHandler((action, arguments) async {
      if (action == 'closed') {
        ref.read(nativePopupDimProvider.notifier).hide();
        WindowControl.setMultiLeaveRoomsPopupHandler(null);
        return;
      }
      if (action == 'leaveRooms') {
        final roomIds = (arguments['roomIds'] as List? ?? const [])
            .whereType<String>()
            .toList();
        for (final roomId in roomIds) {
          final room = _findRoomById(ref, roomId);
          if (room == null) {
            continue;
          }
          await _leaveRoomImmediately(context, ref, room);
        }
        ref.read(nativePopupDimProvider.notifier).hide();
        WindowControl.setMultiLeaveRoomsPopupHandler(null);
      }
    });
    await WindowControl.showMultiLeaveRoomsPopup(
      rooms: _roomPickerPayload(rooms),
    );
  }

  Future<void> _showNewChatPopup(BuildContext context, WidgetRef ref) async {
    var users = ref.read(userProfilesProvider).value ?? const <PersonProfile>[];
    if (users.isEmpty) {
      try {
        users = await ref.read(userProfilesProvider.future);
      } on Object {
        users = const <PersonProfile>[];
      }
    }
    final currentUser = ref.read(authControllerProvider).value?.session?.user;
    final currentUserId = currentUser?.id;
    final currentEmail = currentUser?.email.toLowerCase();
    final selectableUsers = [
      for (final user in users)
        if ((user.id == null || user.id != currentUserId) &&
            (user.email == null ||
                currentEmail == null ||
                user.email!.toLowerCase() != currentEmail))
          user,
    ];
    if (selectableUsers.isEmpty) {
      if (context.mounted) {
        _showBlackToast(
          context,
          '\uB300\uD654\uC0C1\uB300\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4',
        );
      }
      return;
    }

    if (!Platform.isWindows) {
      if (!context.mounted) {
        return;
      }
      final result = await showDialog<_MobileNewChatResult>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.48),
        builder: (_) => _MobileNewChatDialog(users: selectableUsers),
      );
      if (result == null || result.userIds.isEmpty || !context.mounted) {
        return;
      }
      final session = ref.read(authControllerProvider).value?.session;
      if (session == null || session.accessToken.isEmpty) {
        return;
      }
      try {
        final remoteRoom = await ref
            .read(chatApiProvider)
            .startGroupRoom(
              accessToken: session.accessToken,
              targetUserIds: result.userIds,
              title: result.title,
            );
        final room = ref
            .read(chatRoomsProvider.notifier)
            .roomFromRemoteRoom(remoteRoom);
        ref.read(chatRoomsProvider.notifier).upsert(room);
        _openRoom(ref, room);
      } on Object catch (error) {
        if (context.mounted) {
          showAvaToast(context, authErrorMessage(error));
        }
      }
      return;
    }

    var creating = false;
    WindowControl.setNewChatPopupHandler((action, arguments) async {
      if (action == 'closed') {
        WindowControl.setNewChatPopupHandler(null);
        return;
      }
      if (action != 'create' || creating) {
        return;
      }
      creating = true;
      final userIds = (arguments['userIds'] as List? ?? const [])
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toList();
      if (userIds.isEmpty) {
        creating = false;
        return;
      }
      final session = ref.read(authControllerProvider).value?.session;
      if (session == null || session.accessToken.isEmpty) {
        creating = false;
        return;
      }
      try {
        final remoteRoom = await ref
            .read(chatApiProvider)
            .startGroupRoom(
              accessToken: session.accessToken,
              targetUserIds: userIds,
              title: arguments['title'] as String? ?? '',
              avatarImageUrl: arguments['avatarImageUrl'] as String? ?? '',
            );
        final room = ref
            .read(chatRoomsProvider.notifier)
            .roomFromRemoteRoom(remoteRoom);
        ref.read(chatRoomsProvider.notifier).upsert(room);
        _openRoom(ref, room);
        await WindowControl.closeNewChatPopup();
        WindowControl.setNewChatPopupHandler(null);
      } on Object catch (error) {
        creating = false;
        if (!context.mounted) {
          return;
        }
        showAvaToast(context, authErrorMessage(error));
      }
    });

    await WindowControl.showNewChatPopup(
      users: _newChatUserPayload(selectableUsers),
    );
  }

  Future<void> _showRoomContextMenu(
    BuildContext context,
    WidgetRef ref,
    ChatRoom room,
    Offset position,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final activeFolderId = ref.read(activeChatFolderProvider);
    final folders = ref.read(chatFoldersProvider);
    final isInsideUserFolder =
        activeFolderId != null &&
        activeFolderId != unreadChatFolderId &&
        folders.any(
          (folder) =>
              folder.id == activeFolderId && folder.roomIds.contains(room.id),
        );
    Future<void> handleResult(String result) async {
      if (result == 'open') {
        _openRoom(ref, room);
      } else if (result == 'pin') {
        ref.read(chatRoomsProvider.notifier).togglePinned(room.id);
      } else if (result == 'favorite') {
        ref.read(chatFoldersProvider.notifier).toggleFavoriteRoom(room.id);
      } else if (result == 'mute') {
        ref.read(chatRoomsProvider.notifier).toggleMuted(room.id);
      } else if (result == 'read') {
        await _markRoomRead(context, ref, room);
      } else if (result == 'floating') {
        await _showFloating(ref, room);
      } else if (result == 'folder') {
        await _showCreateFolderDialog(context, ref, initialRoomIds: [room.id]);
      } else if (result == 'folder-submenu') {
        return;
      } else if (result.startsWith('folder:')) {
        ref
            .read(chatFoldersProvider.notifier)
            .addRoom(result.substring('folder:'.length), room.id);
      } else if (result == 'folder-remove' && activeFolderId != null) {
        ref
            .read(chatFoldersProvider.notifier)
            .removeRoom(activeFolderId, room.id);
      } else if (result == 'store') {
        ref.read(quietChatRoomsProvider.notifier).add(room.id);
      } else if (result == 'leave') {
        await _leaveRoom(context, ref, room);
      }
    }

    if (Platform.isWindows) {
      final result = await WindowControl.showNativeMenu(
        items: [
          _nativeMenuItem('open', '채팅방 열기'),
          _nativeMenuItem('pin', room.isPinned ? '채팅방 상단 고정 해제' : '채팅방 상단 고정'),
          _nativeMenuItem(
            'favorite',
            ref.read(chatFoldersProvider.notifier).isFavoriteRoom(room.id)
                ? '즐겨찾기 해제'
                : '즐겨찾기 등록',
          ),
          _nativeMenuSeparator(),
          _nativeMenuItem('mute', room.isMuted ? '알림 켜기' : '알림 끄기'),
          _nativeMenuItem('read', '읽음 처리        R'),
          _nativeMenuItem('floating', '플로팅 띄우기'),
          _nativeMenuSeparator(),
          if (!isInsideUserFolder && folders.isNotEmpty)
            _nativeMenuItem(
              'folder-submenu',
              '폴더에 추가',
              children: [
                for (final folder in folders)
                  _nativeMenuItem(
                    'folder:${folder.id}',
                    '${folder.icon} ${folder.name}',
                  ),
              ],
            ),
          if (!isInsideUserFolder) _nativeMenuItem('folder', '새폴더 만들기'),
          if (isInsideUserFolder) _nativeMenuItem('folder-remove', '폴더에서 해제'),
          _nativeMenuItem('store', '조용한 채팅방으로 보관'),
          _nativeMenuItem('leave', '채팅방 나가기'),
        ],
        x: position.dx + 4,
        y: position.dy,
      );
      if (!context.mounted || result == null) {
        return;
      }
      await handleResult(result);
      return;
    }

    if (_isMobileRuntimeForChats() && MediaQuery.sizeOf(context).width <= 720) {
      final result = await _showMobileRoomContextMenu(
        context,
        ref,
        room,
        isInsideUserFolder: isInsideUserFolder,
        hasFolders: folders.isNotEmpty,
      );
      if (!context.mounted || result == null) {
        return;
      }
      await handleResult(result);
      return;
    }

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
      items: [
        const PopupMenuItem(
          value: 'open',
          height: 28,
          padding: EdgeInsets.zero,
          child: _RoomMenuItemContent(label: '채팅방 열기'),
        ),
        PopupMenuItem(
          value: 'pin',
          height: 28,
          padding: EdgeInsets.zero,
          child: _RoomMenuItemContent(
            key: const ValueKey('room-menu-pin'),
            label: room.isPinned ? '채팅방 상단 고정 해제' : '채팅방 상단 고정',
          ),
        ),
        PopupMenuItem(
          value: 'favorite',
          height: 28,
          padding: EdgeInsets.zero,
          child: _RoomMenuItemContent(
            label:
                ref.read(chatFoldersProvider.notifier).isFavoriteRoom(room.id)
                ? '즐겨찾기 해제'
                : '즐겨찾기 등록',
          ),
        ),
        const PopupMenuDivider(height: 10),
        PopupMenuItem(
          value: 'mute',
          height: 28,
          padding: EdgeInsets.zero,
          child: _RoomMenuItemContent(label: room.isMuted ? '알림 켜기' : '알림 끄기'),
        ),
        const PopupMenuItem(
          value: 'read',
          height: 28,
          padding: EdgeInsets.zero,
          child: _RoomMenuItemContent(label: '읽음 처리'),
        ),
        const PopupMenuItem(
          value: 'floating',
          height: 28,
          padding: EdgeInsets.zero,
          child: _RoomMenuItemContent(label: '플로팅 띄우기'),
        ),
        const PopupMenuDivider(height: 10),
        if (!isInsideUserFolder && folders.isNotEmpty)
          PopupMenuItem(
            value: 'folder-submenu',
            height: 28,
            padding: EdgeInsets.zero,
            child: _RoomFolderMenuItemContent(folders: folders),
          ),
        if (!isInsideUserFolder)
          const PopupMenuItem(
            value: 'folder',
            height: 28,
            padding: EdgeInsets.zero,
            child: _RoomMenuItemContent(label: '새폴더 만들기'),
          ),
        if (isInsideUserFolder)
          const PopupMenuItem(
            value: 'folder-remove',
            height: 28,
            padding: EdgeInsets.zero,
            child: _RoomMenuItemContent(
              label: '\uD3F4\uB354\uC5D0\uC11C \uD574\uC81C',
            ),
          ),
        const PopupMenuItem(
          value: 'store',
          height: 28,
          padding: EdgeInsets.zero,
          child: _RoomMenuItemContent(label: '조용한 채팅방으로 보관'),
        ),
        const PopupMenuItem(
          value: 'leave',
          height: 28,
          padding: EdgeInsets.zero,
          child: _RoomMenuItemContent(label: '채팅방 나가기'),
        ),
      ],
    );

    if (!context.mounted || result == null) {
      return;
    }

    await handleResult(result);
  }

  Future<String?> _showMobileRoomContextMenu(
    BuildContext context,
    WidgetRef ref,
    ChatRoom room, {
    required bool isInsideUserFolder,
    required bool hasFolders,
  }) async {
    final favorite = ref
        .read(chatFoldersProvider.notifier)
        .isFavoriteRoom(room.id);
    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.46),
      builder: (context) => _MobileRoomContextMenu(
        title: room.title,
        actions: [
          const _MobileRoomMenuAction(
            value: 'open',
            label: '\uCC44\uD305\uBC29 \uC815\uBCF4 \uC124\uC815',
          ),
          _MobileRoomMenuAction(
            value: 'favorite',
            label: favorite
                ? '\uC990\uACA8\uCC3E\uAE30 \uD574\uC81C'
                : '\uC990\uACA8\uCC3E\uAE30 \uCD94\uAC00',
          ),
          _MobileRoomMenuAction(
            value: 'pin',
            label: room.isPinned
                ? '\uCC44\uD305\uBC29 \uC0C1\uB2E8 \uACE0\uC815 \uD574\uC81C'
                : '\uCC44\uD305\uBC29 \uC0C1\uB2E8 \uACE0\uC815',
          ),
          _MobileRoomMenuAction(
            value: 'mute',
            label: room.isMuted
                ? '\uCC44\uD305\uBC29 \uC54C\uB9BC \uCF1C\uAE30'
                : '\uCC44\uD305\uBC29 \uC54C\uB9BC \uB044\uAE30',
          ),
          const _MobileRoomMenuAction(
            value: 'floating',
            label:
                '\uD648 \uD654\uBA74\uC5D0 \uBC14\uB85C\uAC00\uAE30 \uCD94\uAC00',
          ),
          if (!isInsideUserFolder && hasFolders)
            const _MobileRoomMenuAction(
              value: 'folder-choose',
              label: '\uD3F4\uB354\uC5D0 \uCD94\uAC00',
            ),
          if (!isInsideUserFolder)
            const _MobileRoomMenuAction(
              value: 'folder',
              label: '\uC0C8\uD3F4\uB354 \uB9CC\uB4E4\uAE30',
            ),
          if (isInsideUserFolder)
            const _MobileRoomMenuAction(
              value: 'folder-remove',
              label: '\uD3F4\uB354\uC5D0\uC11C \uD574\uC81C',
            ),
          const _MobileRoomMenuAction(
            value: 'store',
            label:
                '\uC870\uC6A9\uD55C \uCC44\uD305\uBC29\uC73C\uB85C \uBCF4\uAD00',
          ),
          const _MobileRoomMenuAction(
            value: 'leave',
            label: '\uB098\uAC00\uAE30',
          ),
        ],
      ),
    );
    if (!context.mounted || result != 'folder-choose') {
      return result;
    }
    final folderId = await _showMobileFolderChoiceDialog(context, ref);
    return folderId == null ? null : 'folder:$folderId';
  }

  Future<String?> _showMobileFolderChoiceDialog(
    BuildContext context,
    WidgetRef ref,
  ) {
    final folders = ref.read(chatFoldersProvider);
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.46),
      builder: (context) => _MobileRoomContextMenu(
        title: '\uD3F4\uB354\uC5D0 \uCD94\uAC00',
        actions: [
          for (final folder in folders)
            _MobileRoomMenuAction(
              value: folder.id,
              label: '${folder.icon} ${folder.name}',
            ),
        ],
      ),
    );
  }

  Future<void> _markRoomRead(
    BuildContext context,
    WidgetRef ref,
    ChatRoom room,
  ) async {
    ref.read(chatRoomsProvider.notifier).markRead(room.id);
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
    } on Object catch (error) {
      if (!context.mounted) {
        return;
      }
      showAvaToast(context, authErrorMessage(error));
    }
  }

  Future<void> _showFloating(WidgetRef ref, ChatRoom room) async {
    if (room.isDraft) {
      return;
    }
    final avatarColor = room.members.isEmpty
        ? const Color(0xFFA6C6EE)
        : room.members.first.color;
    await WindowControl.showChatFloating(
      roomId: room.id,
      title: room.title,
      avatarColor: colorToHex(avatarColor),
      isGroup: !room.isDirectChat && !room.isSelfChat,
      isMuted: room.isMuted,
      unreadCount: room.unreadCount,
    );
  }

  Future<void> _showQuietRoomsContextMenu(
    BuildContext context,
    WidgetRef ref,
    List<ChatRoom> rooms,
    Offset position,
  ) async {
    Future<void> handleResult(String result) async {
      if (result == 'open') {
        await _showQuietRoomsDialog(context, ref, rooms);
      } else if (result == 'read') {
        await _markQuietRoomsRead(context, ref, rooms);
      } else if (result == 'hide' || result == 'clear') {
        ref.read(quietChatRoomsProvider.notifier).clear();
      }
    }

    if (Platform.isWindows) {
      final result = await WindowControl.showNativeMenu(
        items: [
          _nativeMenuItem('open', '조용한 채팅방 열기'),
          _nativeMenuSeparator(),
          _nativeMenuItem('read', '읽음 처리'),
          _nativeMenuItem('hide', '조용한 채팅방 숨김'),
          _nativeMenuItem('clear', '조용한 채팅방 해제'),
        ],
        x: position.dx + 4,
        y: position.dy,
      );
      if (!context.mounted || result == null) {
        return;
      }
      await handleResult(result);
      return;
    }

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
          value: 'open',
          height: 28,
          padding: EdgeInsets.zero,
          child: _RoomMenuItemContent(label: '조용한 채팅방 열기'),
        ),
        PopupMenuDivider(height: 10),
        PopupMenuItem(
          value: 'read',
          height: 28,
          padding: EdgeInsets.zero,
          child: _RoomMenuItemContent(label: '읽음 처리'),
        ),
        PopupMenuItem(
          value: 'hide',
          height: 28,
          padding: EdgeInsets.zero,
          child: _RoomMenuItemContent(label: '조용한 채팅방 숨김'),
        ),
        PopupMenuItem(
          value: 'clear',
          height: 28,
          padding: EdgeInsets.zero,
          child: _RoomMenuItemContent(label: '조용한 채팅방 해제'),
        ),
      ],
    );

    if (!context.mounted || result == null) {
      return;
    }
    await handleResult(result);
  }

  Future<void> _showQuietRoomContextMenu(
    BuildContext context,
    WidgetRef ref,
    ChatRoom room,
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
          value: 'open',
          height: 28,
          padding: EdgeInsets.zero,
          child: _RoomMenuItemContent(label: '채팅방 열기'),
        ),
        PopupMenuDivider(height: 10),
        PopupMenuItem(
          value: 'read',
          height: 28,
          padding: EdgeInsets.zero,
          child: _RoomMenuItemContent(label: '읽음 처리        R'),
        ),
        PopupMenuItem(
          value: 'floating',
          height: 28,
          padding: EdgeInsets.zero,
          child: _RoomMenuItemContent(label: '플로팅 띄우기'),
        ),
        PopupMenuDivider(height: 10),
        PopupMenuItem(
          value: 'unquiet',
          height: 28,
          padding: EdgeInsets.zero,
          child: _RoomMenuItemContent(label: '조용한 채팅방에서 해제'),
        ),
        PopupMenuItem(
          value: 'leave',
          height: 28,
          padding: EdgeInsets.zero,
          child: _RoomMenuItemContent(label: '채팅방 나가기'),
        ),
      ],
    );

    if (!context.mounted || result == null) {
      return;
    }
    if (result == 'open') {
      unawaited(Navigator.of(context).maybePop());
      _openRoom(ref, room);
    } else if (result == 'read') {
      await _markRoomRead(context, ref, room);
    } else if (result == 'floating') {
      await _showFloating(ref, room);
    } else if (result == 'unquiet') {
      ref.read(quietChatRoomsProvider.notifier).remove(room.id);
      if (context.mounted) {
        _showQuietToast(context);
      }
    } else if (result == 'leave') {
      await _leaveRoom(context, ref, room);
      ref.read(quietChatRoomsProvider.notifier).remove(room.id);
      if (context.mounted) {
        _showQuietToast(context);
      }
    }
  }

  void _showQuietToast(BuildContext context) {
    _showBlackToast(
      context,
      '\uC870\uC6A9\uD55C \uCC44\uD305\uBC29\uC5D0\uC11C \uD574\uC81C\uB418\uC5C8\uC2B5\uB2C8\uB2E4.',
    );
  }

  void _showBlackToast(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 1),
  }) {
    showAvaToast(context, message, duration: duration);
  }

  Future<void> _markQuietRoomsRead(
    BuildContext context,
    WidgetRef ref,
    List<ChatRoom> rooms,
  ) async {
    for (final room in rooms) {
      if (!context.mounted) {
        return;
      }
      await _markRoomRead(context, ref, room);
    }
  }

  Future<void> _showQuietRoomsDialog(
    BuildContext context,
    WidgetRef ref,
    List<ChatRoom> rooms,
  ) async {
    if (Platform.isWindows) {
      await _showNativeQuietRoomsPopup(context, ref, rooms);
      return;
    }

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.12),
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final quietIds = ref.watch(quietChatRoomsProvider).toSet();
          final currentRooms = [
            for (final room in ref.watch(chatRoomsProvider))
              if (quietIds.contains(room.id)) room,
          ];
          if (currentRooms.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                Navigator.of(context).maybePop();
              }
            });
          }
          return _QuietRoomsDialog(
            rooms: currentRooms,
            onOpen: (room) {
              unawaited(Navigator.of(context).maybePop());
              _openRoom(ref, room);
            },
            onContextMenu: (room, position) =>
                _showQuietRoomContextMenu(context, ref, room, position),
          );
        },
      ),
    );
  }

  Future<void> _showNativeQuietRoomsPopup(
    BuildContext context,
    WidgetRef ref,
    List<ChatRoom> rooms,
  ) async {
    WindowControl.setQuietRoomsPopupHandler((action, arguments) async {
      final roomId = arguments['roomId'] as String? ?? '';
      final room = _findRoomById(ref, roomId);
      if (action == 'closed') {
        WindowControl.setQuietRoomsPopupHandler(null);
        return;
      }
      if (room == null) {
        return;
      }

      if (action == 'openRoom') {
        _openRoom(ref, room);
      } else if (action == 'read') {
        await _markRoomRead(context, ref, room);
      } else if (action == 'floating') {
        await _showFloating(ref, room);
      } else if (action == 'unquiet') {
        ref.read(quietChatRoomsProvider.notifier).remove(room.id);
      } else if (action == 'leave') {
        await _leaveRoom(context, ref, room);
        ref.read(quietChatRoomsProvider.notifier).remove(room.id);
      }
    });
    await WindowControl.showQuietRoomsPopup(rooms: _quietRoomPayload(rooms));
  }

  ChatRoom? _findRoomById(WidgetRef ref, String roomId) {
    if (roomId.isEmpty) {
      return null;
    }
    for (final room in ref.read(chatRoomsProvider)) {
      if (room.id == roomId) {
        return room;
      }
    }
    return null;
  }

  List<Map<String, Object?>> _quietRoomPayload(List<ChatRoom> rooms) {
    return _roomPickerPayload(rooms);
  }

  List<Map<String, Object?>> _roomPickerPayload(List<ChatRoom> rooms) {
    return [
      for (final room in rooms)
        {
          'id': room.id,
          'title': room.title,
          'preview': room.preview,
          'time': room.time,
          'avatarColor': _roomAvatarColor(room),
          'avatarImageUrl': _roomAvatarImageUrl(room),
          'avatarParts': _roomAvatarParts(room),
          'isGroup': !room.isDirectChat && !room.isSelfChat,
          'isMuted': room.isMuted,
          'unreadCount': room.unreadCount,
          'participantCount': room.displayParticipantCount,
        },
    ];
  }

  Future<void> _showFolderManageDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (ref.read(chatFoldersProvider).isEmpty) {
      await _showCreateFolderDialog(context, ref);
      return;
    }

    if (Platform.isWindows) {
      await _showNativeFolderManagePopup(context, ref);
      return;
    }

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.14),
      builder: (_) => const _FolderManageDialog(),
    );
  }

  Future<void> _showCreateFolderDialog(
    BuildContext context,
    WidgetRef ref, {
    List<String> initialRoomIds = const [],
    String? initialName,
    String? initialIcon,
    bool isEdit = false,
  }) async {
    final _FolderDraft? draft;
    if (Platform.isWindows) {
      draft = await _showNativeCreateFolderPopup(
        ref,
        initialRoomIds,
        initialName: initialName,
        initialIcon: initialIcon,
        isEdit: isEdit,
      );
    } else {
      draft = await showDialog<_FolderDraft>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.14),
        builder: (_) => _CreateFolderDialog(
          rooms: ref.read(chatRoomsProvider),
          initialRoomIds: initialRoomIds,
          initialName: initialName,
          initialIcon: initialIcon,
          isEdit: isEdit,
        ),
      );
    }
    if (draft == null) {
      return;
    }

    ref
        .read(chatFoldersProvider.notifier)
        .create(name: draft.name, icon: draft.icon, roomIds: draft.roomIds);
    if (!context.mounted) {
      return;
    }
    if (Platform.isWindows) {
      await _showNativeFolderManagePopup(context, ref);
      return;
    }
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.14),
      builder: (_) => const _FolderManageDialog(),
    );
  }

  Future<void> _showEditFolderDialog(
    BuildContext context,
    WidgetRef ref,
    ChatFolder folder,
  ) async {
    final _FolderDraft? draft;
    if (Platform.isWindows) {
      draft = await _showNativeCreateFolderPopup(
        ref,
        folder.roomIds,
        initialName: folder.name,
        initialIcon: folder.icon,
        isEdit: true,
      );
    } else {
      draft = await showDialog<_FolderDraft>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.14),
        builder: (_) => _CreateFolderDialog(
          rooms: ref.read(chatRoomsProvider),
          initialRoomIds: folder.roomIds,
          initialName: folder.name,
          initialIcon: folder.icon,
          isEdit: true,
        ),
      );
    }
    if (draft == null) {
      return;
    }
    ref
        .read(chatFoldersProvider.notifier)
        .update(
          folder.copyWith(
            name: draft.name,
            icon: draft.icon,
            roomIds: draft.roomIds,
          ),
        );
    if (context.mounted && Platform.isWindows) {
      await _showNativeFolderManagePopup(context, ref);
    }
  }

  Future<void> _showNativeFolderManagePopup(
    BuildContext context,
    WidgetRef ref,
  ) async {
    WindowControl.setFolderPopupHandler((action, arguments) async {
      if (action == 'createFolder') {
        WindowControl.setFolderPopupHandler(null);
        if (context.mounted) {
          await _showCreateFolderDialog(context, ref);
        }
      } else if (action == 'addFavorite') {
        ref.read(chatFoldersProvider.notifier).ensureFavoriteFolder();
        if (context.mounted) {
          await _showNativeFolderManagePopup(context, ref);
        }
      } else if (action == 'editFolder') {
        final folderId = arguments['folderId'] as String? ?? '';
        ChatFolder? folder;
        for (final item in ref.read(chatFoldersProvider)) {
          if (item.id == folderId) {
            folder = item;
            break;
          }
        }
        WindowControl.setFolderPopupHandler(null);
        if (context.mounted && folder != null) {
          await _showEditFolderDialog(context, ref, folder);
        }
      } else if (action == 'deleteFolder') {
        ref
            .read(chatFoldersProvider.notifier)
            .delete(arguments['folderId'] as String? ?? '');
        if (context.mounted) {
          await _showNativeFolderManagePopup(context, ref);
        }
      } else if (action == 'reorderFolders') {
        final orderedIds = (arguments['folderIds'] as List? ?? const [])
            .whereType<String>()
            .toList();
        ref.read(chatFilterOrderProvider.notifier).reorder(orderedIds);
        ref.read(chatFoldersProvider.notifier).reorder([
          for (final id in orderedIds)
            if (id != unreadChatFolderId) id,
        ]);
      } else if (action == 'closed') {
        WindowControl.setFolderPopupHandler(null);
      }
    });

    final quietRoomIds = ref.read(quietChatRoomsProvider).toSet();
    final rooms = [
      for (final room in ref.read(chatRoomsProvider))
        if (!quietRoomIds.contains(room.id)) room,
    ];
    final folders = ref.read(chatFoldersProvider);
    final unreadCount = rooms.fold<int>(
      0,
      (count, room) => count + room.unreadCount,
    );
    final entries = _orderedFolderEntries(
      folders: folders,
      filterOrder: ref.read(chatFilterOrderProvider),
      unreadCount: unreadCount,
    );
    await WindowControl.showFolderManagePopup(
      unreadCount: unreadCount,
      hasFavorite: folders.any((folder) => folder.isFavorite),
      folders: [
        for (final entry in entries)
          {
            'id': entry.id,
            'name': entry.name,
            'icon': entry.icon,
            'count': entry.count,
            'isFavorite': entry.folder?.isFavorite ?? false,
            'isSystem': entry.isSystem,
          },
      ],
    );
  }

  Future<_FolderDraft?> _showNativeCreateFolderPopup(
    WidgetRef ref,
    List<String> initialRoomIds, {
    String? initialName,
    String? initialIcon,
    bool isEdit = false,
  }) async {
    final completer = Completer<_FolderDraft?>();
    WindowControl.setFolderPopupHandler((action, arguments) async {
      if (completer.isCompleted) {
        return;
      }
      if (action == 'created') {
        final roomIds = (arguments['roomIds'] as List? ?? const [])
            .whereType<String>()
            .toList();
        completer.complete(
          _FolderDraft(
            name: arguments['name'] as String? ?? '',
            icon: arguments['icon'] as String? ?? '⊘',
            roomIds: roomIds,
          ),
        );
      } else if (action == 'closed') {
        completer.complete(null);
      }
    });

    final rooms = ref.read(chatRoomsProvider);
    await WindowControl.showFolderCreatePopup(
      initialRoomIds: initialRoomIds,
      initialName: initialName,
      initialIcon: initialIcon,
      isEdit: isEdit,
      rooms: [
        for (final room in rooms)
          {
            'id': room.id,
            'title': room.title,
            'preview': room.preview,
            'avatarColor': _roomAvatarColor(room),
            'avatarImageUrl': _roomAvatarImageUrl(room),
            'avatarParts': _roomAvatarParts(room),
            'isGroup': !room.isDirectChat && !room.isSelfChat,
            'participantCount': room.displayParticipantCount,
            'unreadCount': room.unreadCount,
          },
      ],
    );

    try {
      return await completer.future.timeout(
        const Duration(minutes: 30),
        onTimeout: () => null,
      );
    } finally {
      WindowControl.setFolderPopupHandler(null);
    }
  }

  Future<void> _leaveRoom(
    BuildContext context,
    WidgetRef ref,
    ChatRoom room,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.24),
      builder: (dialogContext) => _LeaveRoomConfirmDialog(room: room),
    );
    if (confirmed != true) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    await _leaveRoomImmediately(context, ref, room);
  }

  Future<void> _leaveRoomImmediately(
    BuildContext context,
    WidgetRef ref,
    ChatRoom room,
  ) async {
    if (room.isDraft) {
      ref.read(chatRoomsProvider.notifier).remove(room.id);
      if (ref.read(selectedChatRoomProvider)?.id == room.id) {
        ref.read(selectedChatRoomProvider.notifier).close();
        WindowControl.compactMessenger();
      }
      return;
    }

    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      return;
    }

    try {
      await ref
          .read(chatApiProvider)
          .leaveRoom(accessToken: session.accessToken, roomCode: room.id);
      ref.read(chatRoomsProvider.notifier).remove(room.id);
      if (ref.read(selectedChatRoomProvider)?.id == room.id) {
        ref.read(selectedChatRoomProvider.notifier).close();
        WindowControl.compactMessenger();
      }
    } on Object catch (error) {
      if (!context.mounted) {
        return;
      }
      showAvaToast(context, authErrorMessage(error));
    }
  }
}

class _LeaveRoomConfirmDialog extends StatelessWidget {
  const _LeaveRoomConfirmDialog({required this.room});

  static const _question =
      '\uCC44\uD305\uBC29\uC744 \uB098\uAC00\uC2DC\uACA0\uC5B4\uC694?';
  static const _leave = '\uB098\uAC00\uAE30';
  static const _cancel = '\uCDE8\uC18C';

  final ChatRoom room;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 10,
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Material(
          color: Colors.white,
          child: SizedBox(
            width: 258,
            height: 164,
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned(
                        top: 7,
                        right: 7,
                        child: SizedBox.square(
                          dimension: 26,
                          child: IconButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            padding: EdgeInsets.zero,
                            splashRadius: 14,
                            icon: const Icon(
                              Icons.close,
                              size: 20,
                              color: Color(0xFF8C8C8C),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 25, 22, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ProfileAvatar(profile: _profile, size: 44),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    room.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              _question,
                              style: TextStyle(
                                color: Color(0xFF333333),
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFE7E7E7),
                ),
                SizedBox(
                  height: 43,
                  child: Row(
                    children: [
                      Expanded(
                        child: _LeaveDialogButton(
                          label: _leave,
                          onTap: () => Navigator.of(context).pop(true),
                        ),
                      ),
                      const VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: Color(0xFFE7E7E7),
                      ),
                      Expanded(
                        child: _LeaveDialogButton(
                          label: _cancel,
                          onTap: () => Navigator.of(context).pop(false),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PersonProfile get _profile {
    if (room.members.isNotEmpty) {
      return room.members.first;
    }
    return PersonProfile(name: room.title, color: const Color(0xFFA6BCEB));
  }
}

class _LeaveDialogButton extends StatefulWidget {
  const _LeaveDialogButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_LeaveDialogButton> createState() => _LeaveDialogButtonState();
}

class _LeaveDialogButtonState extends State<_LeaveDialogButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: ColoredBox(
          color: _isHovered ? const Color(0xFFF7F7F7) : Colors.white,
          child: Center(
            child: Text(
              widget.label,
              style: const TextStyle(
                color: Color(0xFF111111),
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderDraft {
  const _FolderDraft({
    required this.name,
    required this.icon,
    required this.roomIds,
  });

  final String name;
  final String icon;
  final List<String> roomIds;
}

class _FolderManageEntry {
  const _FolderManageEntry({
    required this.id,
    required this.name,
    required this.icon,
    required this.count,
    this.folder,
    this.isSystem = false,
  });

  final String id;
  final String name;
  final String icon;
  final int count;
  final ChatFolder? folder;
  final bool isSystem;
}

const _folderIconChoices = [
  '⊘',
  '⌂',
  '■',
  '💗',
  '✎',
  '▣',
  '▬',
  '✈',
  '✚',
  '☺',
  '★',
  '○',
];

class _CreateFolderDialog extends StatefulWidget {
  const _CreateFolderDialog({
    required this.rooms,
    this.initialRoomIds = const [],
    this.initialName,
    this.initialIcon,
    this.isEdit = false,
  });

  final List<ChatRoom> rooms;
  final List<String> initialRoomIds;
  final String? initialName;
  final String? initialIcon;
  final bool isEdit;

  @override
  State<_CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<_CreateFolderDialog> {
  late final TextEditingController _nameController;
  late String _selectedIcon;
  late List<String> _roomIds;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController()
      ..addListener(() => setState(() {}));
    _nameController.text = widget.initialName ?? '';
    _selectedIcon = widget.initialIcon ?? '⊘';
    _roomIds = [...widget.initialRoomIds];
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _nameController.text.trim();
    final selectedRooms = [
      for (final room in widget.rooms)
        if (_roomIds.contains(room.id)) room,
    ];
    final canConfirm = name.isNotEmpty && name.length <= 10;

    return _FolderDialogShell(
      width: 370,
      height: 600,
      title: widget.isEdit ? '폴더 편집' : '폴더 만들기',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  maxLength: 10,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: '폴더 이름을 입력해 주세요.',
                    hintStyle: TextStyle(color: Color(0xFF9A9A9A)),
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFE3E3E3)),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFE3E3E3)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${_nameController.text.length}/10',
                style: const TextStyle(color: Color(0xFF777777), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            '폴더 아이콘',
            style: TextStyle(fontSize: 13, color: Color(0xFF555555)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              for (final icon in _folderIconChoices)
                _FolderIconChoice(
                  icon: icon,
                  isSelected: _selectedIcon == icon,
                  onTap: () => setState(() => _selectedIcon = icon),
                ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            '등록한 채팅방',
            style: TextStyle(fontSize: 13, color: Color(0xFF555555)),
          ),
          const SizedBox(height: 12),
          _AddRoomsButton(
            onTap: () async {
              final selected = await showDialog<List<String>>(
                context: context,
                barrierColor: Colors.black.withValues(alpha: 0.14),
                builder: (_) => _RoomSelectDialog(
                  rooms: widget.rooms,
                  selectedRoomIds: _roomIds,
                ),
              );
              if (selected != null) {
                setState(() => _roomIds = selected);
              }
            },
          ),
          const SizedBox(height: 14),
          for (final room in selectedRooms)
            _SelectedFolderRoomRow(
              room: room,
              onRemove: () =>
                  setState(() => _roomIds.removeWhere((id) => id == room.id)),
            ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _FolderDialogButton(
                label: '확인',
                isPrimary: true,
                enabled: canConfirm,
                onTap: () => Navigator.of(context).pop(
                  _FolderDraft(
                    name: name,
                    icon: _selectedIcon,
                    roomIds: _roomIds,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _FolderDialogButton(
                label: '취소',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoomSelectDialog extends StatefulWidget {
  const _RoomSelectDialog({required this.rooms, required this.selectedRoomIds});

  final List<ChatRoom> rooms;
  final List<String> selectedRoomIds;

  @override
  State<_RoomSelectDialog> createState() => _RoomSelectDialogState();
}

class _RoomSelectDialogState extends State<_RoomSelectDialog> {
  late final TextEditingController _searchController;
  late final Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController()
      ..addListener(() => setState(() {}));
    _selectedIds = {...widget.selectedRoomIds};
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final rooms = widget.rooms
        .where(
          (room) =>
              query.isEmpty ||
              room.title.toLowerCase().contains(query) ||
              room.preview.toLowerCase().contains(query),
        )
        .toList();

    return _FolderDialogShell(
      width: 370,
      height: 600,
      title: '채팅방 선택',
      child: Column(
        children: [
          SizedBox(
            height: 38,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Color(0xFFA9A9A9)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Color(0xFF777777)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: rooms.length,
              itemBuilder: (context, index) {
                final room = rooms[index];
                final isSelected = _selectedIds.contains(room.id);
                return _SelectableRoomRow(
                  room: room,
                  isSelected: isSelected,
                  mobileLayout: false,
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedIds.remove(room.id);
                      } else {
                        _selectedIds.add(room.id);
                      }
                    });
                  },
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _FolderDialogButton(
                label: '선택',
                isPrimary: true,
                enabled: _selectedIds.isNotEmpty,
                onTap: () => Navigator.of(context).pop(_selectedIds.toList()),
              ),
              const SizedBox(width: 8),
              _FolderDialogButton(
                label: '취소',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FolderManageDialog extends ConsumerWidget {
  const _FolderManageDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(chatFoldersProvider);
    final filterOrder = ref.watch(chatFilterOrderProvider);
    final rooms = ref.watch(chatRoomsProvider);
    final unreadCount = rooms.fold<int>(
      0,
      (count, room) => count + room.unreadCount,
    );
    final entries = _orderedFolderEntries(
      folders: folders,
      filterOrder: filterOrder,
      unreadCount: unreadCount,
    );
    final hasFavorite = folders.any((folder) => folder.isFavorite);

    return _FolderDialogShell(
      width: 370,
      height: 600,
      title: '채팅방 폴더 관리',
      bottom: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          final draft = await showDialog<_FolderDraft>(
            context: context,
            barrierColor: Colors.black.withValues(alpha: 0.14),
            builder: (_) =>
                _CreateFolderDialog(rooms: ref.read(chatRoomsProvider)),
          );
          if (draft != null) {
            ref
                .read(chatFoldersProvider.notifier)
                .create(
                  name: draft.name,
                  icon: draft.icon,
                  roomIds: draft.roomIds,
                );
          }
        },
        child: const SizedBox(
          height: 46,
          child: Center(
            child: Text(
              '+ 폴더 만들기',
              style: TextStyle(fontSize: 14, color: Colors.black),
            ),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: entries.length,
            onReorder: (oldIndex, newIndex) {
              final next = [...entries];
              if (newIndex > oldIndex) {
                newIndex -= 1;
              }
              final moved = next.removeAt(oldIndex);
              next.insert(newIndex, moved);
              ref.read(chatFilterOrderProvider.notifier).reorder([
                for (final entry in next) entry.id,
              ]);
              ref.read(chatFoldersProvider.notifier).reorder([
                for (final entry in next)
                  if (!entry.isSystem) entry.id,
              ]);
            },
            itemBuilder: (context, index) {
              final entry = entries[index];
              final folder = entry.folder;
              return _FolderManageRow(
                key: ValueKey('manage-folder-${entry.id}'),
                icon: entry.icon,
                title: entry.name,
                count: entry.count,
                dragIndex: index,
                onEdit: folder == null || folder.isFavorite
                    ? null
                    : () async {
                        final draft = await showDialog<_FolderDraft>(
                          context: context,
                          barrierColor: Colors.black.withValues(alpha: 0.14),
                          builder: (_) => _CreateFolderDialog(
                            rooms: ref.read(chatRoomsProvider),
                            initialRoomIds: folder.roomIds,
                            initialName: folder.name,
                            initialIcon: folder.icon,
                            isEdit: true,
                          ),
                        );
                        if (draft != null) {
                          ref
                              .read(chatFoldersProvider.notifier)
                              .update(
                                folder.copyWith(
                                  name: draft.name,
                                  icon: draft.icon,
                                  roomIds: draft.roomIds,
                                ),
                              );
                        }
                      },
                onDelete: folder == null
                    ? null
                    : () => ref
                          .read(chatFoldersProvider.notifier)
                          .delete(folder.id),
              );
            },
          ),
          if (!hasFavorite) ...[
            const SizedBox(height: 18),
            const Text(
              '추천 폴더',
              style: TextStyle(color: Color(0xFF777777), fontSize: 13),
            ),
            const SizedBox(height: 8),
            _RecommendedFolderRow(
              enabled: true,
              onTap: () =>
                  ref.read(chatFoldersProvider.notifier).ensureFavoriteFolder(),
            ),
          ],
        ],
      ),
    );
  }
}

class _FolderDialogShell extends StatelessWidget {
  const _FolderDialogShell({
    required this.title,
    required this.child,
    required this.width,
    required this.height,
    this.bottom,
  });

  final String title;
  final Widget child;
  final double width;
  final double height;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 10,
      insetPadding: const EdgeInsets.all(18),
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Material(
          color: Colors.white,
          child: SizedBox(
            width: width,
            height: height,
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, size: 18),
                          color: const Color(0xFF8A8A8A),
                          splashRadius: 14,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 36, 18, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 17,
                                color: Colors.black,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 22),
                            Expanded(child: child),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (bottom != null) ...[
                  const Divider(height: 1, color: Color(0xFFE5E5E5)),
                  bottom!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderIconChoice extends StatelessWidget {
  const _FolderIconChoice({
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F4),
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: const Color(0xFF333333), width: 1.4)
              : null,
        ),
        child: Icon(
          _folderIconData(icon),
          color: _folderIconColor(icon),
          size: 19,
        ),
      ),
    );
  }
}

class _AddRoomsButton extends StatelessWidget {
  const _AddRoomsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8F8),
              border: Border.all(color: const Color(0xFFE5E5E5)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.add, size: 22, color: Color(0xFF555555)),
          ),
          const SizedBox(width: 12),
          const Text(
            '채팅방 추가',
            style: TextStyle(color: Colors.black, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _SelectedFolderRoomRow extends StatelessWidget {
  const _SelectedFolderRoomRow({required this.room, required this.onRemove});

  final ChatRoom room;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          _MiniRoomAvatar(room: room),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${room.title} ${room.displayParticipantCount}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Colors.black),
            ),
          ),
          OutlinedButton(
            onPressed: onRemove,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 30),
              padding: EdgeInsets.zero,
              side: const BorderSide(color: Color(0xFFE1E1E1)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            child: const Text(
              '해제',
              style: TextStyle(color: Colors.black, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectableRoomRow extends StatelessWidget {
  const _SelectableRoomRow({
    required this.room,
    required this.isSelected,
    required this.mobileLayout,
    required this.onTap,
  });

  final ChatRoom room;
  final bool isSelected;
  final bool mobileLayout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 68,
        color: isSelected ? const Color(0xFFFFF8D8) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Row(
          children: [
            _MiniRoomAvatar(room: room, size: 42),
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
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    room.preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF6E6E6E),
                      fontSize: 12,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isSelected
                  ? const Color(0xFFFFD600)
                  : const Color(0xFF9A9A9A),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniRoomAvatar extends StatelessWidget {
  const _MiniRoomAvatar({required this.room, this.size = 40});

  final ChatRoom room;
  final double size;

  @override
  Widget build(BuildContext context) {
    final roomImageUrl = room.avatarImageUrl?.trim() ?? '';
    if (roomImageUrl.isNotEmpty) {
      return ProfileAvatar(
        profile: PersonProfile(
          name: room.title,
          color: const Color(0xFFA6C6EE),
          imageUrl: roomImageUrl,
        ),
        size: size,
      );
    }
    if (room.isDirectChat || room.members.length <= 1) {
      final profile = room.members.isEmpty
          ? PersonProfile(name: room.title, color: const Color(0xFFA6C6EE))
          : room.members.first;
      return ProfileAvatar(profile: profile, size: size);
    }

    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          for (var i = 0; i < room.members.length.clamp(1, 4); i++)
            Positioned(
              left: i.isEven ? 0 : size / 2,
              top: i < 2 ? 0 : size / 2,
              child: ProfileAvatar(profile: room.members[i], size: size / 2),
            ),
        ],
      ),
    );
  }
}

class _FolderDialogButton extends StatelessWidget {
  const _FolderDialogButton({
    required this.label,
    required this.onTap,
    this.isPrimary = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 37,
      child: TextButton(
        onPressed: enabled ? onTap : null,
        style: TextButton.styleFrom(
          backgroundColor: !enabled
              ? const Color(0xFFF0F0F0)
              : isPrimary
              ? const Color(0xFFFFDF00)
              : Colors.white,
          foregroundColor: enabled ? Colors.black : const Color(0xFFB5B5B5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(2),
            side: BorderSide(
              color: isPrimary ? Colors.transparent : const Color(0xFFE1E1E1),
            ),
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}

class _FolderManageRow extends StatelessWidget {
  const _FolderManageRow({
    super.key,
    required this.icon,
    required this.title,
    this.count,
    this.dragIndex,
    this.onEdit,
    this.onDelete,
  });

  final String icon;
  final String title;
  final int? count;
  final int? dragIndex;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE1E1E1)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: [
          dragIndex == null
              ? const Icon(Icons.drag_handle, size: 18, color: Colors.black)
              : ReorderableDragStartListener(
                  index: dragIndex!,
                  child: const Icon(
                    Icons.drag_handle,
                    size: 18,
                    color: Colors.black,
                  ),
                ),
          const SizedBox(width: 14),
          Icon(_folderIconData(icon), color: _folderIconColor(icon), size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                text: title,
                style: const TextStyle(color: Colors.black, fontSize: 14),
                children: [
                  if ((count ?? 0) > 0)
                    TextSpan(
                      text: ' $count',
                      style: const TextStyle(color: Color(0xFF4F7DBD)),
                    ),
                ],
              ),
            ),
          ),
          if (onEdit != null)
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 19),
              color: const Color(0xFF333333),
              splashRadius: 16,
            ),
          if (onDelete != null)
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 19),
              color: const Color(0xFF333333),
              splashRadius: 16,
            ),
        ],
      ),
    );
  }
}

class _RecommendedFolderRow extends StatelessWidget {
  const _RecommendedFolderRow({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE1E1E1)),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(
          children: [
            Icon(
              Icons.star,
              size: 22,
              color: enabled
                  ? const Color(0xFFFFA000)
                  : const Color(0xFFC0C0C0),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '즐겨찾기',
                style: TextStyle(fontSize: 14, color: Colors.black),
              ),
            ),
            Icon(
              enabled ? Icons.add : Icons.check,
              color: const Color(0xFF555555),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatFolderFilters extends StatefulWidget {
  const _ChatFolderFilters({
    required this.folders,
    required this.filterOrder,
    required this.rooms,
    required this.activeFolderId,
    required this.unreadCount,
    required this.onSelectFolder,
    required this.onManageFolders,
  });

  final List<ChatFolder> folders;
  final List<String> filterOrder;
  final List<ChatRoom> rooms;
  final String? activeFolderId;
  final int unreadCount;
  final ValueChanged<String?> onSelectFolder;
  final VoidCallback onManageFolders;

  @override
  State<_ChatFolderFilters> createState() => _ChatFolderFiltersState();
}

class _ChatFolderFiltersState extends State<_ChatFolderFilters> {
  final ScrollController _scrollController = ScrollController();
  bool _isHovered = false;
  bool _hasOverflow = false;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollButtons);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollButtons());
  }

  @override
  void didUpdateWidget(covariant _ChatFolderFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollButtons());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollButtons);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollButtons() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final hasOverflow = position.maxScrollExtent > 1;
    final canScrollLeft = hasOverflow && position.pixels > 1;
    final canScrollRight =
        hasOverflow && position.pixels < position.maxScrollExtent - 1;
    if (_hasOverflow == hasOverflow &&
        _canScrollLeft == canScrollLeft &&
        _canScrollRight == canScrollRight) {
      return;
    }
    setState(() {
      _hasOverflow = hasOverflow;
      _canScrollLeft = canScrollLeft;
      _canScrollRight = canScrollRight;
    });
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) {
      return;
    }
    final target = (_scrollController.offset + delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _orderedFolderEntries(
      folders: widget.folders,
      filterOrder: widget.filterOrder,
      unreadCount: widget.unreadCount,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 18, 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: SizedBox(
          height: 34,
          child: Listener(
            onPointerSignal: (event) {
              if (event is! PointerScrollEvent ||
                  !_scrollController.hasClients ||
                  !_hasOverflow) {
                return;
              }
              final delta =
                  event.scrollDelta.dy.abs() >= event.scrollDelta.dx.abs()
                  ? event.scrollDelta.dy
                  : event.scrollDelta.dx;
              if (delta == 0) {
                return;
              }
              final target = (_scrollController.offset + delta).clamp(
                0.0,
                _scrollController.position.maxScrollExtent,
              );
              _scrollController.jumpTo(target);
            },
            child: Stack(
              children: [
                ListView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  children: [
                    _FilterChip(
                      key: const ValueKey('chat-filter-all'),
                      label: '전체',
                      isActive: widget.activeFolderId == null,
                      onTap: () => widget.onSelectFolder(null),
                    ),
                    const SizedBox(width: 8),
                    for (final entry in entries) ...[
                      if (!entry.isSystem) const SizedBox(width: 8),
                      Builder(
                        builder: (context) {
                          final folder = entry.folder;
                          final unreadCount = folder == null
                              ? widget.unreadCount
                              : _folderUnreadCount(folder, widget.rooms);
                          final folderId = entry.isSystem
                              ? unreadChatFolderId
                              : entry.id;
                          final icon = entry.isSystem
                              ? Icons.chat_bubble
                              : _folderIconData(entry.icon);
                          final iconColor = entry.isSystem
                              ? const Color(0xFF52A7F4)
                              : _folderIconColor(entry.icon);
                          return _FilterChip(
                            key: ValueKey('chat-filter-folder-$folderId'),
                            label: entry.name,
                            suffix: unreadCount > 0 ? '$unreadCount' : null,
                            icon: icon,
                            iconColor: iconColor,
                            isActive: widget.activeFolderId == folderId,
                            onTap: () => widget.onSelectFolder(folderId),
                          );
                        },
                      ),
                    ],
                    const SizedBox(width: 8),
                    SizedBox.square(
                      dimension: 32,
                      child: OutlinedButton(
                        onPressed: widget.onManageFolders,
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: const CircleBorder(),
                          side: const BorderSide(color: Color(0xFFE3E3E3)),
                        ),
                        child: Icon(
                          widget.folders.isEmpty
                              ? Icons.add
                              : Icons.playlist_add,
                          color: const Color(0xFF7D7D7D),
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_isHovered && _hasOverflow && _canScrollLeft)
                  Positioned(
                    left: 0,
                    top: 3,
                    child: _FolderScrollButton(
                      icon: Icons.chevron_left,
                      onPressed: () => _scrollBy(-150),
                    ),
                  ),
                if (_isHovered && _hasOverflow && _canScrollRight)
                  Positioned(
                    right: 0,
                    top: 3,
                    child: _FolderScrollButton(
                      icon: Icons.chevron_right,
                      onPressed: () => _scrollBy(150),
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

int _folderUnreadCount(ChatFolder folder, List<ChatRoom> rooms) {
  var unreadCount = 0;
  for (final room in rooms) {
    if (folder.roomIds.contains(room.id)) {
      unreadCount += room.unreadCount;
    }
  }
  return unreadCount;
}

List<_FolderManageEntry> _orderedFolderEntries({
  required List<ChatFolder> folders,
  required List<String> filterOrder,
  required int unreadCount,
}) {
  final folderById = {for (final folder in folders) folder.id: folder};
  final entries = <_FolderManageEntry>[];
  var addedUnread = false;
  for (final id in filterOrder) {
    if (id == unreadChatFolderId) {
      if (!addedUnread) {
        entries.add(
          _FolderManageEntry(
            id: unreadChatFolderId,
            name: '안읽음',
            icon: '\uD83D\uDCAC',
            count: unreadCount,
            isSystem: true,
          ),
        );
        addedUnread = true;
      }
      continue;
    }
    final folder = folderById.remove(id);
    if (folder == null) {
      continue;
    }
    entries.add(
      _FolderManageEntry(
        id: folder.id,
        name: folder.name,
        icon: folder.icon,
        count: folder.roomIds.length,
        folder: folder,
      ),
    );
  }
  if (!addedUnread) {
    entries.insert(
      0,
      _FolderManageEntry(
        id: unreadChatFolderId,
        name: '안읽음',
        icon: '\uD83D\uDCAC',
        count: unreadCount,
        isSystem: true,
      ),
    );
  }
  for (final folder in folders) {
    if (!folderById.containsKey(folder.id)) {
      continue;
    }
    entries.add(
      _FolderManageEntry(
        id: folder.id,
        name: folder.name,
        icon: folder.icon,
        count: folder.roomIds.length,
        folder: folder,
      ),
    );
  }
  return entries;
}

IconData _folderIconData(String icon) {
  final normalized = icon.replaceAll('\uFE0F', '');
  return switch (normalized) {
    '\u2298' => Icons.block,
    '\u2302' || '\uD83C\uDFE0' => Icons.home,
    '\u25A0' || '\uD83D\uDCBC' => Icons.work,
    '\u2665' || '\uD83D\uDC97' => Icons.favorite,
    '\u270E' || '\u270F' => Icons.edit,
    '\u25A3' || '\uD83E\uDDFA' => Icons.shopping_basket,
    '\u25AC' || '\uD83D\uDCB3' => Icons.credit_card,
    '\u2708' => Icons.flight,
    '\u271A' || '\u2795' => Icons.add,
    '\u263A' => Icons.mood,
    '\u2605' || '\u2B50' => Icons.star,
    '\u25CB' => Icons.circle_outlined,
    '\uD83D\uDC31' || '\uD83D\uDC36' => Icons.pets,
    _ => Icons.chat_bubble,
  };
}

Color _folderIconColor(String icon) {
  final normalized = icon.replaceAll('\uFE0F', '');
  return switch (normalized) {
    '\u2302' || '\uD83C\uDFE0' => const Color(0xFFFF6F3C),
    '\u25A0' || '\uD83D\uDCBC' => const Color(0xFF8A5A28),
    '\u2665' || '\uD83D\uDC97' => const Color(0xFFFF5B9E),
    '\u270E' || '\u270F' => const Color(0xFFFF7A1A),
    '\u25A3' || '\uD83E\uDDFA' => const Color(0xFFE84D5B),
    '\u25AC' || '\uD83D\uDCB3' => const Color(0xFF3D8BFF),
    '\u2708' => const Color(0xFF4A90E2),
    '\u271A' || '\u2795' => const Color(0xFF00A86B),
    '\u263A' => const Color(0xFFFFC107),
    '\u2605' || '\u2B50' => const Color(0xFFFFA000),
    _ => const Color(0xFF52A7F4),
  };
}

// ignore: unused_element
class _ChatFilters extends ConsumerWidget {
  const _ChatFilters({required this.unreadCount});

  final int unreadCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadOnly = ref.watch(unreadOnlyFilterProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 18, 8),
      child: Row(
        children: [
          _FilterChip(
            key: const ValueKey('chat-filter-all'),
            label: '전체',
            isActive: !unreadOnly,
            onTap: () => ref.read(unreadOnlyFilterProvider.notifier).showAll(),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            key: const ValueKey('chat-filter-unread'),
            label: '안읽음',
            suffix: '$unreadCount',
            icon: Icons.chat_bubble,
            isActive: unreadOnly,
            onTap: () =>
                ref.read(unreadOnlyFilterProvider.notifier).showUnreadOnly(),
          ),
          const SizedBox(width: 8),
          SizedBox.square(
            dimension: 32,
            child: OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
                side: const BorderSide(color: Color(0xFFE3E3E3)),
              ),
              child: const Icon(Icons.add, color: Color(0xFF9A9A9A), size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderScrollButton extends StatelessWidget {
  const _FolderScrollButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 28,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE1E1E1)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: IconButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          splashRadius: 14,
          icon: Icon(icon, size: 18, color: const Color(0xFF7A7A7A)),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.suffix,
    this.icon,
    this.iconColor,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final String? suffix;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: isActive ? Colors.black : Colors.white,
            border: Border.all(
              color: isActive ? Colors.black : const Color(0xFFE3E3E3),
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 15,
                  color: iconColor ?? const Color(0xFF52A7F4),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if ((int.tryParse(suffix ?? '') ?? 0) > 0) ...[
                const SizedBox(width: 4),
                _FilterUnreadBadge(
                  key: const ValueKey('unread-filter-badge'),
                  count: int.tryParse(suffix!) ?? 0,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomMenuItemContent extends StatefulWidget {
  const _RoomMenuItemContent({required this.label, super.key});

  final String label;

  @override
  State<_RoomMenuItemContent> createState() => _RoomMenuItemContentState();
}

class _RoomMenuItemContentState extends State<_RoomMenuItemContent> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        width: 152,
        height: 28,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        color: _isHovered ? const Color(0xFFEFEFEF) : Colors.transparent,
        child: Text(
          widget.label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 12,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

class _MobileRoomMenuAction {
  const _MobileRoomMenuAction({required this.value, required this.label});

  final String value;
  final String label;
}

class _MobileRoomContextMenu extends StatelessWidget {
  const _MobileRoomContextMenu({required this.title, required this.actions});

  final String title;
  final List<_MobileRoomMenuAction> actions;

  @override
  Widget build(BuildContext context) {
    final dialogWidth = (MediaQuery.sizeOf(context).width - 76)
        .clamp(280.0, 320.0)
        .toDouble();
    return Dialog(
      alignment: Alignment.center,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Material(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    letterSpacing: 0,
                  ),
                ),
              ),
              for (final action in actions)
                InkWell(
                  onTap: () => Navigator.of(context).pop(action.value),
                  splashColor: Colors.white.withValues(alpha: 0.08),
                  highlightColor: Colors.white.withValues(alpha: 0.06),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 13,
                    ),
                    child: Text(
                      action.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomFolderMenuItemContent extends StatefulWidget {
  const _RoomFolderMenuItemContent({required this.folders});

  final List<ChatFolder> folders;

  @override
  State<_RoomFolderMenuItemContent> createState() =>
      _RoomFolderMenuItemContentState();
}

class _RoomFolderMenuItemContentState
    extends State<_RoomFolderMenuItemContent> {
  bool _isHovered = false;
  bool _submenuOpen = false;

  Future<void> _openSubmenu() async {
    if (_submenuOpen || widget.folders.isEmpty) {
      return;
    }
    _submenuOpen = true;
    final overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox;
    final itemBox = context.findRenderObject() as RenderBox?;
    if (itemBox == null) {
      _submenuOpen = false;
      return;
    }
    final itemTopLeft = itemBox.localToGlobal(Offset.zero, ancestor: overlay);
    if (Platform.isWindows) {
      await WindowControl.showFolderSubmenuPopup(
        folders: [
          for (final folder in widget.folders)
            {'id': folder.id, 'name': folder.name, 'icon': folder.icon},
        ],
        x: itemTopLeft.dx + itemBox.size.width - 1,
        y: itemTopLeft.dy,
        parentWidth: itemBox.size.width,
        parentHeight: itemBox.size.height,
      );
      _submenuOpen = false;
      return;
    }
    final String? result;
    result = await showMenu<String>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          itemTopLeft.dx + itemBox.size.width - 1,
          itemTopLeft.dy,
          0,
          0,
        ),
        Offset.zero & overlay.size,
      ),
      elevation: 6,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFC8C8C8)),
        borderRadius: BorderRadius.circular(2),
      ),
      items: [
        for (final folder in widget.folders)
          PopupMenuItem(
            value: 'folder:${folder.id}',
            height: 28,
            padding: EdgeInsets.zero,
            child: _RoomFolderSubmenuItemContent(folder: folder),
          ),
      ],
    );
    _submenuOpen = false;
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(result ?? 'folder-submenu');
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _isHovered = true);
        Future<void>.microtask(_openSubmenu);
      },
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        width: 152,
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        color: _isHovered ? const Color(0xFFEFEFEF) : Colors.transparent,
        child: const Row(
          children: [
            Expanded(
              child: Text(
                '폴더에 추가',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  height: 1.1,
                ),
              ),
            ),
            Text(
              '>',
              style: TextStyle(color: Colors.black, fontSize: 12, height: 1.1),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomFolderSubmenuItemContent extends StatefulWidget {
  const _RoomFolderSubmenuItemContent({required this.folder});

  final ChatFolder folder;

  @override
  State<_RoomFolderSubmenuItemContent> createState() =>
      _RoomFolderSubmenuItemContentState();
}

class _RoomFolderSubmenuItemContentState
    extends State<_RoomFolderSubmenuItemContent> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        width: 96,
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        color: _isHovered ? const Color(0xFFEFEFEF) : Colors.transparent,
        child: Row(
          children: [
            Icon(
              _folderIconData(widget.folder.icon),
              size: 14,
              color: _folderIconColor(widget.folder.icon),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterUnreadBadge extends StatelessWidget {
  const _FilterUnreadBadge({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 18,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFFFF4B2B),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '$count',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _QuietChatRoomsTile extends StatefulWidget {
  const _QuietChatRoomsTile({
    required this.rooms,
    required this.onDoubleTap,
    required this.onContextMenu,
  });

  final List<ChatRoom> rooms;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset> onContextMenu;

  @override
  State<_QuietChatRoomsTile> createState() => _QuietChatRoomsTileState();
}

class _QuietChatRoomsTileState extends State<_QuietChatRoomsTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final roomCount = widget.rooms.length;
    final unreadCount = widget.rooms.fold<int>(
      0,
      (count, room) => count + room.unreadCount,
    );
    final time = widget.rooms.isEmpty ? '' : widget.rooms.first.time;
    final background = _isHovered ? const Color(0xFFEFEFEF) : Colors.white;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onDoubleTap,
        onSecondaryTapDown: (details) =>
            widget.onContextMenu(details.globalPosition),
        child: Container(
          color: background,
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 46,
                height: 52,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6E7FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const SizedBox.square(
                      dimension: 44,
                      child: Icon(
                        Icons.nightlight_round,
                        size: 27,
                        color: Color(0xFF8F93FF),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        right: 68,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '조용한 채팅방',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                height: 1.12,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '$roomCount개의 채팅방',
                              style: const TextStyle(
                                color: Color(0xFF555D66),
                                fontSize: 12,
                                height: 1.18,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 1,
                        right: 0,
                        child: Text(
                          time,
                          style: const TextStyle(
                            color: Color(0xFF747474),
                            fontSize: 11,
                            height: 1.1,
                          ),
                        ),
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          top: 25,
                          right: 0,
                          child: _UnreadBadge(count: unreadCount),
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

class _QuietRoomsDialog extends StatelessWidget {
  const _QuietRoomsDialog({
    required this.rooms,
    required this.onOpen,
    required this.onContextMenu,
  });

  final List<ChatRoom> rooms;
  final ValueChanged<ChatRoom> onOpen;
  final void Function(ChatRoom room, Offset position) onContextMenu;

  @override
  Widget build(BuildContext context) {
    return _FolderDialogShell(
      width: 370,
      height: 600,
      title: '조용한 채팅방',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '활동하지 않는 채팅방을 보관합니다. 채팅방 알림이 비활성화 되며 안 읽은 메시지 수에 포함되지 않습니다.',
            style: TextStyle(
              color: Color(0xFF555555),
              fontSize: 12,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.builder(
              itemCount: rooms.length,
              itemBuilder: (context, index) {
                final room = rooms[index];
                return _QuietRoomDialogTile(
                  room: room,
                  onOpen: () => onOpen(room),
                  onContextMenu: (position) => onContextMenu(room, position),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _QuietRoomDialogTile extends StatefulWidget {
  const _QuietRoomDialogTile({
    required this.room,
    required this.onOpen,
    required this.onContextMenu,
  });

  final ChatRoom room;
  final VoidCallback onOpen;
  final ValueChanged<Offset> onContextMenu;

  @override
  State<_QuietRoomDialogTile> createState() => _QuietRoomDialogTileState();
}

class _QuietRoomDialogTileState extends State<_QuietRoomDialogTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onOpen,
        onSecondaryTapDown: (details) =>
            widget.onContextMenu(details.globalPosition),
        child: Container(
          height: 70,
          color: _isHovered ? const Color(0xFFEFEFEF) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
          child: Row(
            children: [
              _MiniRoomAvatar(room: widget.room, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RoomTitleLine(room: widget.room),
                    const SizedBox(height: 5),
                    _RoomPreviewText(room: widget.room, maxLines: 1),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                widget.room.time,
                style: const TextStyle(
                  color: Color(0xFF747474),
                  fontSize: 11,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const List<String> _chatBannerAssets = [
  'assets/images/AVA_IMG/banner/02.png',
  'assets/images/AVA_IMG/banner/03.png',
  'assets/images/AVA_IMG/banner/04.png',
  'assets/images/AVA_IMG/banner/05.png',
  'assets/images/AVA_IMG/banner/06.png',
  'assets/images/AVA_IMG/banner/07.png',
  'assets/images/AVA_IMG/banner/08.png',
];

class _RotatingChatBanner extends StatefulWidget {
  const _RotatingChatBanner();

  @override
  State<_RotatingChatBanner> createState() => _RotatingChatBannerState();
}

class _RotatingChatBannerState extends State<_RotatingChatBanner> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _index = (_index + 1) % _chatBannerAssets.length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5EAF0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10000000),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 76,
              width: double.infinity,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 520),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [...previousChildren, ?currentChild],
                  );
                },
                transitionBuilder: (child, animation) {
                  final isIncoming =
                      child.key == ValueKey<String>(_chatBannerAssets[_index]);
                  final offsetAnimation = Tween<Offset>(
                    begin: isIncoming
                        ? const Offset(0, 1)
                        : const Offset(0, -1),
                    end: Offset.zero,
                  ).animate(animation);
                  return ClipRect(
                    child: SlideTransition(
                      position: offsetAnimation,
                      child: child,
                    ),
                  );
                },
                child: Image.asset(
                  _chatBannerAssets[_index],
                  key: ValueKey(_chatBannerAssets[_index]),
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatRoomTileSelection extends ConsumerWidget {
  const _ChatRoomTileSelection({
    super.key,
    required this.room,
    required this.mobileLayout,
    required this.onTap,
    required this.onDoubleTap,
    required this.onContextMenu,
  });

  final ChatRoom room;
  final bool mobileLayout;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset> onContextMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSelected = ref.watch(
      focusedChatRoomIdProvider.select((roomId) => roomId == room.id),
    );
    return _ChatRoomTile(
      room: room,
      isSelected: isSelected,
      mobileLayout: mobileLayout,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onContextMenu: onContextMenu,
    );
  }
}

class _ChatRoomTile extends StatelessWidget {
  const _ChatRoomTile({
    required this.room,
    required this.isSelected,
    required this.mobileLayout,
    required this.onTap,
    required this.onDoubleTap,
    required this.onContextMenu,
  });

  final ChatRoom room;
  final bool isSelected;
  final bool mobileLayout;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset> onContextMenu;

  @override
  Widget build(BuildContext context) {
    final background = isSelected ? const Color(0xFFEFEFEF) : Colors.white;

    if (mobileLayout) {
      return Material(
        color: background,
        child: InkWell(
          onTap: onTap,
          onLongPress: () => onContextMenu(Offset.zero),
          splashColor: const Color(0xFFE6E6E6),
          highlightColor: const Color(0xFFEFEFEF),
          child: _buildContent(),
        ),
      );
    }

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (event.buttons == kPrimaryButton) {
          onTap();
        }
      },
      child: Material(
        color: background,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          onTap: () {},
          onDoubleTap: onDoubleTap,
          onSecondaryTapDown: (details) {
            onTap();
            onContextMenu(details.globalPosition);
          },
          hoverColor: const Color(0xFFEFEFEF),
          highlightColor: const Color(0xFFEFEFEF),
          splashColor: Colors.transparent,
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StackedAvatars(room: room),
          const SizedBox(width: 14),
          Expanded(
            child: SizedBox(
              height: 52,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    right: 68,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _RoomTitleLine(room: room),
                        const SizedBox(height: 3),
                        _RoomPreviewText(room: room, maxLines: 2),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 1,
                    right: 0,
                    child: Text(
                      room.time,
                      style: const TextStyle(
                        color: Color(0xFF747474),
                        fontSize: 11,
                        height: 1.1,
                      ),
                    ),
                  ),
                  if (room.unreadCount > 0)
                    Positioned(
                      top: 25,
                      right: 0,
                      child: _UnreadBadge(
                        key: ValueKey('unread-badge-${room.id}'),
                        count: room.unreadCount,
                        mention: room.hasUnreadMention,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomPreviewText extends StatelessWidget {
  const _RoomPreviewText({required this.room, required this.maxLines});

  final ChatRoom room;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final preview = normalizeChatRoomPreview(room.preview);
    final stickerId = _previewStickerId(preview);
    if (stickerId != null && !room.previewIsSpoiler) {
      return Row(
        children: [
          _ChatListStickerPreview(stickerId: stickerId),
          const SizedBox(width: 5),
          const Expanded(
            child: Text(
              '\uC774\uBAA8\uD2F0\uCF58',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(0xFF555D66),
                fontSize: 12,
                height: 1.18,
              ),
            ),
          ),
        ],
      );
    }
    final leadingIcon = _previewLeadingIcon(preview);
    final text = Text(
      preview,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: const Color(0xFF555D66),
        fontSize: 12,
        height: maxLines > 1 ? 1.18 : null,
      ),
    );
    if (!room.previewIsSpoiler || preview.isEmpty) {
      if (leadingIcon == null) {
        return text;
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(leadingIcon, size: 13, color: const Color(0xFF6A737D)),
          ),
          const SizedBox(width: 3),
          Expanded(child: text),
        ],
      );
    }
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 3.2, sigmaY: 3.2),
        child: text,
      ),
    );
  }
}

const _previewStickerTokenPrefix = '[[AVA_STICKER:';
const _previewStickerTokenSuffix = ']]';

String? _previewStickerId(String preview) {
  final trimmed = preview.trim();
  if (!trimmed.startsWith(_previewStickerTokenPrefix) ||
      !trimmed.endsWith(_previewStickerTokenSuffix)) {
    return null;
  }
  final stickerId = trimmed.substring(
    _previewStickerTokenPrefix.length,
    trimmed.length - _previewStickerTokenSuffix.length,
  );
  return stickerId.isEmpty ? null : stickerId;
}

class _ChatListStickerPreview extends StatelessWidget {
  const _ChatListStickerPreview({required this.stickerId});

  final String stickerId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: Image.asset(
        _previewStickerAssetPath(stickerId),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) =>
            CustomPaint(painter: _ChatListStickerPainter(stickerId)),
      ),
    );
  }
}

String _previewStickerAssetPath(String stickerId) {
  final raw = RegExp(r'(\d+)$').firstMatch(stickerId)?.group(1);
  final number = (int.tryParse(raw ?? '1') ?? 1).clamp(1, 30);
  return 'assets/images/AVA_IMG/emoticon/kakaofreinds/'
      'emoticon_${number.toString().padLeft(2, '0')}.gif';
}

class _ChatListStickerPainter extends CustomPainter {
  const _ChatListStickerPainter(this.stickerId);

  final String stickerId;

  int get _variant {
    final raw = RegExp(r'(\d+)$').firstMatch(stickerId)?.group(1);
    return (int.tryParse(raw ?? '1') ?? 1) % 6;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.34;
    final variant = _variant;

    paint.color = const Color(0xFFFFB642);
    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(
      center + Offset(-radius * 0.72, -radius * 0.72),
      radius * 0.24,
      paint,
    );
    canvas.drawCircle(
      center + Offset(radius * 0.72, -radius * 0.72),
      radius * 0.24,
      paint,
    );

    paint.color = const Color(0xFF3A2718).withValues(alpha: 0.12);
    canvas.drawCircle(
      center + Offset(-radius * 0.72, -radius * 0.72),
      radius * 0.12,
      paint,
    );
    canvas.drawCircle(
      center + Offset(radius * 0.72, -radius * 0.72),
      radius * 0.12,
      paint,
    );

    paint.color = const Color(0xFF3A2718);
    canvas.drawCircle(
      center + Offset(-radius * 0.35, -radius * 0.15),
      radius * 0.09,
      paint,
    );
    canvas.drawCircle(
      center + Offset(radius * 0.35, -radius * 0.15),
      radius * 0.09,
      paint,
    );

    final muzzle = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center + Offset(0, radius * 0.12),
        width: radius * 0.62,
        height: radius * 0.4,
      ),
      Radius.circular(radius * 0.2),
    );
    paint.color = const Color(0xFFFFE5B3);
    canvas.drawRRect(muzzle, paint);

    paint.color = const Color(0xFF3A2718);
    canvas.drawCircle(center + Offset(0, radius * 0.05), radius * 0.075, paint);
    final mouth = Path()
      ..moveTo(center.dx - radius * 0.18, center.dy + radius * 0.2)
      ..quadraticBezierTo(
        center.dx,
        center.dy + radius * 0.35,
        center.dx + radius * 0.18,
        center.dy + radius * 0.2,
      );
    canvas.drawPath(
      mouth,
      Paint()
        ..isAntiAlias = true
        ..color = const Color(0xFF3A2718)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    if (variant == 0 || variant == 3) {
      paint.color = const Color(0xFFFF6E8D);
      canvas.drawCircle(
        center + Offset(-radius * 0.52, radius * 0.08),
        radius * 0.11,
        paint,
      );
      canvas.drawCircle(
        center + Offset(radius * 0.52, radius * 0.08),
        radius * 0.11,
        paint,
      );
    } else if (variant == 1 || variant == 4) {
      final heart = Path()
        ..moveTo(center.dx + radius * 0.72, center.dy - radius * 0.5)
        ..cubicTo(
          center.dx + radius * 0.56,
          center.dy - radius * 0.66,
          center.dx + radius * 0.34,
          center.dy - radius * 0.36,
          center.dx + radius * 0.72,
          center.dy - radius * 0.18,
        )
        ..cubicTo(
          center.dx + radius * 1.08,
          center.dy - radius * 0.36,
          center.dx + radius * 0.88,
          center.dy - radius * 0.66,
          center.dx + radius * 0.72,
          center.dy - radius * 0.5,
        );
      paint.color = const Color(0xFFFF5A76);
      canvas.drawPath(heart, paint);
    } else if (variant == 5) {
      paint.color = const Color(0xFF4C63D9);
      canvas.drawCircle(
        center + Offset(-radius * 0.82, -radius * 0.38),
        radius * 0.08,
        paint,
      );
      canvas.drawCircle(
        center + Offset(radius * 0.82, radius * 0.34),
        radius * 0.08,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChatListStickerPainter oldDelegate) {
    return oldDelegate.stickerId != stickerId;
  }
}

IconData? _previewLeadingIcon(String preview) {
  if (preview.startsWith('[\uC774\uBBF8\uC9C0]')) {
    return Icons.image_outlined;
  }
  if (preview.startsWith('[\uB3D9\uC601\uC0C1]')) {
    return Icons.movie_outlined;
  }
  if (preview.startsWith('[\uD30C\uC77C]')) {
    return Icons.insert_drive_file_outlined;
  }
  return null;
}

class _RoomTitleLine extends StatelessWidget {
  const _RoomTitleLine({required this.room});

  final ChatRoom room;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            room.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              height: 1.12,
            ),
          ),
        ),
        if (!room.isDirectChat && room.displayParticipantCount > 1) ...[
          const SizedBox(width: 4),
          Text(
            '${room.displayParticipantCount}',
            style: const TextStyle(
              color: Color(0xFF8A8A8A),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.12,
            ),
          ),
        ],
        if (room.isPinned) ...[
          const SizedBox(width: 4),
          const Icon(Icons.push_pin, size: 13, color: Color(0xFF999999)),
        ],
        if (room.isMuted) ...[
          const SizedBox(width: 4),
          const Icon(
            Icons.notifications_off,
            size: 13,
            color: Color(0xFF8F8F8F),
          ),
        ],
      ],
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count, this.mention = false, super.key});

  final int count;
  final bool mention;

  @override
  Widget build(BuildContext context) {
    const size = 19.0;
    final label = mention ? '@$count' : '$count';
    final horizontalPadding = label.length > 1 ? 5.0 : 0.0;

    return Container(
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFF4B2B),
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class _StackedAvatars extends StatelessWidget {
  const _StackedAvatars({required this.room});

  final ChatRoom room;

  static const _fallbackColors = [
    Color(0xFF8FC7D5),
    Color(0xFFA6C6EE),
    Color(0xFFDDE8A5),
    Color(0xFF9FB2D9),
  ];

  @override
  Widget build(BuildContext context) {
    final avatarCount = room.isDirectChat
        ? 1
        : room.displayParticipantCount.clamp(1, 4);

    if (avatarCount == 1) {
      return SizedBox(
        width: 46,
        height: 52,
        child: Align(
          alignment: Alignment.topCenter,
          child: ProfileAvatar(
            key: ValueKey('chat-room-avatar-${room.id}-0'),
            profile: room.members.first,
            size: 42,
          ),
        ),
      );
    }

    final visible = [
      for (var i = 0; i < avatarCount; i++)
        i < room.members.length
            ? room.members[i]
            : PersonProfile(
                name: '${room.title} $i',
                color: _fallbackColors[i % _fallbackColors.length],
              ),
    ];

    return SizedBox(
      width: 46,
      height: 52,
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i.isEven ? 0 : 22,
              top: i < 2 ? 0 : 22,
              child: ProfileAvatar(
                key: ValueKey('chat-room-avatar-${room.id}-$i'),
                profile: visible[i],
                size: 22,
              ),
            ),
        ],
      ),
    );
  }
}
