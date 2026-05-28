import 'package:ava_flutter/src/features/azoom/presentation/azoom_page.dart';
import 'package:ava_flutter/src/features/messenger/domain/messenger_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const profile = PersonProfile(
    name: 'Tester',
    email: 'tester@example.test',
    color: Color(0xFF7AA06A),
    status: 'online',
  );

  testWidgets('mobile AZOOM firework button shows Konfetti overlay', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SizedBox(
            width: 390,
            height: 844,
            child: AzoomPage(
              currentUser: profile,
              bypassAndroidVoicePermissionChecks: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final voiceChannel = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('azoom-mobile-voice-');
    }).first;

    await tester.tap(voiceChannel);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('azoom-mobile-voice-join-button')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('azoom-mobile-firework-button')),
    );
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.tap(
      find.byKey(const ValueKey('azoom-mobile-firework-button')),
    );
    await tester.pump(const Duration(milliseconds: 1200));

    expect(
      find.byKey(const ValueKey('azoom-firework-overlay')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 2200));
  });
}
