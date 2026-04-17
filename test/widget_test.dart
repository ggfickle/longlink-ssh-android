import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:longlink_ssh/main.dart';
import 'package:longlink_ssh/services/ssh_profile_repository.dart';

void main() {
  testWidgets('shows empty state on first launch', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(LongLinkApp(repository: SshProfileRepository()));
    await tester.pumpAndSettle();

    expect(find.text('LongLink SSH'), findsOneWidget);
    expect(find.text('No saved SSH profiles yet.'), findsOneWidget);
    expect(find.text('Create profile'), findsOneWidget);
  });
}
