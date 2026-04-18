import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:longlink_ssh/models/ssh_profile.dart';
import 'package:longlink_ssh/services/ssh_profile_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saveProfile works when there are no existing profiles yet', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});

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
}
