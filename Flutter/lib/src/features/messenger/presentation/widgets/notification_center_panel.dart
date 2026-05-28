import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../platform/window_control.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../calendar/application/calendar_controller.dart';
import '../../../notification/data/notification_api.dart';
import '../../application/notification_center_controller.dart';
import '../../data/chat_api.dart';
import '../../domain/messenger_models.dart';
import '../messenger_page.dart';
import 'profile_avatar.dart';

enum _NotificationFilter { all, requested, checked }

enum _NotificationSortMode { latest, mentionCount }

class NotificationCenterPanel extends ConsumerStatefulWidget {
  const NotificationCenterPanel({super.key});

  @override
  ConsumerState<NotificationCenterPanel> createState() =>
      _NotificationCenterPanelState();
}

class _NotificationCenterPanelState
    extends ConsumerState<NotificationCenterPanel> {
  final GlobalKey _editButtonKey = GlobalKey();
  _NotificationFilter _filter = _NotificationFilter.all;
  _NotificationSortMode _sortMode = _NotificationSortMode.latest;
  bool _editMenuOpen = false;

  @override
  void initState() {
    super.initState();
    final cache = ref.read(notificationCenterCacheProvider);
    if (!cache.hasLoaded && !cache.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_load(silent: false));
      });
    }
  }

  Future<void> _load({bool silent = false}) async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      ref
          .read(notificationCenterCacheProvider.notifier)
          .setNotifications(const []);
      ref
          .read(notificationCenterCacheProvider.notifier)
          .setAppNotifications(const []);
      return;
    }

    ref
        .read(notificationCenterCacheProvider.notifier)
        .beginLoading(silent: silent);

    try {
      final api = ref.read(chatApiProvider);
      final notifications = await api.mentionNotifications(
        accessToken: session.accessToken,
        status: 'all',
        limit: 120,
      );
      final appNotifications = await ref
          .read(notificationApiProvider)
          .list(accessToken: session.accessToken);
      if (!mounted) {
        return;
      }
      ref
          .read(notificationCenterCacheProvider.notifier)
          .setNotifications(notifications);
      ref
          .read(notificationCenterCacheProvider.notifier)
          .setAppNotifications(
            appNotifications.items,
            unreadCount: appNotifications.unreadCount,
          );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ref.read(notificationCenterCacheProvider.notifier).setError(error);
    }
  }

  List<_MentionNotificationItem> _visibleMentionItems(
    List<_MentionNotificationItem> items,
  ) {
    return switch (_filter) {
      _NotificationFilter.all || _NotificationFilter.requested =>
        items
            .where((item) => !item.notification.checked)
            .toList(growable: false),
      _NotificationFilter.checked =>
        items
            .where((item) => item.notification.checked)
            .toList(growable: false),
    };
  }

  List<AzoomVoiceStartNotification> _visibleAzoomItems(
    List<AzoomVoiceStartNotification> items,
  ) {
    final activeItems = items.where((item) => item.active);
    return switch (_filter) {
      _NotificationFilter.all => activeItems.toList(growable: false),
      _NotificationFilter.requested =>
        activeItems.where((item) => !item.checked).toList(growable: false),
      _NotificationFilter.checked =>
        activeItems.where((item) => item.checked).toList(growable: false),
    };
  }

  List<NotificationDto> _visibleAppItems(List<NotificationDto> items) {
    return switch (_filter) {
      _NotificationFilter.all => items,
      _NotificationFilter.requested =>
        items.where((item) => !item.read).toList(growable: false),
      _NotificationFilter.checked =>
        items.where((item) => item.read).toList(growable: false),
    };
  }

  int _requestedCount(
    List<AzoomVoiceStartNotification> azoomItems,
    List<_MentionNotificationItem> mentionItems,
    List<NotificationDto> appItems,
  ) {
    return mentionItems.where((item) => !item.notification.checked).length +
        azoomItems.where((item) => item.active && !item.checked).length +
        appItems.where((item) => !item.read).length;
  }

  List<_NotificationListItem> _sortedVisibleItems(
    List<AzoomVoiceStartNotification> azoomNotifications,
    List<_MentionNotificationItem> mentionItems,
    List<NotificationDto> appNotifications,
  ) {
    final visibleMentionItems = _visibleMentionItems(mentionItems);
    final mentionCountsByRoom = <String, int>{};
    for (final item in visibleMentionItems) {
      mentionCountsByRoom[item.room.id] =
          (mentionCountsByRoom[item.room.id] ?? 0) + 1;
    }
    final visibleItems = [
      for (final item in _visibleAzoomItems(azoomNotifications))
        _NotificationListItem.azoom(item),
      for (final item in visibleMentionItems)
        _NotificationListItem.mention(item),
      for (final item in _visibleAppItems(appNotifications))
        _NotificationListItem.app(item),
    ];
    visibleItems.sort((a, b) {
      if (_sortMode == _NotificationSortMode.mentionCount) {
        final countCompare = b
            .mentionCount(mentionCountsByRoom)
            .compareTo(a.mentionCount(mentionCountsByRoom));
        if (countCompare != 0) {
          return countCompare;
        }
      }
      return b.sortAt.compareTo(a.sortAt);
    });
    return visibleItems;
  }

  Future<void> _showEditMenu() async {
    if (_editMenuOpen) {
      return;
    }
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final anchorBox =
        _editButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (anchorBox == null) {
      return;
    }
    final topLeft = anchorBox.localToGlobal(Offset.zero, ancestor: overlay);
    setState(() => _editMenuOpen = true);
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
            '${_sortMode == _NotificationSortMode.latest ? '\u2713 ' : ''}\uCD5C\uC2E0\uC21C',
          ),
        ),
        PopupMenuItem(
          value: 'mention-count',
          child: Text(
            '${_sortMode == _NotificationSortMode.mentionCount ? '\u2713 ' : ''}\uBA58\uC158 \uAC1C\uC218 \uC21C',
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'read-all',
          child: Text('\uBAA8\uB450 \uC77D\uC74C \uCC98\uB9AC'),
        ),
      ],
    );
    if (mounted) {
      setState(() => _editMenuOpen = false);
    }
    if (!mounted || result == null) {
      return;
    }
    switch (result) {
      case 'latest':
        setState(() => _sortMode = _NotificationSortMode.latest);
      case 'mention-count':
        setState(() => _sortMode = _NotificationSortMode.mentionCount);
      case 'read-all':
        await _markAllRead();
    }
  }

  Future<void> _markAllRead() async {
    final session = ref.read(authControllerProvider).value?.session;
    final items = [
      for (final notification
          in ref.read(notificationCenterCacheProvider).notifications)
        _MentionNotificationItem.fromDto(notification),
    ];
    final unreadMentionItems = [
      for (final item in items)
        if (!item.notification.checked && item.notification.id.isNotEmpty) item,
    ];
    if (session != null && session.accessToken.isNotEmpty) {
      try {
        final api = ref.read(chatApiProvider);
        for (final item in unreadMentionItems) {
          final checked = await api.markMentionNotificationChecked(
            accessToken: session.accessToken,
            notificationId: item.notification.id,
          );
          ref.read(notificationCenterCacheProvider.notifier).upsert(checked);
        }
        final appResult = await ref
            .read(notificationApiProvider)
            .markAllRead(accessToken: session.accessToken);
        ref
            .read(notificationCenterCacheProvider.notifier)
            .setAppNotifications(
              appResult.items,
              unreadCount: appResult.unreadCount,
            );
        await ref
            .read(chatRoomsProvider.notifier)
            .refreshFromServer(force: true);
      } on Object catch (error) {
        ref.read(notificationCenterCacheProvider.notifier).setError(error);
      }
    }
    for (final item in ref.read(azoomVoiceStartNotificationsProvider)) {
      if (item.active && !item.checked) {
        ref
            .read(azoomVoiceStartNotificationsProvider.notifier)
            .markChecked(item.id);
      }
    }
  }

  Future<void> _openNotification(_MentionNotificationItem item) async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session != null &&
        session.accessToken.isNotEmpty &&
        item.notification.id.isNotEmpty &&
        !item.notification.checked) {
      try {
        final checked = await ref
            .read(chatApiProvider)
            .markMentionNotificationChecked(
              accessToken: session.accessToken,
              notificationId: item.notification.id,
            );
        ref.read(notificationCenterCacheProvider.notifier).upsert(checked);
      } on Object {
        // Navigation is still useful if the read-state request is delayed.
      }
    }

    ref.read(activeMessengerTabProvider.notifier).setTab(MessengerTab.chats);
    ref.read(focusedChatRoomIdProvider.notifier).focus(item.room);
    ref
        .read(focusedChatMessageIdProvider.notifier)
        .focus(item.notification.messageId);
    ref.read(selectedChatRoomProvider.notifier).open(item.room);
    await WindowControl.expandMessenger();
  }

  Future<void> _openAzoomVoiceNotification(
    AzoomVoiceStartNotification item,
  ) async {
    if (!item.checked) {
      ref
          .read(azoomVoiceStartNotificationsProvider.notifier)
          .markChecked(item.id);
    }
    ref.read(activeMessengerTabProvider.notifier).setTab(MessengerTab.azoom);
    ref.read(azoomPendingVoiceEntryProvider.notifier).open(item.channelId);
    await WindowControl.openAzoomMessenger();
    await WindowControl.showMessengerWindow();
  }

  Future<void> _openAppNotification(NotificationDto item) async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session != null &&
        session.accessToken.isNotEmpty &&
        item.id.isNotEmpty &&
        !item.read) {
      try {
        final checked = await ref
            .read(notificationApiProvider)
            .markRead(
              accessToken: session.accessToken,
              notificationId: item.id,
            );
        ref.read(notificationCenterCacheProvider.notifier).upsertApp(checked);
      } on Object {
        // The target page is still useful even if read-state sync is delayed.
      }
    }
    if (item.sourceType == 'CALENDAR_EVENT') {
      ref
          .read(activeMessengerTabProvider.notifier)
          .setTab(MessengerTab.calendar);
      unawaited(ref.read(calendarControllerProvider.notifier).refresh());
      await WindowControl.expandMessenger();
      if (mounted) {
        context.go('/calendar');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(notificationCenterRevisionProvider, (_, _) {
      unawaited(_load(silent: true));
    });
    final notificationCache = ref.watch(notificationCenterCacheProvider);
    final mentionItems = [
      for (final notification in notificationCache.notifications)
        _MentionNotificationItem.fromDto(notification),
    ];
    final appNotifications = notificationCache.appNotifications;
    final azoomNotifications = ref.watch(azoomVoiceStartNotificationsProvider);
    final requestedCount = _requestedCount(
      azoomNotifications,
      mentionItems,
      appNotifications,
    );
    final visibleItems = _sortedVisibleItems(
      azoomNotifications,
      mentionItems,
      appNotifications,
    );
    final showLoading =
        notificationCache.loading &&
        !notificationCache.hasLoaded &&
        mentionItems.isEmpty;
    final showError =
        notificationCache.error != null &&
        !notificationCache.hasLoaded &&
        visibleItems.isEmpty;
    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(19, 38, 29, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '알림센터',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                        height: 1.1,
                      ),
                    ),
                  ),
                  TextButton(
                    key: _editButtonKey,
                    onPressed: _showEditMenu,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF8F8F8F),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(40, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      '편집',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  _FilterChipButton(
                    label: '전체',
                    active: _filter == _NotificationFilter.all,
                    onTap: () =>
                        setState(() => _filter = _NotificationFilter.all),
                  ),
                  const SizedBox(width: 10),
                  _FilterChipButton(
                    label: '확인요청',
                    active: _filter == _NotificationFilter.requested,
                    badge: requestedCount > 0 ? requestedCount : null,
                    onTap: () =>
                        setState(() => _filter = _NotificationFilter.requested),
                  ),
                  const SizedBox(width: 10),
                  _FilterChipButton(
                    label: '확인함',
                    active: _filter == _NotificationFilter.checked,
                    disabledLook: _filter != _NotificationFilter.checked,
                    onTap: () =>
                        setState(() => _filter = _NotificationFilter.checked),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 17),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                '알림 $requestedCount개',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFE3E3E3)),
            Expanded(
              child: showLoading
                  ? const Center(
                      key: ValueKey('notification-center-loading'),
                      child: SizedBox.square(
                        dimension: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Color(0xFF4663CF),
                        ),
                      ),
                    )
                  : showError
                  ? _NotificationEmptyState(
                      message: '알림을 불러오지 못했습니다.',
                      onRetry: _load,
                    )
                  : visibleItems.isEmpty
                  ? const _NotificationEmptyState(message: '표시할 알림이 없습니다.')
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: visibleItems.length,
                      itemBuilder: (context, index) {
                        final item = visibleItems[index];
                        final mention = item.mention;
                        if (mention != null) {
                          return _MentionNotificationCard(
                            item: mention,
                            onTap: () => unawaited(_openNotification(mention)),
                          );
                        }
                        final azoom = item.azoom;
                        if (azoom != null) {
                          return _AzoomVoiceStartNotificationCard(
                            item: azoom,
                            onTap: () =>
                                unawaited(_openAzoomVoiceNotification(azoom)),
                          );
                        }
                        final app = item.app!;
                        return _AppNotificationCard(
                          item: app,
                          onTap: () => unawaited(_openAppNotification(app)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationListItem {
  const _NotificationListItem._({
    required this.sortAt,
    this.mention,
    this.azoom,
    this.app,
  });

  factory _NotificationListItem.mention(_MentionNotificationItem item) {
    return _NotificationListItem._(
      sortAt:
          item.notification.sentAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      mention: item,
    );
  }

  factory _NotificationListItem.azoom(AzoomVoiceStartNotification item) {
    return _NotificationListItem._(sortAt: item.startedAt, azoom: item);
  }

  factory _NotificationListItem.app(NotificationDto item) {
    return _NotificationListItem._(
      sortAt: item.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      app: item,
    );
  }

  final DateTime sortAt;
  final _MentionNotificationItem? mention;
  final AzoomVoiceStartNotification? azoom;
  final NotificationDto? app;

  int mentionCount(Map<String, int> countsByRoom) {
    final item = mention;
    if (item == null) {
      return 0;
    }
    return countsByRoom[item.room.id] ?? 1;
  }
}

class _MentionNotificationItem {
  const _MentionNotificationItem({
    required this.notification,
    required this.room,
    required this.sender,
  });

  factory _MentionNotificationItem.fromDto(
    ChatMentionNotificationDto notification,
  ) {
    final members = [
      for (final member in notification.roomMembers)
        personProfileFromDto(member),
    ];
    final sender = PersonProfile(
      id: notification.senderId.isEmpty ? null : notification.senderId,
      name: notification.senderName.isEmpty
          ? notification.roomTitle
          : notification.senderName,
      nickname: notification.senderNickname.isEmpty
          ? null
          : notification.senderNickname,
      color: avatarColorFromHex(notification.senderAvatarColor),
      imageUrl: notification.senderAvatarImageUrl.isEmpty
          ? null
          : notification.senderAvatarImageUrl,
    );
    final room = ChatRoom(
      id: notification.roomCode,
      title: notification.roomTitle,
      preview: notification.content,
      time: formatChatClockTime(notification.sentAt),
      members: members,
      participantCount: notification.participantCount,
      unreadCount: 0,
      hasUnreadMention: !notification.checked,
      lastActivityAt: notification.sentAt,
    );
    return _MentionNotificationItem(
      notification: notification,
      room: room,
      sender: sender,
    );
  }

  final ChatMentionNotificationDto notification;
  final ChatRoom room;
  final PersonProfile sender;
}

class _MentionNotificationCard extends StatelessWidget {
  const _MentionNotificationCard({required this.item, required this.onTap});

  final _MentionNotificationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final notification = item.notification;
    final mentionLabel = notification.mentionDisplayName.trim().isEmpty
        ? '@나'
        : '@${notification.mentionDisplayName.trim()}';
    final content = _mentionBody(notification.content, mentionLabel);
    return Material(
      color: const Color(0xFFFAFAFA),
      child: InkWell(
        onTap: onTap,
        splashColor: const Color(0xFFEAF5FF),
        highlightColor: const Color(0xFFEAF5FF),
        hoverColor: const Color(0xFFF0F6FC),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE5E5E5))),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 128),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 13, 17, 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 18,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                            children: [
                              TextSpan(text: item.sender.name),
                              const TextSpan(
                                text: ' · ',
                                style: TextStyle(
                                  color: Color(0xFF9B9B9B),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text:
                                    '${item.room.title} ${item.room.displayParticipantCount}',
                                style: const TextStyle(
                                  color: Color(0xFF9B9B9B),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          mentionLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF3269B4),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 17,
                            height: 1.24,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 13),
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time,
                              size: 18,
                              color: Color(0xFF9C9C9C),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _formatKoreanDateTime(notification.sentAt),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF333333),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: _NotificationRoomAvatar(room: item.room),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AzoomVoiceStartNotificationCard extends StatelessWidget {
  const _AzoomVoiceStartNotificationCard({
    required this.item,
    required this.onTap,
  });

  final AzoomVoiceStartNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFAFAFA),
      child: InkWell(
        onTap: onTap,
        splashColor: const Color(0xFFEAF5FF),
        highlightColor: const Color(0xFFEAF5FF),
        hoverColor: const Color(0xFFF0F6FC),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE5E5E5))),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 128),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 13, 17, 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AZOOM',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 18,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          '${item.channelName} 회의 시작',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF3269B4),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item.channelName} 음성채널 회의가 시작됐습니다.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 17,
                            height: 1.24,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 13),
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time,
                              size: 18,
                              color: Color(0xFF9C9C9C),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _formatKoreanDateTime(item.startedAt),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF333333),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 43,
                    height: 43,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFF8CC9DD),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.volume_up_rounded,
                      color: Colors.white,
                      size: 25,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppNotificationCard extends StatelessWidget {
  const _AppNotificationCard({required this.item, required this.onTap});

  final NotificationDto item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = item.sourceType == 'CALENDAR_EVENT'
        ? Icons.calendar_month_rounded
        : Icons.notifications_rounded;
    return Material(
      color: item.read ? const Color(0xFFFAFAFA) : const Color(0xFFF4F8FF),
      child: InkWell(
        onTap: onTap,
        splashColor: const Color(0xFFEAF5FF),
        highlightColor: const Color(0xFFEAF5FF),
        hoverColor: const Color(0xFFF0F6FC),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE5E5E5))),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 116),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 13, 17, 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title.isEmpty ? 'AVA 알림' : item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 18,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.body,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            height: 1.25,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time,
                              size: 17,
                              color: Color(0xFF9C9C9C),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                _formatKoreanDateTime(item.createdAt),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF333333),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 43,
                    height: 43,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFF4663CF),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationRoomAvatar extends StatelessWidget {
  const _NotificationRoomAvatar({required this.room});

  final ChatRoom room;

  @override
  Widget build(BuildContext context) {
    if (room.members.length <= 1) {
      final profile = room.members.isEmpty
          ? PersonProfile(name: room.title, color: const Color(0xFF8CC9DD))
          : room.members.first;
      return ProfileAvatar(profile: profile, size: 43);
    }
    final members = room.members.take(4).toList();
    return SizedBox(
      width: 43,
      height: 43,
      child: Stack(
        children: [
          for (var i = 0; i < members.length; i++)
            Positioned(
              left: i.isEven ? 0 : 21,
              top: i < 2 ? 0 : 21,
              child: ProfileAvatar(profile: members[i], size: 22),
            ),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.active,
    required this.onTap,
    this.badge,
    this.disabledLook = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final int? badge;
  final bool disabledLook;

  @override
  Widget build(BuildContext context) {
    final bg = active ? Colors.black : Colors.white;
    final borderColor = active ? Colors.black : const Color(0xFFD2D2D2);
    final fg = active
        ? Colors.white
        : disabledLook
        ? const Color(0xFF9D9D9D)
        : const Color(0xFF222222);
    return Material(
      color: bg,
      shape: StadiumBorder(side: BorderSide(color: borderColor, width: 1.3)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 40,
          padding: EdgeInsets.only(left: 20, right: badge == null ? 20 : 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  width: 19,
                  height: 19,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE86161),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$badge',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationEmptyState extends StatelessWidget {
  const _NotificationEmptyState({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF777777),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ],
      ),
    );
  }
}

String _mentionBody(String content, String mentionLabel) {
  var body = content.trim();
  if (body.startsWith(mentionLabel)) {
    body = body.substring(mentionLabel.length).trim();
  }
  return body.isEmpty ? content.trim() : body;
}

String _formatKoreanDateTime(DateTime? value) {
  final date = (value ?? DateTime.now()).toLocal();
  const weekdays = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
  final period = date.hour < 12 ? '오전' : '오후';
  final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.year}. ${date.month}. ${date.day}. '
      '${weekdays[date.weekday - 1]} $period $hour12:$minute';
}
