import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_models.dart';

final authSessionStoreProvider = Provider<AuthSessionStore>((ref) {
  return const AuthSessionStore();
});

class AuthSessionStore {
  const AuthSessionStore();

  Future<AuthSession?> read() async {
    if (kIsWeb) {
      return null;
    }

    final file = _sessionFile();
    if (!await file.exists()) {
      return null;
    }

    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) {
        return null;
      }
      return AuthSession.fromJson(json.cast<String, dynamic>());
    } on Object {
      return null;
    }
  }

  Future<void> write(AuthSession session) async {
    if (kIsWeb) {
      return;
    }

    final file = _sessionFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(session.toJson()));
  }

  Future<void> clear() async {
    if (kIsWeb) {
      return;
    }

    final file = _sessionFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  File _sessionFile() {
    final appData = Platform.environment['APPDATA'];
    final base = appData == null || appData.isEmpty
        ? Directory.systemTemp.path
        : appData;
    return File(
      '$base${Platform.pathSeparator}AVA${Platform.pathSeparator}session.json',
    );
  }
}
