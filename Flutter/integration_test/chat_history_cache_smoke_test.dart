import 'dart:convert' show base64Url, jsonEncode, utf8;

import 'package:ava_flutter/src/config/app_version.dart';
import 'package:ava_flutter/src/config/app_config.dart';
import 'package:ava_flutter/src/features/auth/application/auth_controller.dart';
import 'package:ava_flutter/src/features/auth/data/auth_models.dart';
import 'package:ava_flutter/src/features/messenger/application/notification_center_controller.dart';
import 'package:ava_flutter/src/features/messenger/data/chat_api.dart';
import 'package:ava_flutter/src/features/messenger/domain/messenger_models.dart';
import 'package:ava_flutter/src/features/messenger/presentation/messenger_page.dart';
import 'package:ava_flutter/src/features/messenger/presentation/widgets/chat_room_panel.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _room = ChatRoom(
  id: 'chat-cache-smoke-room',
  title: 'Cache Smoke',
  preview: '',
  time: '',
  participantCount: 2,
  members: [
    PersonProfile(
      id: 'cache-user',
      name: 'Cache User',
      color: Color(0xFF7AA06A),
      email: 'cache@ava.local',
    ),
    PersonProfile(
      id: 'other-user',
      name: 'Other User',
      color: Color(0xFF8BA6C9),
      email: 'other@ava.local',
    ),
  ],
);

const _cachedMessageText = 'AVA_CHAT_CACHE_VISIBLE_IMMEDIATELY';
const _cachedNotificationText = 'AVA_NOTIFICATION_CACHE_VISIBLE_IMMEDIATELY';
const _installSetupCompletedKey = 'ava.app_setup.install_completed.v2';
const _setupCompletedVersionKey = 'ava.app_setup.completed_version.v1';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('warms chat histories during app setup before room open', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = _SlowChatApi(delay: const Duration(milliseconds: 700));
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'http://127.0.0.1:9',
            websocketUrl: 'ws://127.0.0.1:9/ws',
          ),
        ),
        authControllerProvider.overrideWith(_SmokeAuthController.new),
        chatRoomsProvider.overrideWith(_SmokeChatRooms.new),
        chatApiProvider.overrideWithValue(api),
        currentUserProfileProvider.overrideWithValue(
          const PersonProfile(
            id: 'cache-user',
            name: 'Cache User',
            color: Color(0xFF7AA06A),
            email: 'cache@ava.local',
          ),
        ),
        updatedUserProfilesProvider.overrideWithValue(const []),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessengerPage()),
      ),
    );

    for (var attempt = 0; attempt < 12; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find
          .byKey(const ValueKey('app-setup-overlay'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(find.byKey(const ValueKey('app-setup-overlay')), findsOneWidget);
    expect(find.text('앱 설정중. . .'), findsOneWidget);

    for (var attempt = 0; attempt < 12; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_installSetupCompletedKey) == true) {
        break;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(_installSetupCompletedKey), isTrue);

    await _pumpUntil(
      tester,
      () => container
          .read(chatMessageMemoryCacheProvider.notifier)
          .messagesFor(_room.id)
          .isNotEmpty,
      description: 'chat history cache',
    );
    await _pumpUntil(
      tester,
      () => container
          .read(notificationCenterCacheProvider)
          .notifications
          .isNotEmpty,
      description: 'notification center cache',
    );
    expect(
      container
          .read(chatMessageMemoryCacheProvider.notifier)
          .messagesFor(_room.id),
      isNotEmpty,
    );
    expect(
      container.read(notificationCenterCacheProvider).notifications,
      isNotEmpty,
    );
    expect(find.byKey(const ValueKey('app-setup-overlay')), findsNothing);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _ChatCacheSmokeHarness()),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.text(_cachedMessageText).evaluate().isNotEmpty,
      description: 'cached chat message paint after warmup',
    );
    expect(find.text(_cachedMessageText), findsOneWidget);
  });

  testWidgets('paints preloaded notification center immediately for 30 loops', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = _SlowChatApi(delay: const Duration(milliseconds: 700));
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'http://127.0.0.1:9',
            websocketUrl: 'ws://127.0.0.1:9/ws',
          ),
        ),
        authControllerProvider.overrideWith(_SmokeAuthController.new),
        chatRoomsProvider.overrideWith(_SmokeChatRooms.new),
        chatApiProvider.overrideWithValue(api),
        currentUserProfileProvider.overrideWithValue(
          const PersonProfile(
            id: 'cache-user',
            name: 'Cache User',
            color: Color(0xFF7AA06A),
            email: 'cache@ava.local',
          ),
        ),
        updatedUserProfilesProvider.overrideWithValue(const []),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessengerPage()),
      ),
    );

    await _pumpUntil(
      tester,
      () => container
          .read(notificationCenterCacheProvider)
          .notifications
          .isNotEmpty,
      description: 'notification center cache',
    );
    expect(
      container.read(notificationCenterCacheProvider).notifications,
      isNotEmpty,
    );

    final paintDurations = <int>[];
    for (var loop = 1; loop <= 30; loop++) {
      container
          .read(activeMessengerTabProvider.notifier)
          .setTab(MessengerTab.chats);
      await tester.pump();

      final stopwatch = Stopwatch()..start();
      container
          .read(activeMessengerTabProvider.notifier)
          .setTab(MessengerTab.notifications);
      await tester.pump();
      stopwatch.stop();

      expect(
        find.byKey(const ValueKey('notification-center-loading')),
        findsNothing,
      );
      expect(find.text(_cachedNotificationText), findsOneWidget);
      paintDurations.add(stopwatch.elapsedMilliseconds);
    }

    // ignore: avoid_print
    print(
      'NOTIFICATION_CACHE_SMOKE loops=30 apiCalls=${api.notificationCalls} '
      'maxFirstPaintMs=${paintDurations.reduce((a, b) => a > b ? a : b)}',
    );
  });

  testWidgets('does not show app setup overlay after setup was completed', (
    tester,
  ) async {
    final scope = base64Url.encode(utf8.encode('cache-user|ABBA-S'));
    SharedPreferences.setMockInitialValues({
      'ava.app_setup.completed.v3.$scope': true,
      _setupCompletedVersionKey: AppVersion.name,
    });
    final api = _SlowChatApi(delay: const Duration(milliseconds: 700));
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'http://127.0.0.1:9',
            websocketUrl: 'ws://127.0.0.1:9/ws',
          ),
        ),
        authControllerProvider.overrideWith(_SmokeAuthController.new),
        chatRoomsProvider.overrideWith(_SmokeChatRooms.new),
        chatApiProvider.overrideWithValue(api),
        currentUserProfileProvider.overrideWithValue(
          const PersonProfile(
            id: 'cache-user',
            name: 'Cache User',
            color: Color(0xFF7AA06A),
            email: 'cache@ava.local',
          ),
        ),
        updatedUserProfilesProvider.overrideWithValue(const []),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessengerPage()),
      ),
    );

    for (var attempt = 0; attempt < 12; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('app-setup-overlay')), findsNothing);
    }
    await _pumpUntil(
      tester,
      () => container
          .read(chatMessageMemoryCacheProvider.notifier)
          .messagesFor(_room.id)
          .isNotEmpty,
      description: 'silent chat history warmup',
    );
    expect(find.byKey(const ValueKey('app-setup-overlay')), findsNothing);
  });

  testWidgets('does not show app setup overlay after current version marker', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _installSetupCompletedKey: true,
      _setupCompletedVersionKey: AppVersion.name,
    });
    final api = _SlowChatApi(delay: const Duration(milliseconds: 700));
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'http://127.0.0.1:9',
            websocketUrl: 'ws://127.0.0.1:9/ws',
          ),
        ),
        authControllerProvider.overrideWith(_SmokeAuthController.new),
        chatRoomsProvider.overrideWith(_SmokeChatRooms.new),
        chatApiProvider.overrideWithValue(api),
        currentUserProfileProvider.overrideWithValue(
          const PersonProfile(
            id: 'cache-user',
            name: 'Cache User',
            color: Color(0xFF7AA06A),
            email: 'cache@ava.local',
          ),
        ),
        updatedUserProfilesProvider.overrideWithValue(const []),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessengerPage()),
      ),
    );

    for (var attempt = 0; attempt < 12; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('app-setup-overlay')), findsNothing);
    }
    await _pumpUntil(
      tester,
      () => container
          .read(chatMessageMemoryCacheProvider.notifier)
          .messagesFor(_room.id)
          .isNotEmpty,
      description: 'install-marker silent chat history warmup',
    );
    expect(find.byKey(const ValueKey('app-setup-overlay')), findsNothing);
  });

  testWidgets('shows app setup once after app version update', (tester) async {
    SharedPreferences.setMockInitialValues({
      _installSetupCompletedKey: true,
      _setupCompletedVersionKey: '0.0.0-old',
    });
    final api = _SlowChatApi(delay: const Duration(milliseconds: 500));
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'http://127.0.0.1:9',
            websocketUrl: 'ws://127.0.0.1:9/ws',
          ),
        ),
        authControllerProvider.overrideWith(_SmokeAuthController.new),
        chatRoomsProvider.overrideWith(_SmokeChatRooms.new),
        chatApiProvider.overrideWithValue(api),
        currentUserProfileProvider.overrideWithValue(
          const PersonProfile(
            id: 'cache-user',
            name: 'Cache User',
            color: Color(0xFF7AA06A),
            email: 'cache@ava.local',
          ),
        ),
        updatedUserProfilesProvider.overrideWithValue(const []),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessengerPage()),
      ),
    );

    await _pumpUntil(
      tester,
      () =>
          find.byKey(const ValueKey('app-setup-overlay')).evaluate().isNotEmpty,
      description: 'version update setup overlay',
    );
    await _pumpUntil(
      tester,
      () => find.byKey(const ValueKey('app-setup-overlay')).evaluate().isEmpty,
      description: 'version update setup overlay dismissed',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_setupCompletedVersionKey), AppVersion.name);
  });

  testWidgets('initial app setup waits for remote rooms before completing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = _SlowChatApi(delay: const Duration(milliseconds: 500));
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'http://127.0.0.1:9',
            websocketUrl: 'ws://127.0.0.1:9/ws',
          ),
        ),
        authControllerProvider.overrideWith(_SmokeAuthController.new),
        chatApiProvider.overrideWithValue(api),
        currentUserProfileProvider.overrideWithValue(
          const PersonProfile(
            id: 'cache-user',
            name: 'Cache User',
            color: Color(0xFF7AA06A),
            email: 'cache@ava.local',
          ),
        ),
        updatedUserProfilesProvider.overrideWithValue(const []),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessengerPage()),
      ),
    );

    await _pumpUntil(
      tester,
      () =>
          find.byKey(const ValueKey('app-setup-overlay')).evaluate().isNotEmpty,
      description: 'initial setup overlay',
    );
    await _pumpUntil(
      tester,
      () => container
          .read(chatMessageMemoryCacheProvider.notifier)
          .messagesFor(_room.id)
          .isNotEmpty,
      description: 'remote room messages cached during setup',
    );
    await _pumpUntil(
      tester,
      () => find.byKey(const ValueKey('app-setup-overlay')).evaluate().isEmpty,
      description: 'initial setup overlay dismissed',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(_installSetupCompletedKey), isTrue);
    expect(prefs.getString(_setupCompletedVersionKey), AppVersion.name);
    expect(api.roomsCalls, greaterThanOrEqualTo(1));
    expect(api.messagesCalls, greaterThanOrEqualTo(1));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _ChatCacheSmokeHarness()),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.text(_cachedMessageText).evaluate().isNotEmpty,
      description: 'cached message visible after remote setup',
    );
    expect(
      find.byKey(const ValueKey('chat-room-loading-indicator')),
      findsNothing,
    );
  });

  testWidgets('restores persisted chat history before remote sync', (
    tester,
  ) async {
    final scope = base64Url.encode(utf8.encode('cache-user|ABBA-S'));
    SharedPreferences.setMockInitialValues({
      'ava.chat.message_cache.v2.$scope': jsonEncode({
        _room.id: [_cachedMessageJson()],
      }),
    });
    final api = _SlowChatApi(delay: const Duration(milliseconds: 900));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://127.0.0.1:9',
              websocketUrl: 'ws://127.0.0.1:9/ws',
            ),
          ),
          authControllerProvider.overrideWith(_SmokeAuthController.new),
          chatApiProvider.overrideWithValue(api),
          currentUserProfileProvider.overrideWithValue(
            const PersonProfile(
              id: 'cache-user',
              name: 'Cache User',
              color: Color(0xFF7AA06A),
              email: 'cache@ava.local',
            ),
          ),
          updatedUserProfilesProvider.overrideWithValue(const []),
        ],
        child: const MaterialApp(home: _PersistedChatCacheHarness()),
      ),
    );

    expect(
      find.byKey(const ValueKey('chat-room-loading-indicator')),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(
      find.byKey(const ValueKey('chat-room-loading-indicator')),
      findsNothing,
    );
    expect(find.text(_cachedMessageText), findsOneWidget);
    expect(api.messagesCalls, lessThanOrEqualTo(1));
  });

  testWidgets('paints cached chat history immediately for 30 reopen loops', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = _SlowChatApi(delay: const Duration(milliseconds: 900));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'http://127.0.0.1:9',
              websocketUrl: 'ws://127.0.0.1:9/ws',
            ),
          ),
          authControllerProvider.overrideWith(_SmokeAuthController.new),
          chatApiProvider.overrideWithValue(api),
          currentUserProfileProvider.overrideWithValue(
            const PersonProfile(
              id: 'cache-user',
              name: 'Cache User',
              color: Color(0xFF7AA06A),
              email: 'cache@ava.local',
            ),
          ),
          updatedUserProfilesProvider.overrideWithValue(const []),
        ],
        child: const MaterialApp(home: _ChatCacheSmokeHarness()),
      ),
    );

    await tester.pump();
    expect(find.text(_cachedMessageText), findsNothing);

    await tester.pump(api.delay + const Duration(milliseconds: 300));
    expect(find.text(_cachedMessageText), findsOneWidget);

    final paintDurations = <int>[];
    for (var loop = 1; loop <= 30; loop++) {
      await tester.tap(find.byKey(const ValueKey('toggle-chat-cache-panel')));
      await tester.pump();
      expect(find.text(_cachedMessageText), findsNothing);

      final stopwatch = Stopwatch()..start();
      await tester.tap(find.byKey(const ValueKey('toggle-chat-cache-panel')));
      await tester.pump();
      stopwatch.stop();

      expect(
        find.byKey(const ValueKey('chat-room-loading-indicator')),
        findsNothing,
      );
      expect(find.text(_cachedMessageText), findsOneWidget);
      paintDurations.add(stopwatch.elapsedMilliseconds);
    }

    // ignore: avoid_print
    print(
      'CHAT_CACHE_SMOKE loops=30 apiCalls=${api.messagesCalls} '
      'maxFirstPaintMs=${paintDurations.reduce((a, b) => a > b ? a : b)}',
    );
  });
}

Map<String, Object?> _cachedMessageJson() {
  return {
    'id': 'cache-smoke-message',
    'senderId': 'other-user',
    'sender': {
      'id': 'other-user',
      'name': 'Other User',
      'email': 'other@ava.local',
      'color': '#8BA6C9',
    },
    'text': _cachedMessageText,
    'time': '9:00',
    'isMine': false,
    'sentAt': DateTime(2026, 5, 24, 9).toIso8601String(),
    'unreadCount': 0,
    'isSystem': false,
    'isSilent': false,
    'isSpoiler': false,
    'spoilerRevealed': false,
    'attachment': null,
    'mentions': const [],
  };
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
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for $description.');
}

class _SmokeChatRooms extends ChatRooms {
  @override
  List<ChatRoom> build() => const [_room];

  @override
  Future<void> refreshFromServer({bool force = false}) async {}
}

class _ChatCacheSmokeHarness extends StatefulWidget {
  const _ChatCacheSmokeHarness();

  @override
  State<_ChatCacheSmokeHarness> createState() => _ChatCacheSmokeHarnessState();
}

class _ChatCacheSmokeHarnessState extends State<_ChatCacheSmokeHarness> {
  bool _showPanel = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ElevatedButton(
            key: const ValueKey('toggle-chat-cache-panel'),
            onPressed: () {
              setState(() {
                _showPanel = !_showPanel;
              });
            },
            child: Text(_showPanel ? 'hide' : 'show'),
          ),
          Expanded(
            child: _showPanel
                ? ChatRoomPanel(room: _room, onClose: () {}, mobileLayout: true)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _PersistedChatCacheHarness extends ConsumerStatefulWidget {
  const _PersistedChatCacheHarness();

  @override
  ConsumerState<_PersistedChatCacheHarness> createState() =>
      _PersistedChatCacheHarnessState();
}

class _PersistedChatCacheHarnessState
    extends ConsumerState<_PersistedChatCacheHarness> {
  @override
  void initState() {
    super.initState();
    ref
        .read(chatMessageMemoryCacheProvider.notifier)
        .configureScope('cache-user|ABBA-S');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ChatRoomPanel(room: _room, onClose: () {}, mobileLayout: true),
    );
  }
}

class _SmokeAuthController extends AuthController {
  @override
  Future<AuthState> build() async {
    return AuthState(
      session: AuthSession(
        accessToken: 'cache-smoke-access-token',
        refreshToken: 'cache-smoke-refresh-token',
        expiresAt: DateTime(2026, 5, 24, 12),
        user: const AuthUser(
          id: 'cache-user',
          email: 'cache@ava.local',
          displayName: 'Cache User',
          role: 'USER',
          companyName: 'ABBA-S',
        ),
      ),
    );
  }
}

class _SlowChatApi extends ChatApi {
  _SlowChatApi({required this.delay}) : super(Dio(), null);

  final Duration delay;
  int roomsCalls = 0;
  int messagesCalls = 0;
  int notificationCalls = 0;

  @override
  Future<List<ChatRoomDto>> rooms(String accessToken) async {
    roomsCalls++;
    await Future<void>.delayed(delay);
    return [_roomDto()];
  }

  @override
  Future<List<ChatMessageDto>> messages({
    required String accessToken,
    required String roomCode,
    int limit = 80,
  }) async {
    messagesCalls++;
    await Future<void>.delayed(delay);
    return [
      ChatMessageDto(
        id: 'cache-smoke-message',
        roomCode: roomCode,
        senderId: 'other-user',
        senderName: 'Other User',
        senderNickname: '',
        senderAvatarColor: '#8BA6C9',
        senderAvatarImageUrl: '',
        content: _cachedMessageText,
        sentAt: DateTime(2026, 5, 24, 9),
        unreadCount: 0,
        systemMessage: false,
        silent: false,
        spoiler: false,
        attachment: null,
        mentions: const [],
      ),
    ];
  }

  @override
  Future<List<UserProfileDto>> users(String accessToken) async => const [];

  @override
  Future<List<ChatMentionNotificationDto>> mentionNotifications({
    required String accessToken,
    String status = 'all',
    int limit = 80,
  }) async {
    notificationCalls++;
    await Future<void>.delayed(delay);
    return [_notificationDto()];
  }

  @override
  Future<ChatMentionNotificationDto> markMentionNotificationChecked({
    required String accessToken,
    required String notificationId,
  }) async {
    return _notificationDto(checked: true);
  }

  @override
  Future<ChatReadStateDto> markRead({
    required String accessToken,
    required String roomCode,
  }) async {
    return const ChatReadStateDto(roomCode: '', messages: []);
  }
}

ChatRoomDto _roomDto() {
  return ChatRoomDto(
    code: _room.id,
    title: _room.title,
    type: 'GROUP',
    participantCount: 2,
    pinned: false,
    pinnedAt: null,
    lastMessage: _cachedMessageText,
    lastMessageAt: DateTime(2026, 5, 24, 9),
    lastMessageSpoiler: false,
    avatarImageUrl: '',
    notice: null,
    members: [
      _userDto('cache-user', 'Cache User'),
      _userDto('other-user', 'Other User'),
    ],
    unreadCount: 0,
    mentioned: false,
  );
}

ChatMentionNotificationDto _notificationDto({bool checked = false}) {
  return ChatMentionNotificationDto(
    id: 'notification-cache-smoke',
    roomCode: _room.id,
    roomTitle: _room.title,
    participantCount: 2,
    roomMembers: [
      _userDto('cache-user', 'Cache User'),
      _userDto('other-user', 'Other User'),
    ],
    messageId: 'cache-smoke-message',
    senderId: 'other-user',
    senderName: 'Other User',
    senderNickname: '',
    senderAvatarColor: '#8BA6C9',
    senderAvatarImageUrl: '',
    mentionDisplayName: 'Cache',
    content: '@Cache $_cachedNotificationText',
    sentAt: DateTime(2026, 5, 24, 9),
    checkedAt: checked ? DateTime(2026, 5, 24, 9, 1) : null,
    checked: checked,
  );
}

UserProfileDto _userDto(String id, String name) {
  return UserProfileDto(
    id: id,
    email: '$id@ava.local',
    name: name,
    displayName: name,
    nickname: '',
    phoneNumber: '',
    role: 'USER',
    companyName: 'ABBA-S',
    position: '',
    department: 'Cache',
    birthDate: null,
    status: 'online',
    avatarColor: id == 'cache-user' ? '#7AA06A' : '#8BA6C9',
    statusMessage: '',
    avatarImageUrl: '',
    profileBackgroundColor: '#7AA06A',
    profileBackgroundImageUrl: '',
    blocked: false,
  );
}
