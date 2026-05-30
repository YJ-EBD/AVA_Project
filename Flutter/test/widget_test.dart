import 'dart:io' show Platform;
import 'dart:ui';

import 'package:ava_flutter/src/features/admin/data/admin_api.dart';
import 'package:ava_flutter/src/features/ai/presentation/ava_ai_page.dart';
import 'package:ava_flutter/src/config/app_config.dart';
import 'package:ava_flutter/src/features/auth/application/auth_controller.dart';
import 'package:ava_flutter/src/features/auth/data/auth_models.dart';
import 'package:ava_flutter/src/features/auth/presentation/login_page.dart';
import 'package:ava_flutter/src/features/ava_stock/presentation/ava_stock_page.dart';
import 'package:ava_flutter/src/features/azoom/presentation/azoom_page.dart';
import 'package:ava_flutter/src/features/home/presentation/home_page.dart';
import 'package:ava_flutter/src/features/messenger/data/chat_api.dart';
import 'package:ava_flutter/src/features/messenger/data/mock_messenger_data.dart';
import 'package:ava_flutter/src/features/messenger/domain/messenger_models.dart';
import 'package:ava_flutter/src/features/messenger/presentation/messenger_page.dart';
import 'package:ava_flutter/src/features/messenger/presentation/widgets/more_panel.dart';
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _findAvaStockCodeSplash() {
  return find.byKey(const ValueKey('ava-stock-code-splash'));
}

void main() {
  test('orders active chat rooms after pinned rooms', () {
    final container = _messengerTestContainer();
    addTearDown(container.dispose);

    expect(container.read(chatRoomsProvider).take(3).map((room) => room.id), [
      'ra-team',
      'research-lab',
      'all-staff',
    ]);

    container
        .read(chatRoomsProvider.notifier)
        .messagePosted('kim-minjae', 'latest chat', DateTime(2026, 5, 6, 18));

    final rooms = container.read(chatRoomsProvider);
    expect(rooms[0].id, 'ra-team');
    expect(rooms[1].id, 'kim-minjae');
    expect(rooms[1].preview, 'latest chat');
  });

  test('uses recipient realtime unread count when server provides it', () {
    final container = _messengerTestContainer();
    addTearDown(container.dispose);
    final notifier = container.read(chatRoomsProvider.notifier);
    const room = ChatRoom(
      id: 'server-unread-room',
      title: 'Server unread',
      preview: '',
      time: '',
      members: [],
      unreadCount: 1,
    );

    notifier.upsert(room);
    notifier.realtimeRoomUpdated(
      room.copyWith(unreadCount: 7, hasUnreadMention: true),
      incrementUnread: true,
      isOpen: false,
    );

    final updated = container
        .read(chatRoomsProvider)
        .firstWhere((item) => item.id == room.id);
    expect(updated.unreadCount, 7);
    expect(updated.hasUnreadMention, isTrue);
  });

  test('puts current user unspecified department first', () async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_UnspecifiedTestAuthController.new),
        userProfilesProvider.overrideWith(_UnspecifiedTestUserProfiles.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await container.read(userProfilesProvider.future);

    final groups = container.read(friendGroupsProvider);

    expect(groups.first.title, '\uBBF8\uC9C0\uC815');
    expect(groups.first.users.first.id, 'test1-user');
  });

  testWidgets('keeps AVA AI workspace beside the chat pane', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(460, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 460, height: 720, child: AvaAiPage()),
          ),
        ),
      ),
    );
    await tester.pump();

    final chatPane = find.byKey(const ValueKey('ava-ai-chat-pane'));
    final workspacePane = find.byKey(const ValueKey('ava-ai-workspace-pane'));

    expect(chatPane, findsOneWidget);
    expect(workspacePane, findsOneWidget);
    expect(tester.getSize(chatPane).width, 396);
    expect(tester.getSize(workspacePane).width, 390);
    expect(
      tester.getTopLeft(workspacePane).dx,
      moreOrLessEquals(tester.getTopRight(chatPane).dx, epsilon: 0.1),
    );
  });

  testWidgets('resizes the native window for AVA AI and compact tabs', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(960, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final nativeCalls = <String>[];
    const windowChannel = MethodChannel('ava/window');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      (call) async {
        nativeCalls.add(call.method);
        return _nativeMenuResult(call);
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowChannel,
        null,
      );
    });

    final container = _messengerTestContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessengerPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.auto_awesome).first);
    await tester.pumpAndSettle();

    expect(nativeCalls, contains('setWindowTitle'));
    expect(nativeCalls, contains('expandMessenger'));
    expect(find.byKey(const ValueKey('ava-ai-chat-pane')), findsOneWidget);
    expect(find.byKey(const ValueKey('ava-ai-workspace-pane')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('side-nav-ava-stock-button')),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chat_bubble).first);
    await tester.pumpAndSettle();

    expect(nativeCalls, contains('compactMessenger'));
    expect(container.read(activeMessengerTabProvider), MessengerTab.chats);
  });

  testWidgets('resets native window mode for login page', (
    WidgetTester tester,
  ) async {
    final nativeCalls = <String>[];
    const windowChannel = MethodChannel('ava/window');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      (call) async {
        nativeCalls.add(call.method);
        return _nativeMenuResult(call);
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowChannel,
        null,
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_LoggedOutAuthController.new),
        ],
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.pump();

    expect(nativeCalls, contains('setWindowTitle'));
    expect(nativeCalls, contains('showAuthWindow'));
    expect(nativeCalls, isNot(contains('compactMessenger')));
  });

  testWidgets('opens AVA_stock from the mobile common bottom nav', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 820);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = _messengerTestContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessengerPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile-nav-ava-stock')));
    await tester.pump();

    expect(container.read(activeMessengerTabProvider), MessengerTab.avaStock);
    expect(_findAvaStockCodeSplash(), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
  });

  testWidgets('opens AVA_stock directly from the ava-stock route shell', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 820);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = _messengerTestContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomePage.avaStock()),
      ),
    );
    await tester.pump();

    expect(container.read(activeMessengerTabProvider), MessengerTab.avaStock);
    expect(_findAvaStockCodeSplash(), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
  });

  testWidgets('opens space dashboard from AVA_stock quick menu', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 820);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AvaStockPage())),
    );
    await tester.pump();

    expect(_findAvaStockCodeSplash(), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();

    final previousFactoryViewLabel = String.fromCharCodes([
      0xACF5,
      0xC7A5,
      0x20,
      0x33,
      0x44,
      0x20,
      0xBDF0,
    ]);
    expect(find.text(previousFactoryViewLabel), findsNothing);
    expect(find.text('공간 대시보드'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('ava-stock-space-dashboard-card')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ava-stock-space-dashboard-view')),
      findsOneWidget,
    );
    expect(find.text('\uACF5\uAC04 \uB300\uC2DC\uBCF4\uB4DC'), findsWidgets);
  });

  testWidgets('shows admin more panel as a full-width expanded page', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(960, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = _adminMessengerTestContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 960,
              height: 720,
              child: Row(
                children: [
                  SizedBox(width: 64),
                  SizedBox(width: 896, child: MorePanel()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final adminPanel = find.byKey(const ValueKey('admin-panel-root'));
    expect(adminPanel, findsOneWidget);
    expect(
      tester.getSize(adminPanel).width,
      moreOrLessEquals(896, epsilon: 0.1),
    );

    await tester.tap(find.byKey(const ValueKey('admin-user-tile-admin-user')));
    await tester.pumpAndSettle();

    expect(find.text('내 계정은 이름, 부서, 직책만 수정할 수 있습니다.'), findsOneWidget);
    expect(find.text('로그인 허용'), findsNothing);
  });

  testWidgets('shows collapsible user groups and opens direct chat', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = _messengerTestContainer();
    addTearDown(container.dispose);
    const windowChannel = MethodChannel('ava/window');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      (call) async => _nativeMenuResult(call),
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowChannel,
        null,
      );
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessengerPage()),
      ),
    );
    await tester.pumpAndSettle();

    final updatedUser = find.byKey(
      ValueKey('updated-user-${updatedUsers.first.identityKey}'),
    );
    final currentUserRow = find.byKey(
      const ValueKey('user-row-amos5105@naver.com'),
    );

    expect(updatedUser, findsOneWidget);
    expect(currentUserRow, findsOneWidget);

    await tester.tap(find.byIcon(Icons.chat_bubble).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person).first);
    await tester.pumpAndSettle();
    expect(currentUserRow, findsOneWidget);

    await tester.tap(updatedUser);
    await tester.pump(const Duration(milliseconds: 80));
    await _openDirectChatFromProfile(tester);

    final selectedDirectRoom = container.read(selectedChatRoomProvider);
    expect(selectedDirectRoom, isNotNull);
    expect(
      find.byKey(ValueKey('chat-panel-direct-${selectedDirectRoom!.title}')),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);

    final openedDirectRoom = selectedDirectRoom;
    expect(find.text(openedDirectRoom.preview), findsNothing);
    expect(
      container
          .read(chatRoomsProvider)
          .any((room) => room.id == openedDirectRoom.id),
      isFalse,
    );
    const directMessage = 'hello direct';
    final directRoomId = openedDirectRoom.id;
    await tester.enterText(find.byType(TextField), directMessage);
    await tester.pump();
    container
        .read(chatRoomsProvider.notifier)
        .messagePosted(
          directRoomId,
          directMessage,
          DateTime(2026, 5, 13, 12),
          fallbackRoom: openedDirectRoom,
        );
    await tester.pumpAndSettle();

    expect(
      container
          .read(chatRoomsProvider)
          .any(
            (room) => room.id == directRoomId && room.preview == directMessage,
          ),
      isTrue,
    );

    await tester.tap(find.byIcon(Icons.chat_bubble).first);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('chat-room-$directRoomId')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.person).first);
    await tester.pumpAndSettle();

    final friendsList = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('영업부'),
      180,
      scrollable: friendsList,
    );
    expect(find.text('영업부'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('생산기술'),
      180,
      scrollable: friendsList,
    );
    expect(find.text('생산기술'), findsOneWidget);
  });

  testWidgets('opens profile direct chat once and replaces the draft pane', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final chatApi = _FakeDirectChatApi();
    final container = _directChatTestContainer(chatApi);
    addTearDown(container.dispose);

    const windowChannel = MethodChannel('ava/window');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      (call) async => _nativeMenuResult(call),
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowChannel,
        null,
      );
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessengerPage()),
      ),
    );
    await tester.pumpAndSettle();

    final target = updatedUsers.first;
    await tester.tap(
      find.byKey(ValueKey('updated-user-${target.identityKey}')),
    );
    await tester.pump(const Duration(milliseconds: 80));

    if (Platform.isWindows) {
      final firstTap = _sendWindowMethodCall(tester, 'profilePopupAction', {
        'action': 'directChat',
      });
      final secondTap = _sendWindowMethodCall(tester, 'profilePopupAction', {
        'action': 'directChat',
      });
      await tester.pump(const Duration(milliseconds: 80));
      await Future.wait([firstTap, secondTap]);
      await tester.pump();
    } else {
      await _openDirectChatFromProfile(tester);
    }

    expect(chatApi.directRoomCalls, 1);
    expect(container.read(selectedChatRoomProvider)?.id, 'direct-test-target');
    expect(
      find.byKey(const ValueKey('chat-panel-direct-test-target')),
      findsOneWidget,
    );
    expect(
      container
          .read(chatRoomsProvider)
          .where((room) => room.id == 'direct-test-target')
          .length,
      1,
    );
    expect(
      container
          .read(chatRoomsProvider)
          .where((room) => room.id == 'direct-${target.identityKey}')
          .length,
      0,
    );

    container.read(selectedChatRoomProvider.notifier).close();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('shows messenger shell and opens chat panel', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = _messengerTestContainer();
    addTearDown(container.dispose);
    const windowChannel = MethodChannel('ava/window');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      (call) async => _nativeMenuResult(call),
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowChannel,
        null,
      );
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessengerPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(_sideNavUnreadBadgeText(tester), '6');

    await tester.tap(find.byIcon(Icons.chat_bubble).first);
    await tester.pumpAndSettle();

    final roomTile = find.byKey(const ValueKey('chat-room-ra-team'));
    expect(roomTile, findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(_chatRoomTileColor(tester, 'ra-team'), Colors.white);
    expect(find.byKey(const ValueKey('unread-badge-ra-team')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-room-rnd')), findsNothing);
    expect(find.byKey(const ValueKey('chat-room-lab')), findsNothing);
    expect(find.byKey(const ValueKey('chat-room-photo')), findsNothing);
    expect(
      find.descendant(of: roomTile, matching: find.text('12')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: roomTile,
        matching: find.byKey(const ValueKey('chat-room-avatar-ra-team-3')),
      ),
      findsOneWidget,
    );

    final rooms = container.read(chatRoomsProvider);
    expect(
      rooms.where(
        (room) => [
          'ra-team',
          'research-lab',
          'all-staff',
          'design-team',
          'logistics-room',
        ].contains(room.id),
      ),
      hasLength(5),
    );
    expect(
      rooms.where(
        (room) => [
          'rnd',
          'lab',
          'photo',
          'dongchan',
          'jang',
          'support',
        ].contains(room.id),
      ),
      isEmpty,
    );
    expect(
      rooms.firstWhere((room) => room.id == 'ra-team').members,
      hasLength(12),
    );
    expect(
      rooms.firstWhere((room) => room.id == 'all-staff').members,
      hasLength(20),
    );
    expect(
      rooms.where(
        (room) =>
            room.id.startsWith('kim-') ||
            room.id.startsWith('park-') ||
            room.id.startsWith('lee-') ||
            room.id.startsWith('choi-') ||
            room.id.startsWith('jung-') ||
            room.id.startsWith('han-') ||
            room.id.startsWith('oh-') ||
            room.id.startsWith('kang-') ||
            room.id.startsWith('yoon-') ||
            room.id.startsWith('seo-'),
      ),
      hasLength(10),
    );

    await tester.tap(
      find.byKey(const ValueKey('chat-filter-folder-system-unread')),
    );
    await tester.pumpAndSettle();

    expect(container.read(activeChatFolderProvider), unreadChatFolderId);
    expect(find.byKey(const ValueKey('chat-room-ra-team')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-room-kim-minjae')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-room-research-lab')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chat-filter-all')));
    await tester.pumpAndSettle();

    expect(container.read(activeChatFolderProvider), isNull);

    final designTile = find.byKey(const ValueKey('chat-room-design-team'));
    await tester.tapAt(tester.getCenter(designTile), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    if (!Platform.isWindows) {
      await tester.tap(find.byKey(const ValueKey('room-menu-pin')));
      await tester.pumpAndSettle();
    }

    expect(
      container
          .read(chatRoomsProvider)
          .firstWhere((room) => room.id == 'design-team')
          .isPinned,
      isTrue,
    );

    expect(
      find.descendant(of: designTile, matching: find.byIcon(Icons.push_pin)),
      findsOneWidget,
    );

    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer(location: tester.getCenter(roomTile));
    await tester.pump();
    expect(_chatRoomTileColor(tester, 'ra-team'), Colors.white);

    await hover.moveTo(Offset.zero);
    await tester.pump();
    expect(_chatRoomTileColor(tester, 'ra-team'), Colors.white);
    await hover.removePointer();

    final press = await tester.startGesture(tester.getCenter(roomTile));
    await tester.pump();
    expect(container.read(focusedChatRoomIdProvider), 'ra-team');
    expect(_chatRoomTileColor(tester, 'ra-team'), const Color(0xFFEFEFEF));
    await press.up();

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TextField), findsNothing);

    await tester.tap(roomTile);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(roomTile);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-panel-ra-team')), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-badge-ra-team')), findsNothing);
    expect(_sideNavUnreadBadgeText(tester), '2');

    container.read(chatRoomsProvider.notifier).markRead('kim-minjae');
    await tester.pump();
    expect(find.byKey(const ValueKey('unread-filter-badge')), findsNothing);
    expect(find.byKey(const ValueKey('side-nav-unread-badge')), findsNothing);
    expect(find.byKey(const ValueKey('chat-notice-card')), findsNothing);

    final selectedRoom = container.read(selectedChatRoomProvider)!;
    final notice = ChatNotice(
      messageId: 'chat-message-1',
      senderName: selectedRoom.members.first.name,
      content: selectedRoom.preview,
      sentAt: DateTime(2026, 5, 13, 12),
    );
    container
        .read(chatRoomsProvider.notifier)
        .noticeSet(selectedRoom.id, notice);
    container
        .read(selectedChatRoomProvider.notifier)
        .open(selectedRoom.copyWith(notice: notice));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-notice-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-notice-text')), findsOneWidget);

    final researchTile = find.byKey(const ValueKey('chat-room-research-lab'));
    await tester.tap(researchTile);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(researchTile);
    await tester.pump();

    expect(container.read(selectedChatRoomProvider)?.id, 'research-lab');
    expect(
      find.byKey(const ValueKey('chat-panel-research-lab')),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byIcon(Icons.person).first);
    await tester.pumpAndSettle();

    expect(container.read(activeMessengerTabProvider), MessengerTab.friends);
    expect(container.read(selectedChatRoomProvider)?.id, 'research-lab');
    expect(
      find.byKey(const ValueKey('chat-panel-research-lab')),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pumpAndSettle();

    expect(find.text('AVA 정보'), findsOneWidget);
    expect(find.text('카카오톡 정보'), findsNothing);
    expect(
      tester.getBottomLeft(find.text('AVA 정보')).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('bottom-banner-image'))).dy,
      ),
    );
  });

  testWidgets('compacts desktop notifications even when a chat room is open', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final nativeCalls = <String>[];
    const windowChannel = MethodChannel('ava/window');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      (call) async {
        nativeCalls.add(call.method);
        return _nativeMenuResult(call);
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowChannel,
        null,
      );
    });

    final container = _messengerTestContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessengerPage()),
      ),
    );
    await tester.pumpAndSettle();

    final room = container
        .read(chatRoomsProvider)
        .firstWhere((room) => room.id == 'ra-team');
    container
        .read(activeMessengerTabProvider.notifier)
        .setTab(MessengerTab.chats);
    container.read(selectedChatRoomProvider.notifier).open(room);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-panel-ra-team')), findsOneWidget);
    expect(nativeCalls, contains('expandMessenger'));

    nativeCalls.clear();
    await tester.tap(
      find.byKey(const ValueKey('side-nav-notifications-button')),
    );
    await tester.pumpAndSettle();

    expect(container.read(selectedChatRoomProvider)?.id, 'ra-team');
    expect(find.byKey(const ValueKey('chat-panel-ra-team')), findsNothing);
    expect(nativeCalls, contains('compactMessenger'));

    nativeCalls.clear();
    await tester.tap(find.byIcon(Icons.chat_bubble).first);
    await tester.pumpAndSettle();

    expect(container.read(activeMessengerTabProvider), MessengerTab.chats);
    expect(container.read(selectedChatRoomProvider)?.id, 'ra-team');
    expect(find.byKey(const ValueKey('chat-panel-ra-team')), findsOneWidget);
    expect(nativeCalls, isNot(contains('compactMessenger')));
  });

  testWidgets('uses mobile single-pane chat navigation', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = _messengerTestContainer();
    addTearDown(container.dispose);
    const windowChannel = MethodChannel('ava/window');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      (call) async => _nativeMenuResult(call),
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowChannel,
        null,
      );
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessengerPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mobile-nav-friends')), findsOneWidget);
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('mobile-bottom-nav'))).dy,
      tester.view.physicalSize.height,
    );
    expect(
      find.byKey(const ValueKey('mobile-chat-panel-ra-team')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('mobile-nav-chats')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-room-ra-team')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-room-ra-team')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile-chat-panel-ra-team')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mobile-nav-chats')), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile-composer-tools-toggle')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile-composer-root'))).width,
      390,
    );
    expect(
      tester
          .widget<Material>(find.byKey(const ValueKey('mobile-composer-root')))
          .color,
      Colors.white,
    );
    expect(
      find.byKey(const ValueKey('mobile-composer-tools-menu')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('mobile-composer-tools-toggle')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(
      find.byKey(const ValueKey('mobile-composer-tools-menu')),
      findsOneWidget,
    );
    expect(find.text('파일'), findsOneWidget);

    final toolsMenu = tester.widget<Container>(
      find.byKey(const ValueKey('mobile-composer-tools-menu')),
    );
    expect(
      (toolsMenu.decoration! as BoxDecoration).color,
      const Color(0xFFF7F9FC),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(
      find.byKey(const ValueKey('mobile-composer-tools-menu')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('mobile-chat-back')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile-chat-panel-ra-team')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('mobile-nav-chats')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-room-ra-team')), findsOneWidget);
  });

  testWidgets('opens mobile AZOOM from the messenger bottom nav', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = _messengerTestContainer();
    addTearDown(container.dispose);
    const windowChannel = MethodChannel('ava/window');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      (call) async => _nativeMenuResult(call),
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowChannel,
        null,
      );
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessengerPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile-nav-azoom')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(container.read(activeMessengerTabProvider), MessengerTab.azoom);
    expect(find.byKey(const ValueKey('azoom-mobile-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('azoom-mobile-channel-list')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mobile-bottom-nav')), findsNothing);
  });

  testWidgets('keeps mobile AZOOM above any stale chat panel state', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = _messengerTestContainer();
    addTearDown(container.dispose);
    const windowChannel = MethodChannel('ava/window');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      (call) async => _nativeMenuResult(call),
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowChannel,
        null,
      );
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessengerPage()),
      ),
    );
    await tester.pumpAndSettle();

    container
        .read(selectedChatRoomProvider.notifier)
        .open(container.read(chatRoomsProvider).first);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile-chat-panel-ra-team')),
      findsOneWidget,
    );

    container
        .read(activeMessengerTabProvider.notifier)
        .setTab(MessengerTab.azoom);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(container.read(activeMessengerTabProvider), MessengerTab.azoom);
    expect(find.byKey(const ValueKey('azoom-mobile-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('azoom-mobile-channel-list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-chat-panel-ra-team')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('mobile-bottom-nav')), findsNothing);
  });

  testWidgets('uses mobile AZOOM channel list and voice sheets', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AzoomPage(
              currentUser: PersonProfile(
                id: 'mobile-user',
                name: 'J Y J',
                email: 'mobile@ava.local',
                color: Color(0xFF7AA06A),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const ValueKey('azoom-mobile-rail')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('azoom-mobile-rail-transcripts')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('azoom-mobile-rail-calendar')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('azoom-mobile-nav-chats')), findsNothing);
    expect(
      find.byKey(const ValueKey('azoom-mobile-channel-list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('azoom-mobile-bottom-nav')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('azoom-mobile-transcripts-header')),
      findsOneWidget,
    );
    expect(find.text('\uC11C\uBC84 \uBD80\uC2A4\uD2B8'), findsNothing);
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('azoom-mobile-header-invite')))
          .dx,
      greaterThan(tester.getTopLeft(find.text('\uAC80\uC0C9\uD558\uAE30')).dx),
    );
    expect(
      tester
          .getBottomLeft(
            find.byKey(const ValueKey('azoom-mobile-rail-profile')),
          )
          .dy,
      lessThanOrEqualTo(
        tester
            .getTopLeft(find.byKey(const ValueKey('azoom-mobile-bottom-nav')))
            .dy,
      ),
    );
    final channelCard = tester.widget<ClipRRect>(
      find.byKey(const ValueKey('azoom-mobile-channel-card')),
    );
    expect(
      channelCard.borderRadius,
      const BorderRadius.only(topLeft: Radius.circular(18)),
    );
    expect(
      find.byKey(const ValueKey('azoom-mobile-join-all-staff')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('azoom-mobile-voice-all-staff')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(
      find.byKey(const ValueKey('azoom-mobile-join-all-staff')),
      findsOneWidget,
    );
    final joinSheet = find.byKey(
      const ValueKey('azoom-mobile-voice-join-sheet'),
    );
    expect(tester.getTopLeft(joinSheet).dx, 0);
    expect(tester.getSize(joinSheet).width, 390);
    expect(
      find.byKey(const ValueKey('azoom-mobile-join-dismiss-layer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('azoom-mobile-voice-room-all-staff')),
      findsNothing,
    );

    await tester.tapAt(const Offset(180, 180));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    expect(
      find.byKey(const ValueKey('azoom-mobile-join-all-staff')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('azoom-mobile-voice-all-staff')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(
      find.byKey(const ValueKey('azoom-mobile-join-all-staff')),
      findsOneWidget,
    );

    await tester.tap(
      find.text('\uC74C\uC131 \uCC44\uB110 \uCC38\uAC00\uD558\uAE30'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(
      find.byKey(const ValueKey('azoom-mobile-voice-room-all-staff')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('azoom-mobile-mic-device-control')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('azoom-mobile-camera-device-control')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.call_end), findsOneWidget);
    expect(
      find.byKey(const ValueKey('azoom-mobile-voice-control-dock')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('azoom-mobile-voice-expanded-menu')),
      findsNothing,
    );

    await tester.drag(
      find.byKey(const ValueKey('azoom-mobile-voice-dock-drag-target')),
      const Offset(0, -520),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(
      find.byKey(const ValueKey('azoom-mobile-voice-expanded-menu')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.screen_share), findsOneWidget);
    expect(find.text('제공 ABBA-S'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('azoom-mobile-voice-expanded-menu')),
      const Offset(0, 520),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(
      find.byKey(const ValueKey('azoom-mobile-voice-expanded-menu')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('azoom-mobile-join-all-staff')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('azoom-mobile-notiva-header-button')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('azoom-mobile-notiva-overlay')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('azoom-notiva-ai-panel')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('azoom-mobile-notiva-overlay')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('azoom-mobile-voice-collapse')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(
      find.byKey(const ValueKey('azoom-mobile-voice-room-all-staff')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('azoom-mobile-channel-list')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('azoom-mobile-voice-all-staff')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(
      find.byKey(const ValueKey('azoom-mobile-voice-room-all-staff')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('azoom-mobile-join-all-staff')),
      findsNothing,
    );
  });
}

Future<void> _sendWindowMethodCall(
  WidgetTester tester,
  String method,
  Map<String, Object?> arguments,
) async {
  final data = const StandardMethodCodec().encodeMethodCall(
    MethodCall(method, arguments),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'ava/window',
    data,
    (_) {},
  );
}

Future<void> _openDirectChatFromProfile(WidgetTester tester) async {
  if (Platform.isWindows) {
    await _sendWindowMethodCall(tester, 'profilePopupAction', {
      'action': 'directChat',
    });
  } else {
    await tester.tap(find.text('1:1 채팅').last);
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

String? _nativeMenuResult(MethodCall call) {
  if (call.method != 'showNativeMenu') {
    return null;
  }
  final arguments = (call.arguments as Map?)?.cast<Object?, Object?>();
  final items = arguments?['items'] as List? ?? const [];
  final ids = {
    for (final item in items)
      if (item is Map) (item['value'] ?? item['id'])?.toString(),
  };
  if (ids.contains('notice')) {
    return 'notice';
  }
  if (ids.contains('pin')) {
    return 'pin';
  }
  return null;
}

ProviderContainer _messengerTestContainer() {
  return ProviderContainer(
    overrides: [
      chatRoomsProvider.overrideWith(TestChatRooms.new),
      friendGroupsProvider.overrideWithValue(userGroups),
      updatedUserProfilesProvider.overrideWithValue(updatedUsers),
    ],
  );
}

ProviderContainer _directChatTestContainer(_FakeDirectChatApi chatApi) {
  return ProviderContainer(
    overrides: [
      chatRoomsProvider.overrideWith(TestChatRooms.new),
      friendGroupsProvider.overrideWithValue(userGroups),
      updatedUserProfilesProvider.overrideWithValue(updatedUsers),
      authControllerProvider.overrideWith(_DirectChatAuthController.new),
      chatApiProvider.overrideWithValue(chatApi),
      appConfigProvider.overrideWithValue(
        const AppConfig(apiBaseUrl: '', websocketUrl: ''),
      ),
    ],
  );
}

ProviderContainer _adminMessengerTestContainer() {
  return ProviderContainer(
    overrides: [
      chatRoomsProvider.overrideWith(TestChatRooms.new),
      currentUserProfileProvider.overrideWithValue(
        const PersonProfile(
          id: 'admin-user',
          name: '관리자',
          color: Color(0xFF4663CF),
          email: 'admin@ava.local',
          role: 'ADMIN',
          companyName: 'ABBA-S',
        ),
      ),
      authControllerProvider.overrideWith(_AdminTestAuthController.new),
      adminApiProvider.overrideWithValue(_FakeAdminApi()),
    ],
  );
}

class TestChatRooms extends ChatRooms {
  @override
  List<ChatRoom> build() => chatRooms;
}

class _AdminTestAuthController extends AuthController {
  @override
  Future<AuthState> build() async {
    return AuthState(
      session: AuthSession(
        accessToken: 'admin-access-token',
        refreshToken: 'admin-refresh-token',
        expiresAt: DateTime(2026, 5, 19, 12),
        user: const AuthUser(
          id: 'admin-user',
          email: 'admin@ava.local',
          displayName: '관리자',
          role: 'ADMIN',
          companyName: 'ABBA-S',
        ),
      ),
    );
  }
}

class _DirectChatAuthController extends AuthController {
  @override
  Future<AuthState> build() async {
    return AuthState(
      session: AuthSession(
        accessToken: 'direct-chat-token',
        refreshToken: 'direct-chat-refresh',
        expiresAt: DateTime(2026, 5, 27, 12),
        user: const AuthUser(
          id: 'current-user',
          email: 'current@ava.local',
          displayName: 'Current User',
          role: 'USER',
          companyName: 'ABBA-S',
        ),
      ),
    );
  }
}

class _LoggedOutAuthController extends AuthController {
  @override
  Future<AuthState> build() async {
    return const AuthState();
  }
}

class _FakeDirectChatApi extends ChatApi {
  _FakeDirectChatApi() : super(Dio(), null);

  int directRoomCalls = 0;

  @override
  Future<ChatRoomDto> startDirectRoom({
    required String accessToken,
    required String targetName,
    String? targetUserId,
    String? targetEmail,
  }) async {
    directRoomCalls += 1;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return ChatRoomDto(
      code: 'direct-test-target',
      title: targetName,
      type: 'DIRECT',
      participantCount: 2,
      pinned: false,
      pinnedAt: null,
      lastMessage: '',
      lastMessageAt: null,
      lastMessageSpoiler: false,
      avatarImageUrl: '',
      notice: null,
      members: [
        _testUserProfileDto(
          id: 'current-user',
          email: 'current@ava.local',
          name: 'Current User',
        ),
        _testUserProfileDto(
          id: targetUserId ?? 'target-user',
          email: targetEmail ?? 'target@ava.local',
          name: targetName,
        ),
      ],
      unreadCount: 0,
      mentioned: false,
    );
  }

  @override
  Future<List<ChatMessageDto>> messages({
    required String accessToken,
    required String roomCode,
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

UserProfileDto _testUserProfileDto({
  required String id,
  required String email,
  required String name,
}) {
  return UserProfileDto(
    id: id,
    email: email,
    name: name,
    displayName: name,
    nickname: '',
    phoneNumber: '',
    role: 'USER',
    companyName: 'ABBA-S',
    position: '',
    department: '',
    birthDate: null,
    status: 'online',
    avatarColor: '#7AA06A',
    statusMessage: '',
    avatarImageUrl: '',
    profileBackgroundColor: '#7AA06A',
    profileBackgroundImageUrl: '',
    blocked: false,
  );
}

class _UnspecifiedTestAuthController extends AuthController {
  @override
  Future<AuthState> build() async {
    return AuthState(
      session: AuthSession(
        accessToken: 'test1-access-token',
        refreshToken: 'test1-refresh-token',
        expiresAt: DateTime(2026, 5, 25, 12),
        user: const AuthUser(
          id: 'test1-user',
          email: 'test1@ava.local',
          displayName: '\uD14C\uC2A4\uD2B81',
          role: 'USER',
          companyName: 'ABBA-S',
        ),
      ),
    );
  }
}

class _UnspecifiedTestUserProfiles extends UserProfiles {
  @override
  Future<List<PersonProfile>> build() async {
    return const [
      PersonProfile(
        id: 'research-user',
        name: '\uC5F0\uAD6C\uC18C \uC720\uC800',
        color: Color(0xFF7AA06A),
        email: 'research@ava.local',
        department: '\uC5F0\uAD6C\uC18C',
      ),
      PersonProfile(
        id: 'test1-user',
        name: '\uD14C\uC2A4\uD2B81',
        color: Color(0xFF4663CF),
        email: 'test1@ava.local',
      ),
      PersonProfile(
        id: 'another-unspecified-user',
        name: '\uAE30\uD0C0 \uC720\uC800',
        color: Color(0xFF8BA6C9),
        email: 'another@ava.local',
      ),
    ];
  }
}

class _FakeAdminApi extends AdminApi {
  _FakeAdminApi() : super(Dio());

  @override
  Future<AdminOverviewDto> overview(String accessToken) async {
    return const AdminOverviewDto(
      totalUsers: 2,
      enabledUsers: 1,
      disabledUsers: 1,
      chatRooms: 0,
      chatMessages: 0,
      unreadNotifications: 0,
    );
  }

  @override
  Future<List<AdminUserDto>> pendingApprovals(String accessToken) async {
    return [_adminUser('pending-user', enabled: false)];
  }

  @override
  Future<List<AdminUserDto>> users(String accessToken) async {
    return [
      _adminUser('admin-user', role: 'ADMIN'),
      _adminUser('pending-user', enabled: false),
    ];
  }

  AdminUserDto _adminUser(
    String id, {
    String role = 'USER',
    bool enabled = true,
  }) {
    return AdminUserDto(
      id: id,
      email: '$id@ava.local',
      displayName: id == 'admin-user' ? '관리자' : '승인대기',
      role: role,
      enabled: enabled,
      companyName: 'ABBA-S',
      department: '개발팀',
      position: '매니저',
      status: enabled ? 'ACTIVE' : 'PENDING',
      createdAt: DateTime(2026, 5, 19, 12),
    );
  }
}

Color? _chatRoomTileColor(WidgetTester tester, String id) {
  final tile = find.byKey(ValueKey('chat-room-$id'));
  final material = tester.widget<Material>(
    find
        .descendant(
          of: tile,
          matching: find.byWidgetPredicate(
            (widget) => widget is Material && widget.color != null,
          ),
        )
        .first,
  );

  return material.color;
}

String? _sideNavUnreadBadgeText(WidgetTester tester) {
  final badge = find.byKey(const ValueKey('side-nav-unread-badge'));
  if (badge.evaluate().isEmpty) {
    return null;
  }

  final text = tester.widget<Text>(
    find.descendant(of: badge, matching: find.byType(Text)).first,
  );
  return text.data;
}
