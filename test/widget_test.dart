import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:longlink_ssh/main.dart';
import 'package:longlink_ssh/services/live_ssh_session_manager.dart';
import 'package:longlink_ssh/services/ssh_keychain_repository.dart';
import 'package:longlink_ssh/services/ssh_profile_repository.dart';

void main() {
  testWidgets('shows empty state on first launch', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      {},
    );

    await tester.pumpWidget(
      LongLinkApp(
        repository: SshProfileRepository(),
        keychainRepository: SshKeychainRepository(),
        sessionManager: LiveSshSessionManager(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LongLink SSH'), findsOneWidget);
    expect(find.text('No saved SSH profiles yet.'), findsOneWidget);
    expect(find.text('Create profile'), findsOneWidget);
    expect(find.text('Open keychain'), findsOneWidget);
  });
}
