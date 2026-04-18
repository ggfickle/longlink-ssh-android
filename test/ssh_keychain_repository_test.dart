import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:longlink_ssh/models/ssh_stored_key.dart';
import 'package:longlink_ssh/services/ssh_keychain_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      {},
    );
  });

  test('saveKey stores key metadata and secrets', () async {
    final repository = SshKeychainRepository();
    const key = SshStoredKey(
      id: 'key-1',
      name: 'Oracle root key',
      publicKey: 'ssh-ed25519 AAAATEST oracle@longlink',
      createdAtMillis: 1,
      updatedAtMillis: 2,
      hasPassphrase: true,
    );

    await repository.saveKey(
      key,
      const SshStoredKeySecrets(
        privateKey: 'PRIVATE_KEY',
        passphrase: 'secret-passphrase',
      ),
    );

    final keys = await repository.loadKeys();
    final secrets = await repository.loadSecrets('key-1');

    expect(keys, hasLength(1));
    expect(keys.single.name, 'Oracle root key');
    expect(keys.single.publicKey, contains('ssh-ed25519'));
    expect(secrets.privateKey, 'PRIVATE_KEY');
    expect(secrets.passphrase, 'secret-passphrase');
  });
}
