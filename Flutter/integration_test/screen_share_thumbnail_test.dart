import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ava_flutter/src/platform/window_control.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:integration_test/integration_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

const _sourceTypes = [rtc.SourceType.Window, rtc.SourceType.Screen];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'loads screen share thumbnails before, during fullscreen, and after restart',
    (tester) async {
      addTearDown(() async {
        await WindowControl.setAzoomFullscreen(false);
      });

      final outputDir = Directory('build/azoom_thumbnail_smoke');
      if (outputDir.existsSync()) {
        outputDir.deleteSync(recursive: true);
      }
      outputDir.createSync(recursive: true);

      final normal = await _probeThumbnails(
        label: 'normal',
        outputDir: outputDir,
      );
      expect(normal.sources, isNotEmpty);
      expect(normal.thumbnailCount, greaterThan(0));

      await WindowControl.setAzoomFullscreen(true);
      await tester.pump(const Duration(milliseconds: 700));
      final fullscreen = await _probeThumbnails(
        label: 'fullscreen',
        outputDir: outputDir,
      );
      expect(fullscreen.sources, isNotEmpty);
      expect(fullscreen.thumbnailCount, greaterThan(0));

      final shareSource =
          fullscreen.firstThumbnailSource ?? normal.sources.first;
      final track = await lk.LocalVideoTrack.createScreenShareTrack(
        lk.ScreenShareCaptureOptions(sourceId: shareSource.id, maxFrameRate: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await track.stop();
      await Future<void>.delayed(const Duration(milliseconds: 500));

      await WindowControl.setAzoomFullscreen(false);
      await tester.pump(const Duration(milliseconds: 500));
      final reopened = await _probeThumbnails(
        label: 'reopen_after_stop',
        outputDir: outputDir,
      );
      expect(reopened.sources, isNotEmpty);
      expect(reopened.thumbnailCount, greaterThan(0));

      // Keep one concise line for shell verification logs.
      // ignore: avoid_print
      print(
        'AZOOM_THUMBNAIL_SMOKE normal=${normal.thumbnailCount}/${normal.sources.length} '
        'fullscreen=${fullscreen.thumbnailCount}/${fullscreen.sources.length} '
        'reopen=${reopened.thumbnailCount}/${reopened.sources.length} '
        'dir=${outputDir.absolute.path}',
      );
    },
  );
}

Future<_ThumbnailProbeResult> _probeThumbnails({
  required String label,
  required Directory outputDir,
}) async {
  final thumbnails = <String, Uint8List>{};
  final subscriptions = <StreamSubscription<rtc.DesktopCapturerSource>>[];
  try {
    subscriptions.add(
      rtc.desktopCapturer.onThumbnailChanged.stream.listen((source) {
        final thumbnail = source.thumbnail;
        if (thumbnail != null && thumbnail.isNotEmpty) {
          thumbnails[source.id] = thumbnail;
        }
      }),
    );

    var sources = await rtc.desktopCapturer.getSources(
      types: _sourceTypes,
      thumbnailSize: rtc.ThumbnailSize(640, 360),
    );
    for (final source in sources) {
      final thumbnail = source.thumbnail;
      if (thumbnail != null && thumbnail.isNotEmpty) {
        thumbnails[source.id] = thumbnail;
      }
    }

    for (var attempt = 0; attempt < 18; attempt++) {
      if (sources.isNotEmpty && thumbnails.length >= sources.length) {
        break;
      }
      await rtc.desktopCapturer.updateSources(types: _sourceTypes);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      sources = await rtc.desktopCapturer.getSources(
        types: _sourceTypes,
        thumbnailSize: rtc.ThumbnailSize(640, 360),
      );
      for (final source in sources) {
        final thumbnail = source.thumbnail;
        if (thumbnail != null && thumbnail.isNotEmpty) {
          thumbnails[source.id] = thumbnail;
        }
      }
    }

    var saved = 0;
    rtc.DesktopCapturerSource? firstThumbnailSource;
    for (final source in sources) {
      final thumbnail = thumbnails[source.id];
      if (thumbnail == null || thumbnail.isEmpty) {
        continue;
      }
      firstThumbnailSource ??= source;
      final fileName = '${label}_${saved}_${_safeFilePart(source.name)}.jpg';
      File('${outputDir.path}/$fileName').writeAsBytesSync(thumbnail);
      saved += 1;
      if (saved >= 4) {
        break;
      }
    }

    return _ThumbnailProbeResult(
      sources: sources,
      thumbnailCount: thumbnails.length,
      firstThumbnailSource: firstThumbnailSource,
    );
  } finally {
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
  }
}

String _safeFilePart(String value) {
  final safe = value
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
      .replaceAll(RegExp(r'\s+'), '_')
      .trim();
  if (safe.isEmpty) {
    return 'source';
  }
  return safe.length > 48 ? safe.substring(0, 48) : safe;
}

class _ThumbnailProbeResult {
  const _ThumbnailProbeResult({
    required this.sources,
    required this.thumbnailCount,
    required this.firstThumbnailSource,
  });

  final List<rtc.DesktopCapturerSource> sources;
  final int thumbnailCount;
  final rtc.DesktopCapturerSource? firstThumbnailSource;
}
