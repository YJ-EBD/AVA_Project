import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_models.dart';

final authSessionStoreProvider = Provider<AuthSessionStore>((ref) {
  return const AuthSessionStore();
});

class AuthSessionStore {
  const AuthSessionStore();

  static const _mobileSessionKey = 'ava.auth.session.v1';

  Future<AuthSession?> read() async {
    if (kIsWeb) {
      return null;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      final fromPrefs = await _readFromPreferences();
      if (fromPrefs != null) {
        return fromPrefs;
      }
      final legacy = await _readFromFile();
      if (legacy != null) {
        await write(legacy);
      }
      return legacy;
    }

    return _readFromFile();
  }

  Future<void> write(AuthSession session) async {
    if (kIsWeb) {
      return;
    }

    final payload = jsonEncode(session.toJson());
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_mobileSessionKey, payload);
        return;
      } on Object {
        // Fall back to the legacy file path if preferences are unavailable.
      }
    }

    final file = _sessionFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(payload);
  }

  Future<void> clear() async {
    if (kIsWeb) {
      return;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_mobileSessionKey);
      } on Object {
        // Continue with legacy cleanup below.
      }
    }

    final file = _sessionFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<AuthSession?> _readFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = prefs.getString(_mobileSessionKey);
      if (payload == null || payload.isEmpty) {
        return null;
      }
      final json = jsonDecode(payload);
      if (json is! Map) {
        return null;
      }
      return AuthSession.fromJson(json.cast<String, dynamic>());
    } on Object {
      return null;
    }
  }

  Future<AuthSession?> _readFromFile() async {
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
