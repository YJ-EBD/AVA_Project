import 'dart:convert';
import 'dart:io';

import 'package:ava_flutter/src/config/app_config.dart';
import 'package:ava_flutter/src/config/app_version.dart';
import 'package:ava_flutter/src/features/auth/application/auth_controller.dart';
import 'package:ava_flutter/src/features/auth/data/auth_models.dart';
import 'package:ava_flutter/src/features/messenger/data/chat_api.dart';
import 'package:ava_flutter/src/features/messenger/domain/messenger_models.dart';
import 'package:ava_flutter/src/features/messenger/presentation/messenger_page.dart';
import 'package:ava_flutter/src/features/messenger/presentation/widgets/chats_panel.dart';
import 'package:ava_flutter/src/features/messenger/presentation/widgets/chat_room_panel.dart';
import 'package:ava_flutter/src/features/messenger/presentation/widgets/notification_center_panel.dart';
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _loopCount = 120;
const String _setupCompletedVersionKey = 'ava.app_setup.completed_version.v1';

const PersonProfile _currentUser = PersonProfile(
  id: 'perf-current-user',
  name: 'Perf Current',
  color: Color(0xFF4663CF),
  email: 'perf-current@ava.local',
  companyName: 'ABBA-S',
);

const PersonProfile _otherUser = PersonProfile(
  id: 'perf-other-user',
  name: 'Perf Other',
  color: Color(0xFF68A878),
  email: 'perf-other@ava.local',
  companyName: 'ABBA-S',
);

final List<ChatRoom> _rooms = List<ChatRoom>.generate(
  12,
  (index) => ChatRoom(
    id: 'perf-room-${index + 1}',
    title: 'Perf Room ${index + 1}',
    preview: 'Cached local message',
    time: '12:${(index + 10).toString().padLeft(2, '0')}',
    participantCount: 2,
    members: const [_currentUser, _otherUser],
    lastActivityAt: DateTime(2026, 5, 27, 12, index),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop chat switching and hover are immediate for 120 loops', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _setupCompletedVersionKey: AppVersion.name,
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 760);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _PerfChatApi();
    final container = _perfContainer(api);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
    _primeLocalMessageCache(container);
    container
        .read(activeMessengerTabProvider.notifier)
        .setTab(MessengerTab.chats);
    container.read(selectedChatRoomProvider.notifier).open(_rooms.first);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _DesktopChatPerfHarness()),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.text(_rooms.first.title).evaluate().isNotEmpty,
      description: 'chat room list',
    );

    final switchDurations = <int>[];
    for (var loop = 0; loop < _loopCount; loop++) {
      final room = _rooms[loop % _rooms.length];
      final stopwatch = Stopwatch()..start();
      container
          .read(activeMessengerTabProvider.notifier)
          .setTab(MessengerTab.chats);
      container.read(selectedChatRoomProvider.notifier).open(room);
      await tester.pump();
      stopwatch.stop();
      switchDurations.add(stopwatch.elapsedMicroseconds);
      expect(container.read(selectedChatRoomProvider)?.id, room.id);
    }

    final navigationDurations = <int>[];
    for (var loop = 0; loop < _loopCount; loop++) {
      final stopwatch = Stopwatch()..start();
      container
          .read(activeMessengerTabProvider.notifier)
          .setTab(MessengerTab.notifications);
      await tester.pump();
      container
          .read(activeMessengerTabProvider.notifier)
          .setTab(MessengerTab.chats);
      await tester.pump();
      stopwatch.stop();
      navigationDurations.add(stopwatch.elapsedMicroseconds);
    }

    final hoverDurations = <int>[];
    final visibleHoverRooms = _rooms.reversed.take(6).toList();
    for (var loop = 0; loop < _loopCount; loop++) {
      final room = visibleHoverRooms[loop % visibleHoverRooms.length];
      final target = find.text(room.title).first;
      expect(target, findsOneWidget);
      final position = tester.getCenter(target);
      final stopwatch = Stopwatch()..start();
      await tester.sendEventToBinding(PointerHoverEvent(position: position));
      await tester.pump();
      stopwatch.stop();
      hoverDurations.add(stopwatch.elapsedMicroseconds);
    }

    final log = {
      'scenario': 'desktop_chat_switching_hover_navigation',
      'loopsPerScenario': _loopCount,
      'apiMessageCalls': api.messagesCalls,
      'apiMessagesBeforeCalls': api.messagesBeforeCalls,
      'switch': _durationStats(switchDurations),
      'navigation': _durationStats(navigationDurations),
      'hover': _durationStats(hoverDurations),
    };
    _writePerfLog('desktop_chat_switching_hover_navigation', log);

    expect(_averageMs(switchDurations), lessThan(90));
    expect(_averageMs(navigationDurations), lessThan(90));
    expect(_averageMs(hoverDurations), lessThan(20));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('chat scroll-up pagination stays immediate for 120 loops', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _setupCompletedVersionKey: AppVersion.name,
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(780, 760);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _PerfChatApi();
    final container = _perfContainer(api);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ChatRoomPanel(
              room: _rooms.first,
              onClose: () {},
              mobileLayout: false,
            ),
          ),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.text('perf-room-1 message 239').evaluate().isNotEmpty,
      description: 'initial latest chat messages',
    );

    final scrollable = find.byKey(const ValueKey('chat-messages-list'));
    expect(scrollable, findsOneWidget);
    final scrollDurations = <int>[];
    for (var loop = 0; loop < _loopCount; loop++) {
      final stopwatch = Stopwatch()..start();
      await tester.drag(scrollable, const Offset(0, -360));
      await tester.pump();
      await tester.drag(scrollable, const Offset(0, 420));
      await tester.pump();
      stopwatch.stop();
      scrollDurations.add(stopwatch.elapsedMicroseconds);
    }

    final log = {
      'scenario': 'chat_scroll_up_pagination',
      'loops': _loopCount,
      'apiMessageCalls': api.messagesCalls,
      'apiMessagesBeforeCalls': api.messagesBeforeCalls,
      'scroll': _durationStats(scrollDurations),
    };
    _writePerfLog('chat_scroll_up_pagination', log);

    expect(api.messagesBeforeCalls, greaterThan(0));
    expect(_averageMs(scrollDurations), lessThan(35));
  });
}

ProviderContainer _perfContainer(_PerfChatApi api) {
  return ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        const AppConfig(apiBaseUrl: '', websocketUrl: ''),
      ),
      authControllerProvider.overrideWith(_PerfAuthController.new),
      chatRoomsProvider.overrideWith(_PerfChatRooms.new),
      chatApiProvider.overrideWithValue(api),
      currentUserProfileProvider.overrideWithValue(_currentUser),
      updatedUserProfilesProvider.overrideWithValue(const []),
      friendGroupsProvider.overrideWithValue(const []),
    ],
  );
}

void _primeLocalMessageCache(ProviderContainer container) {
  final cache = container.read(chatMessageMemoryCacheProvider.notifier);
  for (final room in _rooms) {
    cache.put(room.id, _messagesFor(room.id), persist: false);
  }
}

List<ChatMessage> _messagesFor(String roomCode) {
  return [
    for (var index = 0; index < 240; index++)
      ChatMessage(
        id: '$roomCode-msg-$index',
        senderId: index.isEven ? _currentUser.id : _otherUser.id,
        sender: index.isEven ? _currentUser : _otherUser,
        text: '$roomCode message $index',
        time: '12:${(index % 60).toString().padLeft(2, '0')}',
        isMine: index.isEven,
        sentAt: DateTime(2026, 5, 27, 9).add(Duration(minutes: index)),
      ),
  ];
}

List<ChatMessageDto> _messageDtosFor(
  String roomCode, {
  required int start,
  required int endExclusive,
}) {
  return [
    for (var index = start; index < endExclusive; index++)
      ChatMessageDto(
        id: '$roomCode-msg-$index',
        roomCode: roomCode,
        senderId: index.isEven ? _currentUser.id! : _otherUser.id!,
        senderName: index.isEven ? _currentUser.name : _otherUser.name,
        senderNickname: '',
        senderAvatarColor: index.isEven ? '#4663CF' : '#68A878',
        senderAvatarImageUrl: '',
        content: '$roomCode message $index',
        sentAt: DateTime(2026, 5, 27, 9).add(Duration(minutes: index)),
        unreadCount: 0,
        systemMessage: false,
        silent: false,
        spoiler: false,
        attachment: null,
        mentions: const [],
      ),
  ];
}

Map<String, Object> _durationStats(List<int> microseconds) {
  final sorted = [...microseconds]..sort();
  final average = _averageMs(microseconds);
  double percentile(double value) {
    final index = ((sorted.length - 1) * value).round();
    return sorted[index] / 1000;
  }

  return {
    'count': microseconds.length,
    'avgMs': double.parse(average.toStringAsFixed(3)),
    'minMs': double.parse((sorted.first / 1000).toStringAsFixed(3)),
    'p50Ms': double.parse(percentile(0.50).toStringAsFixed(3)),
    'p95Ms': double.parse(percentile(0.95).toStringAsFixed(3)),
    'maxMs': double.parse((sorted.last / 1000).toStringAsFixed(3)),
  };
}

double _averageMs(List<int> microseconds) {
  final total = microseconds.fold<int>(0, (sum, value) => sum + value);
  return total / microseconds.length / 1000;
}

void _writePerfLog(String name, Map<String, Object> log) {
  final directory = Directory('perf_logs');
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
  final timestamp = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  final file = File('perf_logs/${timestamp}_$name.json');
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(log));
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  required String description,
}) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    if (done()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for $description.');
}

class _PerfChatRooms extends ChatRooms {
  @override
  List<ChatRoom> build() => _rooms;

  @override
  Future<void> refreshFromServer({bool force = false}) async {}
}

class _DesktopChatPerfHarness extends ConsumerWidget {
  const _DesktopChatPerfHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(activeMessengerTabProvider);
    final selectedRoom = ref.watch(selectedChatRoomProvider);
    return Scaffold(
      body: activeTab == MessengerTab.notifications
          ? const NotificationCenterPanel()
          : Row(
              children: [
                const SizedBox(width: 396, child: ChatsPanel()),
                Expanded(
                  child: selectedRoom == null
                      ? const SizedBox.shrink()
                      : ChatRoomPanel(
                          key: const ValueKey('perf-chat-panel-state'),
                          room: selectedRoom,
                          onClose: () {},
                          mobileLayout: false,
                        ),
                ),
              ],
            ),
    );
  }
}

class _PerfAuthController extends AuthController {
  @override
  Future<AuthState> build() async {
    return AuthState(
      session: AuthSession(
        accessToken: 'perf-access-token',
        refreshToken: 'perf-refresh-token',
        expiresAt: DateTime(2026, 5, 27, 15),
        user: const AuthUser(
          id: 'perf-current-user',
          email: 'perf-current@ava.local',
          displayName: 'Perf Current',
          role: 'USER',
          companyName: 'ABBA-S',
        ),
      ),
    );
  }
}

class _PerfChatApi extends ChatApi {
  _PerfChatApi() : super(Dio(), null);

  int messagesCalls = 0;
  int messagesBeforeCalls = 0;

  @override
  Future<List<ChatRoomDto>> rooms(String accessToken) async {
    return [
      for (final room in _rooms)
        ChatRoomDto(
          code: room.id,
          title: room.title,
          type: 'DIRECT',
          participantCount: 2,
          pinned: false,
          pinnedAt: null,
          lastMessage: room.preview,
          lastMessageAt: room.lastActivityAt,
          lastMessageSpoiler: false,
          avatarImageUrl: '',
          notice: null,
          members: const [],
          unreadCount: 0,
          mentioned: false,
        ),
    ];
  }

  @override
  Future<List<ChatMessageDto>> messages({
    required String accessToken,
    required String roomCode,
    int limit = 80,
  }) async {
    messagesCalls++;
    final start = (240 - limit).clamp(0, 240).toInt();
    return _messageDtosFor(roomCode, start: start, endExclusive: 240);
  }

  @override
  Future<List<ChatMessageDto>> messagesBefore({
    required String accessToken,
    required String roomCode,
    required String messageId,
    int limit = 80,
  }) async {
    messagesBeforeCalls++;
    final boundary = int.tryParse(messageId.split('-msg-').last) ?? 0;
    final end = boundary.clamp(0, 240).toInt();
    final start = (end - limit).clamp(0, end).toInt();
    return _messageDtosFor(roomCode, start: start, endExclusive: end);
  }

  @override
  Future<List<UserProfileDto>> users(String accessToken) async => const [];

  @override
  Future<List<ChatFolderDto>> chatFolders(String accessToken) async => const [];

  @override
  Future<List<ChatFolderDto>> saveChatFolders({
    required String accessToken,
    required List<ChatFolderDto> folders,
  }) async {
    return folders;
  }

  @override
  Future<List<String>> chatFolderOrder(String accessToken) async => const [];

  @override
  Future<List<String>> saveChatFolderOrder({
    required String accessToken,
    required List<String> filterIds,
  }) async {
    return filterIds;
  }

  @override
  Future<List<String>> quietChatRooms(String accessToken) async => const [];

  @override
  Future<List<String>> saveQuietChatRooms({
    required String accessToken,
    required List<String> roomIds,
  }) async {
    return roomIds;
  }

  @override
  Future<List<ChatMentionNotificationDto>> mentionNotifications({
    required String accessToken,
    String status = 'all',
    int limit = 80,
  }) async {
    return const [];
  }

  @override
  Future<ChatReadStateDto> markRead({
    required String accessToken,
    required String roomCode,
  }) async {
    return ChatReadStateDto(roomCode: roomCode, messages: const []);
  }
}
