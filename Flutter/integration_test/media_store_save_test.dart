import 'dart:convert';
import 'dart:io';

import 'package:ava_flutter/src/platform/window_control.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saves image video and file attachments to shared storage', (
    tester,
  ) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final temp = Directory.systemTemp;

    final image = File('${temp.path}/ava_media_probe_$stamp.png');
    await image.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR42mP8z8AABQMBgQn2U9UAAAAASUVORK5CYII=',
      ),
      flush: true,
    );

    final video = File('${temp.path}/ava_media_probe_$stamp.mp4');
    await video.writeAsBytes(<int>[
      0x00,
      0x00,
      0x00,
      0x18,
      0x66,
      0x74,
      0x79,
      0x70,
      0x69,
      0x73,
      0x6F,
      0x6D,
      0x00,
      0x00,
      0x02,
      0x00,
      0x69,
      0x73,
      0x6F,
      0x6D,
      0x69,
      0x73,
      0x6F,
      0x32,
    ], flush: true);

    final text = File('${temp.path}/ava_media_probe_$stamp.txt');
    await text.writeAsString('ava media probe $stamp', flush: true);

    final imageResult = await WindowControl.saveAttachmentToMediaStore(
      sourcePath: image.path,
      fileName: image.uri.pathSegments.last,
      mimeType: 'image/png',
    );
    final videoResult = await WindowControl.saveAttachmentToMediaStore(
      sourcePath: video.path,
      fileName: video.uri.pathSegments.last,
      mimeType: 'video/mp4',
      notify: true,
    );
    final textResult = await WindowControl.saveAttachmentToMediaStore(
      sourcePath: text.path,
      fileName: text.uri.pathSegments.last,
      mimeType: 'text/plain',
      notify: true,
    );

    expect(imageResult, contains('Pictures/AVA'));
    expect(videoResult, contains('Movies/AVA'));
    expect(textResult, contains('Download/AVA'));
  });
}
