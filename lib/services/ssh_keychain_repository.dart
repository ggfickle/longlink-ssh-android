import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ssh_stored_key.dart';

class SshKeychainRepository {
  SshKeychainRepository({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _keysStorageKey = 'ssh_keys_v1';

  final FlutterSecureStorage _secureStorage;

  Future<List<SshStoredKey>> loadKeys() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_keysStorageKey);

    if (encoded == null || encoded.isEmpty) {
      return <SshStoredKey>[];
    }

    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      return <SshStoredKey>[];
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(SshStoredKey.fromJson)
        .where((key) => key.id.trim().isNotEmpty)
        .toList()
      ..sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
  }

  Future<SshStoredKey?> getKey(String keyId) async {
    final keys = await loadKeys();
    for (final key in keys) {
      if (key.id == keyId) {
        return key;
      }
    }
    return null;
  }

  Future<void> saveKey(SshStoredKey key, SshStoredKeySecrets secrets) async {
    final keys = await loadKeys();
    final index = keys.indexWhere((item) => item.id == key.id);

    if (index >= 0) {
      keys[index] = key;
    } else {
      keys.add(key);
    }

    keys.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _keysStorageKey,
      jsonEncode(keys.map((item) => item.toJson()).toList()),
    );

    await _writeSecret(key.id, 'private_key', secrets.privateKey);
    await _writeSecret(key.id, 'passphrase', secrets.passphrase);
  }

  Future<SshStoredKeySecrets> loadSecrets(String keyId) async {
    return SshStoredKeySecrets(
      privateKey: await _secureStorage.read(
        key: _secretKey(keyId, 'private_key'),
      ),
      passphrase: await _secureStorage.read(
        key: _secretKey(keyId, 'passphrase'),
      ),
    );
  }

  Future<void> deleteKey(String keyId) async {
    final keys = await loadKeys();
    keys.removeWhere((key) => key.id == keyId);

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _keysStorageKey,
      jsonEncode(keys.map((item) => item.toJson()).toList()),
    );

    await _secureStorage.delete(key: _secretKey(keyId, 'private_key'));
    await _secureStorage.delete(key: _secretKey(keyId, 'passphrase'));
  }

  Future<void> _writeSecret(String keyId, String name, String? value) async {
    final trimmed = value?.trim();
    final key = _secretKey(keyId, name);

    if (trimmed == null || trimmed.isEmpty) {
      await _secureStorage.delete(key: key);
      return;
    }

    await _secureStorage.write(key: key, value: value);
  }

  String _secretKey(String keyId, String name) {
    return 'ssh_key.$keyId.$name';
  }
}
