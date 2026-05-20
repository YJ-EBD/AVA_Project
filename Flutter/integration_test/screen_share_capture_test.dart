import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:integration_test/integration_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('creates a LiveKit screen share track from a desktop source', (
    tester,
  ) async {
    final sources = await rtc.desktopCapturer.getSources(
      types: [rtc.SourceType.Screen],
    );

    expect(sources, isNotEmpty);

    final track = await lk.LocalVideoTrack.createScreenShareTrack(
      lk.ScreenShareCaptureOptions(
        sourceId: sources.first.id,
        maxFrameRate: 5,
      ),
    );
    addTearDown(track.stop);

    expect(track.source, lk.TrackSource.screenShareVideo);
    expect(track.mediaStreamTrack.kind, 'video');
  });
}
