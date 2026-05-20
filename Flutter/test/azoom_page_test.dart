import 'dart:ui' as ui;

import 'package:ava_flutter/src/features/azoom/presentation/azoom_page.dart';
import 'package:ava_flutter/src/features/azoom/presentation/azoom_screen_share_dialog.dart';
import 'package:ava_flutter/src/features/messenger/domain/messenger_models.dart';
import 'package:ava_flutter/src/features/messenger/presentation/messenger_page.dart';
import 'package:ava_flutter/src/features/messenger/presentation/widgets/messenger_side_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testProfile = PersonProfile(
    name: '장유종',
    email: 'amos5105@naver.com',
    color: Color(0xFF7AA06A),
    status: '온라인',
  );

  testWidgets('renders AZOOM discord-style layout at desktop size', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 688);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SizedBox(
            width: 1280,
            height: 688,
            child: AzoomPage(currentUser: testProfile),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('azoom-page')), findsOneWidget);
    expect(find.text('AZOOM'), findsOneWidget);
    expect(find.text('전직원 회의'), findsWidgets);
    expect(find.text('RA 회의'), findsOneWidget);
    expect(find.text('연구소 회의'), findsOneWidget);
    expect(find.text('전 직원'), findsOneWidget);
    expect(find.text('RA 팀'), findsOneWidget);
    expect(find.text('연구소'), findsOneWidget);
    expect(find.text('업춘식'), findsNothing);
    expect(find.text('노래'), findsNothing);
    expect(find.text('0군'), findsNothing);
    expect(find.text('만'), findsNothing);
    expect(find.text('영'), findsNothing);
    expect(find.text('자'), findsNothing);
    expect(find.byKey(const ValueKey('azoom-user-panel-name')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('azoom-user-panel-name')))
          .data,
      '장유종',
    );
    expect(
      find.byKey(const ValueKey('azoom-user-panel-status')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('azoom-user-panel-status')))
          .data,
      '온라인',
    );
    expect(find.text('#전직원 회의에 메시지 보내기'), findsOneWidget);
    expect(find.text('전직원 회의 검색'), findsOneWidget);

    expect(
      tester.widget<ColoredBox>(find.byKey(const ValueKey('azoom-page'))).color,
      const Color(0xFF313338),
    );
    expect(
      tester
          .widget<Container>(find.byKey(const ValueKey('azoom-server-rail')))
          .color,
      const Color(0xFF232428),
    );
    expect(
      tester
          .widget<Container>(
            find.byKey(const ValueKey('azoom-channel-sidebar')),
          )
          .color,
      const Color(0xFF2B2D31),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('azoom-server-rail'))).width,
      72,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('azoom-channel-sidebar'))).width,
      290,
    );
    expect(find.byKey(const ValueKey('azoom-playlist-preview')), findsNothing);

    final composerBottom = tester.getBottomLeft(
      find.byKey(const ValueKey('azoom-composer-bar')),
    );
    expect(composerBottom.dy, 688);

    final composerInput = tester.widget<Container>(
      find.byKey(const ValueKey('azoom-composer-input')),
    );
    expect(
      (composerInput.decoration! as BoxDecoration).color,
      const Color(0xFF383A40),
    );
  });

  testWidgets('updates AZOOM chat chrome when a meeting channel is selected', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 688);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SizedBox(
            width: 1280,
            height: 688,
            child: AzoomPage(currentUser: testProfile),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('azoom-text-channel-연구소 회의')));
    await tester.pump();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('azoom-channel-title')))
          .data,
      '연구소 회의',
    );
    expect(find.text('연구소 회의 검색'), findsOneWidget);
    expect(find.text('#연구소 회의에 메시지 보내기'), findsOneWidget);
    expect(find.text('연구소 회의 채널을 초기화했습니다.'), findsOneWidget);
  });

  testWidgets('uses Discord voice surface inside AZOOM before fullscreen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 688);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SizedBox(
            width: 1280,
            height: 688,
            child: AzoomPage(currentUser: testProfile),
          ),
        ),
      ),
    );

    final voiceChannel = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('azoom-voice-channel-');
    }).first;

    await tester.tap(voiceChannel);
    await tester.pump();

    expect(
      tester.widget<ColoredBox>(find.byKey(const ValueKey('azoom-page'))).color,
      const Color(0xFF313338),
    );
    expect(find.byKey(const ValueKey('azoom-server-rail')), findsOneWidget);
    expect(find.byKey(const ValueKey('azoom-channel-sidebar')), findsOneWidget);
    expect(
      tester
          .widget<ColoredBox>(find.byKey(const ValueKey('azoom-voice-surface')))
          .color,
      Colors.black,
    );
    expect(find.byKey(const ValueKey('azoom-voice-title')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('azoom-voice-room-surface')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('azoom-ava-dark-activity-art')),
      findsOneWidget,
    );
  });

  testWidgets('renders Discord-style AZOOM voice sidebar controls', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 688);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SizedBox(
            width: 1280,
            height: 688,
            child: AzoomPage(currentUser: testProfile),
          ),
        ),
      ),
    );

    final voiceChannel = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('azoom-voice-channel-');
    }).first;

    await tester.tap(voiceChannel);
    await tester.pump();

    final dock = find.byKey(const ValueKey('azoom-left-bottom-dock'));
    expect(dock, findsOneWidget);
    expect(tester.getTopLeft(dock).dx, 6);
    expect(tester.getSize(dock).width, 350);
    expect(
      tester.getTopRight(dock).dx,
      lessThanOrEqualTo(
        tester
            .getTopRight(find.byKey(const ValueKey('azoom-channel-sidebar')))
            .dx,
      ),
    );
    expect(
      tester.getTopLeft(dock).dx,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('azoom-channel-sidebar')))
            .dx,
      ),
    );
    expect(
      find.byKey(const ValueKey('azoom-voice-connection-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('azoom-sidebar-mic-device-control')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('azoom-sidebar-deafen-device-control')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('azoom-sidebar-user-settings-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('azoom-sidebar-participant-deafened-icon')),
      findsNothing,
    );
  });

  testWidgets('keeps AZOOM voice overlay controls raised and stable on hover', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 688);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SizedBox(
            width: 1280,
            height: 688,
            child: AzoomPage(currentUser: testProfile),
          ),
        ),
      ),
    );

    final voiceChannel = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('azoom-voice-channel-');
    }).first;

    await tester.tap(voiceChannel);
    await tester.pump();

    final surface = find.byKey(const ValueKey('azoom-voice-surface'));
    final gesture = await tester.createGesture(
      kind: ui.PointerDeviceKind.mouse,
    );
    addTearDown(() async {
      await gesture.removePointer();
    });

    await gesture.addPointer(location: tester.getCenter(surface));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(surface));
    await tester.pumpAndSettle();

    Offset controlsOffset() {
      return tester
          .widget<AnimatedSlide>(
            find.byKey(const ValueKey('azoom-voice-controls-slide')),
          )
          .offset;
    }

    expect(controlsOffset(), Offset.zero);

    final surfaceBottom = tester.getBottomLeft(surface).dy;
    final micBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('azoom-mic-device-control')))
        .dy;
    expect(surfaceBottom - micBottom, greaterThanOrEqualTo(16));

    final surfaceTopLeft = tester.getTopLeft(surface);
    await gesture.moveTo(
      Offset(surfaceTopLeft.dx - 16, surfaceTopLeft.dy + 48),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(controlsOffset(), Offset.zero);

    await tester.pump(const Duration(milliseconds: 260));
    await tester.pumpAndSettle();
    expect(controlsOffset(), const Offset(0, 1.15));
  });

  testWidgets('focuses a clicked AZOOM voice participant', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 688);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SizedBox(
            width: 1280,
            height: 688,
            child: AzoomPage(currentUser: testProfile),
          ),
        ),
      ),
    );

    final voiceChannel = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('azoom-voice-channel-');
    }).first;

    await tester.tap(voiceChannel);
    await tester.pump();

    final participantFrame = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('azoom-presence-participant-frame-') &&
          key.value.endsWith('-grid');
    }).first;

    await tester.tap(
      find
          .descendant(
            of: participantFrame,
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('azoom-voice-spotlight-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('azoom-voice-spotlight-strip')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('azoom-presence-participant-frame-') &&
            key.value.endsWith('-spotlight');
      }),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('azoom-presence-participant-frame-') &&
            key.value.endsWith('-thumbnail');
      }),
      findsOneWidget,
    );
  });

  testWidgets('renders Discord-style AZOOM screen share dialog chrome', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(959, 605);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: AzoomDiscordScreenShareSourceDialog()),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('azoom-screen-share-dialog')),
      findsOneWidget,
    );
    final dialogFrameSize = tester.getSize(
      find.byKey(const ValueKey('azoom-screen-share-dialog-frame')),
    );
    expect(dialogFrameSize.width, lessThanOrEqualTo(903));
    expect(dialogFrameSize.height, lessThanOrEqualTo(557));
    expect(
      find.byKey(const ValueKey('azoom-screen-share-tabs')),
      findsOneWidget,
    );
    expect(find.text('애플리케이션'), findsOneWidget);
    expect(find.text('전체 화면'), findsOneWidget);
    expect(find.text('기기'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('azoom-screen-share-footer')),
      findsOneWidget,
    );
    expect(find.text('SD'), findsOneWidget);
    expect(find.text('HD'), findsOneWidget);
    expect(find.text('공유'), findsOneWidget);
    expect(find.textContaining('Nitro'), findsNothing);
    expect(find.textContaining('AVA 회의 공유'), findsOneWidget);
  });

  testWidgets('selects AZOOM from the AVA side navigation', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SizedBox(
            width: 64,
            height: 686,
            child: MessengerSideNav(activeTab: MessengerTab.chats),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('side-nav-azoom-button')));
    await tester.pump();

    expect(container.read(activeMessengerTabProvider), MessengerTab.azoom);
  });

  testWidgets('restores the previous window size after leaving AZOOM', (
    tester,
  ) async {
    const channel = MethodChannel('ava/window');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessengerPage()),
      ),
    );
    await tester.pump();
    calls.clear();

    container
        .read(activeMessengerTabProvider.notifier)
        .setTab(MessengerTab.azoom);
    await tester.pump();

    container
        .read(activeMessengerTabProvider.notifier)
        .setTab(MessengerTab.avaAi);
    await tester.pump();

    expect(
      calls,
      containsAllInOrder(['openAzoomMessenger', 'restoreMessengerFromAzoom']),
    );
  });
}
