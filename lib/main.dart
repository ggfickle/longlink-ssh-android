import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'services/live_ssh_session_manager.dart';
import 'services/ssh_keychain_repository.dart';
import 'services/ssh_profile_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    LongLinkApp(
      repository: SshProfileRepository(),
      keychainRepository: SshKeychainRepository(),
      sessionManager: LiveSshSessionManager(),
    ),
  );
}

class LongLinkApp extends StatelessWidget {
  const LongLinkApp({
    super.key,
    required this.repository,
    required this.keychainRepository,
    required this.sessionManager,
  });

  final SshProfileRepository repository;
  final SshKeychainRepository keychainRepository;
  final LiveSshSessionManager sessionManager;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LongLink SSH',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      home: HomePage(
        repository: repository,
        keychainRepository: keychainRepository,
        sessionManager: sessionManager,
      ),
    );
  }
}
