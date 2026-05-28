import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_api.dart';
import '../../notification/data/notification_api.dart';

final notificationCenterRevisionProvider =
    NotifierProvider<NotificationCenterRevision, int>(
      NotificationCenterRevision.new,
    );

final notificationCenterCacheProvider =
    NotifierProvider<NotificationCenterCache, NotificationCenterCacheState>(
      NotificationCenterCache.new,
    );

final azoomVoiceStartNotificationsProvider =
    NotifierProvider<
      AzoomVoiceStartNotifications,
      List<AzoomVoiceStartNotification>
    >(AzoomVoiceStartNotifications.new);

final azoomPendingVoiceEntryProvider =
    NotifierProvider<AzoomPendingVoiceEntry, String?>(
      AzoomPendingVoiceEntry.new,
    );

class NotificationCenterRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    state += 1;
  }
}

class NotificationCenterCacheState {
  const NotificationCenterCacheState({
    this.notifications = const [],
    this.appNotifications = const [],
    this.appUnreadCount = 0,
    this.hasLoaded = false,
    this.loading = false,
    this.error,
  });

  final List<ChatMentionNotificationDto> notifications;
  final List<NotificationDto> appNotifications;
  final int appUnreadCount;
  final bool hasLoaded;
  final bool loading;
  final Object? error;

  NotificationCenterCacheState copyWith({
    List<ChatMentionNotificationDto>? notifications,
    List<NotificationDto>? appNotifications,
    int? appUnreadCount,
    bool? hasLoaded,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) {
    return NotificationCenterCacheState(
      notifications: notifications ?? this.notifications,
      appNotifications: appNotifications ?? this.appNotifications,
      appUnreadCount: appUnreadCount ?? this.appUnreadCount,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class NotificationCenterCache extends Notifier<NotificationCenterCacheState> {
  @override
  NotificationCenterCacheState build() => const NotificationCenterCacheState();

  void beginLoading({bool silent = false}) {
    if (!ref.mounted) {
      return;
    }
    state = state.copyWith(
      loading: !silent && !state.hasLoaded,
      clearError: true,
    );
  }

  void setNotifications(List<ChatMentionNotificationDto> notifications) {
    if (!ref.mounted) {
      return;
    }
    state = state.copyWith(
      notifications: List<ChatMentionNotificationDto>.unmodifiable(
        notifications,
      ),
      hasLoaded: true,
      loading: false,
      clearError: true,
    );
  }

  void setAppNotifications(
    List<NotificationDto> notifications, {
    int? unreadCount,
  }) {
    if (!ref.mounted) {
      return;
    }
    state = state.copyWith(
      appNotifications: List<NotificationDto>.unmodifiable(notifications),
      appUnreadCount:
          unreadCount ??
          notifications.where((notification) => !notification.read).length,
      hasLoaded: true,
      loading: false,
      clearError: true,
    );
  }

  void setError(Object error) {
    if (!ref.mounted) {
      return;
    }
    state = state.copyWith(loading: false, error: error);
  }

  void upsert(ChatMentionNotificationDto notification) {
    if (!ref.mounted) {
      return;
    }
    final next = <ChatMentionNotificationDto>[];
    var inserted = false;
    for (final item in state.notifications) {
      if (item.id == notification.id) {
        next.add(notification);
        inserted = true;
      } else {
        next.add(item);
      }
    }
    if (!inserted) {
      next.insert(0, notification);
    }
    setNotifications(next);
  }

  void upsertApp(NotificationDto notification) {
    if (!ref.mounted) {
      return;
    }
    final next = <NotificationDto>[];
    var inserted = false;
    for (final item in state.appNotifications) {
      if (item.id == notification.id) {
        next.add(notification);
        inserted = true;
      } else {
        next.add(item);
      }
    }
    if (!inserted) {
      next.insert(0, notification);
    }
    setAppNotifications(next);
  }
}

class AzoomVoiceStartNotification {
  const AzoomVoiceStartNotification({
    required this.id,
    required this.channelId,
    required this.channelName,
    required this.roomName,
    required this.startedAt,
    required this.checked,
    required this.active,
  });

  final String id;
  final String channelId;
  final String channelName;
  final String roomName;
  final DateTime startedAt;
  final bool checked;
  final bool active;

  AzoomVoiceStartNotification copyWith({
    String? channelName,
    String? roomName,
    DateTime? startedAt,
    bool? checked,
    bool? active,
  }) {
    return AzoomVoiceStartNotification(
      id: id,
      channelId: channelId,
      channelName: channelName ?? this.channelName,
      roomName: roomName ?? this.roomName,
      startedAt: startedAt ?? this.startedAt,
      checked: checked ?? this.checked,
      active: active ?? this.active,
    );
  }
}

class AzoomVoiceStartNotifications
    extends Notifier<List<AzoomVoiceStartNotification>> {
  @override
  List<AzoomVoiceStartNotification> build() => const [];

  void upsertStarted({
    required String channelId,
    required String channelName,
    required String roomName,
    DateTime? startedAt,
  }) {
    final started = startedAt ?? DateTime.now();
    final id = 'azoom-voice-active:$channelId';
    var updated = false;
    final next = [
      for (final item in state)
        if (item.id == id)
          item.copyWith(
            channelName: channelName,
            roomName: roomName,
            startedAt: item.active ? item.startedAt : started,
            active: true,
          )
        else
          item,
    ];
    updated = next.any((item) => item.id == id);
    if (updated) {
      state = next;
      ref.read(notificationCenterRevisionProvider.notifier).bump();
      return;
    }
    state = [
      AzoomVoiceStartNotification(
        id: id,
        channelId: channelId,
        channelName: channelName,
        roomName: roomName,
        startedAt: started,
        checked: false,
        active: true,
      ),
      ...state,
    ];
    ref.read(notificationCenterRevisionProvider.notifier).bump();
  }

  void removeChannel(String channelId) {
    final next = [
      for (final item in state)
        if (item.channelId != channelId) item,
    ];
    if (next.length == state.length) {
      return;
    }
    state = next;
    ref.read(notificationCenterRevisionProvider.notifier).bump();
  }

  void clear() {
    if (state.isEmpty) {
      return;
    }
    state = const [];
    ref.read(notificationCenterRevisionProvider.notifier).bump();
  }

  void markChecked(String id) {
    state = [
      for (final item in state)
        item.id == id ? item.copyWith(checked: true) : item,
    ];
    ref.read(notificationCenterRevisionProvider.notifier).bump();
  }
}

class AzoomPendingVoiceEntry extends Notifier<String?> {
  @override
  String? build() => null;

  void open(String channelId) {
    state = channelId;
  }

  void clear() {
    state = null;
  }
}
