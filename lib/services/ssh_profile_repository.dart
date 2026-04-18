import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ssh_profile.dart';

class SshProfileRepository {
  SshProfileRepository({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _profilesStorageKey = 'ssh_profiles_v1';

  final FlutterSecureStorage _secureStorage;

  Future<List<SshProfile>> loadProfiles() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_profilesStorageKey);

    if (encoded == null || encoded.isEmpty) {
      return <SshProfile>[];
    }

    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      return <SshProfile>[];
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(SshProfile.fromJson)
        .toList()
      ..sort(
        (left, right) => left.displayName.toLowerCase().compareTo(
          right.displayName.toLowerCase(),
        ),
      );
  }

  Future<void> saveProfile(
    SshProfile profile,
    SshProfileSecrets secrets,
  ) async {
    final profiles = await loadProfiles();
    final index = profiles.indexWhere((item) => item.id == profile.id);

    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.add(profile);
    }

    profiles.sort(
      (left, right) => left.displayName.toLowerCase().compareTo(
        right.displayName.toLowerCase(),
      ),
    );

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _profilesStorageKey,
      jsonEncode(profiles.map((profile) => profile.toJson()).toList()),
    );

    await _writeSecret(profile.id, 'password', secrets.password);
    await _writeSecret(profile.id, 'private_key', secrets.privateKey);
    await _writeSecret(profile.id, 'passphrase', secrets.passphrase);
  }

  Future<SshProfileSecrets> loadSecrets(String profileId) async {
    return SshProfileSecrets(
      password: await _secureStorage.read(
        key: _secretKey(profileId, 'password'),
      ),
      privateKey: await _secureStorage.read(
        key: _secretKey(profileId, 'private_key'),
      ),
      passphrase: await _secureStorage.read(
        key: _secretKey(profileId, 'passphrase'),
      ),
    );
  }

  Future<void> deleteProfile(String profileId) async {
    final profiles = await loadProfiles();
    profiles.removeWhere((profile) => profile.id == profileId);

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _profilesStorageKey,
      jsonEncode(profiles.map((profile) => profile.toJson()).toList()),
    );

    await _secureStorage.delete(key: _secretKey(profileId, 'password'));
    await _secureStorage.delete(key: _secretKey(profileId, 'private_key'));
    await _secureStorage.delete(key: _secretKey(profileId, 'passphrase'));
  }

  Future<void> _writeSecret(
    String profileId,
    String name,
    String? value,
  ) async {
    final trimmed = value?.trim();
    final key = _secretKey(profileId, name);

    if (trimmed == null || trimmed.isEmpty) {
      await _secureStorage.delete(key: key);
      return;
    }

    await _secureStorage.write(key: key, value: value);
  }

  String _secretKey(String profileId, String name) {
    return 'ssh_profile.$profileId.$name';
  }
}
