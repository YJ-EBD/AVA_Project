import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ava_flutter/src/config/app_version.dart';

void main() {
  test('AppVersion defaults match pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull);
    expect(AppVersion.name, match!.group(1));
    expect(AppVersion.buildNumber, int.parse(match.group(2) ?? '1'));
  });
}
