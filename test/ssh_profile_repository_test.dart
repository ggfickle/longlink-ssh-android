import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:longlink_ssh/models/ssh_profile.dart';
import 'package:longlink_ssh/services/ssh_profile_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      {},
    );
  });

  test('saveProfile works when there are no existing profiles yet', () async {
    final repository = SshProfileRepository();
    final profile = SshProfile(
      id: 'oracle-root',
      displayName: 'Oracle',
      host: '129.80.64.224',
      port: 9722,
      username: 'root',
      authType: SshAuthType.password,
      connectionTimeoutSeconds: 30,
      keepAliveIntervalSeconds: 15,
    );

    await repository.saveProfile(
      profile,
      const SshProfileSecrets(password: 'secret'),
    );

    final profiles = await repository.loadProfiles();
    expect(profiles, hasLength(1));
    expect(profiles.single.displayName, 'Oracle');
    expect(profiles.single.host, '129.80.64.224');
  });

  test(
    'saveProfile persists reusable key references and clears inline key secrets',
    () async {
      final repository = SshProfileRepository();
      final inlineProfile = SshProfile(
        id: 'shared-key-profile',
        displayName: 'Shared key target',
        host: 'example.com',
        port: 22,
        username: 'root',
        authType: SshAuthType.privateKey,
        connectionTimeoutSeconds: 30,
        keepAliveIntervalSeconds: 15,
      );

      await repository.saveProfile(
        inlineProfile,
        const SshProfileSecrets(
          privateKey: 'INLINE_PRIVATE_KEY',
          passphrase: 'inline-passphrase',
        ),
      );

      final reusableProfile = inlineProfile.copyWith(reusableKeyId: 'key-123');
      await repository.saveProfile(reusableProfile, const SshProfileSecrets());

      final profiles = await repository.loadProfiles();
      expect(profiles.single.reusableKeyId, 'key-123');
      expect(profiles.single.usesReusableKey, isTrue);

      final secrets = await repository.loadSecrets(reusableProfile.id);
      expect(secrets.privateKey, isNull);
      expect(secrets.passphrase, isNull);
    },
  );
}
