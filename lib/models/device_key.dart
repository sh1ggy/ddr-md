/// Name: DeviceKey
/// Parent: CloudSync, CircleState
/// Description: A random key that stands in for an account where there's no
/// sign-in, made on first use and kept in the iOS Keychain (shared by iCloud
/// Keychain) and in preferences (restored by Android's backup).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceKey {
  const DeviceKey(this.keychainName, this.prefsKey);

  final String keychainName;
  final String prefsKey;

  static const _keychain = FlutterSecureStorage(
      iOptions: IOSOptions(
          synchronizable: true,
          accessibility: KeychainAccessibility.first_unlock));
  static final _format = RegExp(r'^[A-Za-z0-9_-]{43}$');

  // The Keychain copy wins: on a new iPhone it arrives through iCloud
  // Keychain, before any preferences do.
  Future<String> read() async {
    String? key;
    if (Platform.isIOS) {
      key = await _keychain.read(key: keychainName).catchError((_) => null);
    }
    if (key == null || !_format.hasMatch(key)) {
      key = Settings.getString(prefsKey);
    }
    if (!_format.hasMatch(key)) key = _new();
    await _store(key);
    return key;
  }

  /// Swaps in a new key: whatever the old one held is out of reach.
  Future<void> replace() => _store(_new());

  Future<void> _store(String key) async {
    await Settings.setString(prefsKey, key);
    if (Platform.isIOS) {
      await _keychain
          .write(key: keychainName, value: key)
          .catchError((Object e) => debugPrint('Keychain: $e'));
    }
  }

  static String _new() {
    final random = Random.secure();
    return base64Url.encode(
        [for (var i = 0; i < 32; i++) random.nextInt(256)]).replaceAll('=', '');
  }
}
