import 'dart:ui';

import 'package:ava_flutter/src/app/ava_app.dart';
import 'package:ava_flutter/src/app/router.dart';
import 'package:ava_flutter/src/features/messenger/domain/messenger_models.dart';
import 'package:ava_flutter/src/features/messenger/presentation/messenger_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('orders active chat rooms after pinned rooms', () {
    final container = ProviderContainer();
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

  testWidgets('shows collapsible user groups and opens direct chat', (
    WidgetTester tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AvaApp()),
    );
    container.read(appRouterProvider).go('/messenger');
    await tester.pumpAndSettle();

    expect(find.text('업데이트한 유저'), findsOneWidget);
    expect(find.text('한국 개발부'), findsOneWidget);
    expect(find.text('RA 팀'), findsOneWidget);
    expect(find.text('선물하기'), findsNothing);
    expect(find.text('업무 가능'), findsNothing);
    expect(find.byKey(const ValueKey('updated-user-메롱이')), findsOneWidget);
    expect(find.byKey(const ValueKey('user-row-장유종')), findsOneWidget);
    expect(find.text('온라인'), findsWidgets);

    await tester.tap(find.text('한국 개발부'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-row-장유종')), findsNothing);

    await tester.tap(find.byIcon(Icons.chat_bubble).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-row-장유종')), findsNothing);

    await tester.tap(find.text('한국 개발부'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-row-장유종')), findsOneWidget);

    final user = find.byKey(const ValueKey('updated-user-메롱이'));
    await tester.tap(user);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(user);
    await tester.pumpAndSettle();

    expect(container.read(selectedChatRoomProvider)?.title, '메롱이');
    expect(find.byKey(const ValueKey('chat-panel-direct-메롱이')), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    final openedDirectRoom = container.read(selectedChatRoomProvider)!;
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
    await tester.tap(find.byType(FilledButton).last);
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

  testWidgets('shows messenger shell and opens chat panel', (
    WidgetTester tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AvaApp()),
    );
    container.read(appRouterProvider).go('/messenger');
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

    await tester.tap(find.byKey(const ValueKey('chat-filter-unread')));
    await tester.pumpAndSettle();

    expect(container.read(unreadOnlyFilterProvider), isTrue);
    expect(find.byKey(const ValueKey('chat-room-ra-team')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-room-kim-minjae')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-room-research-lab')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chat-filter-all')));
    await tester.pumpAndSettle();

    final designTile = find.byKey(const ValueKey('chat-room-design-team'));
    await tester.tapAt(tester.getCenter(designTile), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('채팅방 상단 고정'), findsOneWidget);

    final menuHover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await menuHover.addPointer(
      location: tester.getCenter(find.byKey(const ValueKey('room-menu-pin'))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(_roomMenuItemColor(tester, 'pin'), const Color(0xFFEFEFEF));
    await menuHover.removePointer();

    await tester.tap(find.text('채팅방 상단 고정'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: designTile, matching: find.byIcon(Icons.push_pin)),
      findsOneWidget,
    );

    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer(location: tester.getCenter(roomTile));
    await tester.pump();
    expect(_chatRoomTileColor(tester, 'ra-team'), const Color(0xFFEFEFEF));

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

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('chat-message-1'))),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('message-menu-notice')), findsOneWidget);

    final messageMenuHover = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await messageMenuHover.addPointer(
      location: tester.getCenter(
        find.byKey(const ValueKey('message-menu-notice')),
      ),
    );
    await tester.pump();
    expect(_messageMenuItemColor(tester, 'notice'), const Color(0xFFEFEFEF));
    await messageMenuHover.removePointer();

    await tester.tap(find.byKey(const ValueKey('message-menu-notice')));
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
      lessThan(tester.getTopLeft(find.byType(Image)).dy),
    );
  });
}

Color? _chatRoomTileColor(WidgetTester tester, String id) {
  final tile = find.byKey(ValueKey('chat-room-$id'));
  final container = tester.widget<Container>(
    find
        .descendant(
          of: tile,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.padding == const EdgeInsets.fromLTRB(18, 12, 12, 8),
          ),
        )
        .first,
  );

  return container.color;
}

Color? _roomMenuItemColor(WidgetTester tester, String id) {
  final menuItem = find.byKey(ValueKey('room-menu-$id'));
  final container = tester.widget<AnimatedContainer>(
    find
        .descendant(of: menuItem, matching: find.byType(AnimatedContainer))
        .first,
  );

  return (container.decoration as BoxDecoration?)?.color;
}

Color? _messageMenuItemColor(WidgetTester tester, String id) {
  final menuItem = find.byKey(ValueKey('message-menu-$id'));
  final container = tester.widget<Container>(
    find.descendant(of: menuItem, matching: find.byType(Container)).first,
  );

  return container.color;
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
