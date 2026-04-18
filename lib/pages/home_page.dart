import 'package:flutter/material.dart';

import '../models/ssh_profile.dart';
import '../services/live_ssh_session_manager.dart';
import '../services/ssh_keychain_repository.dart';
import '../services/ssh_profile_repository.dart';
import 'profile_form_page.dart';
import 'ssh_keychain_page.dart';
import 'terminal_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.keychainRepository,
    required this.sessionManager,
  });

  final SshProfileRepository repository;
  final SshKeychainRepository keychainRepository;
  final LiveSshSessionManager sessionManager;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isLoading = true;
  List<SshProfile> _profiles = const [];

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() => _isLoading = true);

    try {
      final profiles = await widget.repository.loadProfiles();
      if (!mounted) {
        return;
      }
      setState(() => _profiles = profiles);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load profiles: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openProfileForm([SshProfile? profile]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProfileFormPage(
          repository: widget.repository,
          keychainRepository: widget.keychainRepository,
          initialProfile: profile,
        ),
      ),
    );

    if (changed == true) {
      await _loadProfiles();
    }
  }

  Future<void> _openKeychain() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SshKeychainPage(repository: widget.keychainRepository),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<SshProfileSecrets> _resolveConnectionSecrets(
    SshProfile profile,
  ) async {
    if (profile.authType == SshAuthType.password) {
      final secrets = await widget.repository.loadSecrets(profile.id);
      if (!secrets.hasPassword) {
        throw StateError('This profile has no saved password.');
      }
      return secrets;
    }

    if (profile.usesReusableKey) {
      final reusableKeyId = profile.reusableKeyId;
      if (reusableKeyId == null) {
        throw StateError('This profile references a missing shared key.');
      }

      final reusableKey = await widget.keychainRepository.getKey(reusableKeyId);
      if (reusableKey == null) {
        throw StateError('The shared key for this profile was not found.');
      }

      final reusableSecrets = await widget.keychainRepository.loadSecrets(
        reusableKey.id,
      );
      if (!reusableSecrets.hasPrivateKey) {
        throw StateError('The selected shared key has no saved private key.');
      }

      return SshProfileSecrets(
        privateKey: reusableSecrets.privateKey,
        passphrase: reusableSecrets.passphrase,
      );
    }

    final secrets = await widget.repository.loadSecrets(profile.id);
    if (!secrets.hasPrivateKey) {
      throw StateError('This profile has no saved private key.');
    }
    return secrets;
  }

  Future<void> _openProfileSession(SshProfile profile) async {
    try {
      final secrets = await _resolveConnectionSecrets(profile);
      final session = widget.sessionManager.obtainSession(
        profile: profile,
        secrets: secrets,
      );
      final shouldConnect = !session.isAlive;

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              TerminalPage(session: session, connectOnOpen: shouldConnect),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open connection: $error')),
      );
    }
  }

  Future<void> _resumeSession(LiveSshSessionController session) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TerminalPage(session: session, connectOnOpen: false),
      ),
    );
  }

  Future<void> _reconnectSession(LiveSshSessionController session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reconnect session?'),
        content: Text('Reconnect ${session.profile.displayName} now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reconnect'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await session.reconnect();
      if (!mounted) {
        return;
      }
      await _resumeSession(session);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to reconnect: $error')));
    }
  }

  Future<void> _disconnectSession(LiveSshSessionController session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect session?'),
        content: Text(
          'Close ${session.profile.displayName} and remove it from live sessions?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await session.close();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to disconnect session: $error')),
      );
    }
  }

  Future<void> _deleteProfile(SshProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete profile?'),
        content: Text('Remove ${profile.displayName} from this device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.repository.deleteProfile(profile.id);
      await _loadProfiles();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete profile: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.sessionManager,
      builder: (context, _) {
        final liveSessions = widget.sessionManager.sessions;
        final showCombinedEmpty =
            !_isLoading && liveSessions.isEmpty && _profiles.isEmpty;

        return Scaffold(
          appBar: AppBar(
            title: const Text('LongLink SSH'),
            actions: [
              IconButton(
                onPressed: _openKeychain,
                tooltip: 'SSH keychain',
                icon: const Icon(Icons.key),
              ),
              IconButton(
                onPressed: _isLoading ? null : _loadProfiles,
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openProfileForm(),
            icon: const Icon(Icons.add),
            label: const Text('New profile'),
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : showCombinedEmpty
              ? _EmptyHome(
                  onCreateProfile: () => _openProfileForm(),
                  onOpenKeychain: _openKeychain,
                )
              : RefreshIndicator(
                  onRefresh: _loadProfiles,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      if (liveSessions.isNotEmpty) ...[
                        Text(
                          'Live sessions',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Back out of a terminal to suspend it. Tap a session here to jump straight back in.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        ...liveSessions.expand(
                          (session) => [
                            _LiveSessionCard(
                              session: session,
                              onOpen: () => _resumeSession(session),
                              onReconnect: () => _reconnectSession(session),
                              onDisconnect: () => _disconnectSession(session),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ],
                      Text(
                        'Saved profiles',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      if (_profiles.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'No saved profiles yet. Create one to connect quickly, or open the SSH keychain first to add reusable keys.',
                            ),
                          ),
                        )
                      else
                        ..._profiles.expand(
                          (profile) => [
                            _ProfileCard(
                              profile: profile,
                              onConnect: () => _openProfileSession(profile),
                              onEdit: () => _openProfileForm(profile),
                              onDelete: () => _deleteProfile(profile),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome({
    required this.onCreateProfile,
    required this.onOpenKeychain,
  });

  final VoidCallback onCreateProfile;
  final VoidCallback onOpenKeychain;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lan_outlined, size: 64),
            const SizedBox(height: 16),
            Text(
              'No saved SSH profiles yet.',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Create a profile for your server, or preload reusable SSH keys in the keychain so new profiles can share them.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onCreateProfile,
                  icon: const Icon(Icons.add),
                  label: const Text('Create profile'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenKeychain,
                  icon: const Icon(Icons.key),
                  label: const Text('Open keychain'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.onConnect,
    required this.onEdit,
    required this.onDelete,
  });

  final SshProfile profile;
  final VoidCallback onConnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onConnect,
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          child: Icon(
            profile.authType == SshAuthType.password
                ? Icons.password
                : Icons.key,
          ),
        ),
        title: Text(profile.displayName),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${profile.username}@${profile.host}:${profile.port}'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(label: profile.authType.label),
                  if (profile.authType == SshAuthType.privateKey)
                    _InfoChip(
                      label: profile.usesReusableKey
                          ? 'Shared key'
                          : 'Profile-only key',
                    ),
                  _InfoChip(
                    label: 'Timeout ${profile.connectionTimeoutSeconds}s',
                  ),
                  _InfoChip(
                    label: 'Keepalive ${profile.keepAliveIntervalSeconds}s',
                  ),
                ],
              ),
            ],
          ),
        ),
        trailing: PopupMenuButton<_ProfileAction>(
          onSelected: (action) {
            switch (action) {
              case _ProfileAction.connect:
                onConnect();
                break;
              case _ProfileAction.edit:
                onEdit();
                break;
              case _ProfileAction.delete:
                onDelete();
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _ProfileAction.connect,
              child: Text('Connect'),
            ),
            PopupMenuItem(value: _ProfileAction.edit, child: Text('Edit')),
            PopupMenuItem(value: _ProfileAction.delete, child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}

class _LiveSessionCard extends StatelessWidget {
  const _LiveSessionCard({
    required this.session,
    required this.onOpen,
    required this.onReconnect,
    required this.onDisconnect,
  });

  final LiveSshSessionController session;
  final VoidCallback onOpen;
  final VoidCallback onReconnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onOpen,
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(child: Icon(_iconFor(session.state))),
        title: Text(session.profile.displayName),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(session.targetLabel),
              const SizedBox(height: 8),
              Text(session.statusText),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(label: _labelFor(session.state)),
                  if (session.profile.keepAliveIntervalSeconds > 0)
                    _InfoChip(
                      label:
                          'Keepalive ${session.profile.keepAliveIntervalSeconds}s',
                    ),
                ],
              ),
            ],
          ),
        ),
        trailing: PopupMenuButton<_LiveSessionAction>(
          onSelected: (action) {
            switch (action) {
              case _LiveSessionAction.open:
                onOpen();
                break;
              case _LiveSessionAction.reconnect:
                onReconnect();
                break;
              case _LiveSessionAction.disconnect:
                onDisconnect();
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: _LiveSessionAction.open, child: Text('Open')),
            PopupMenuItem(
              value: _LiveSessionAction.reconnect,
              child: Text('Reconnect'),
            ),
            PopupMenuItem(
              value: _LiveSessionAction.disconnect,
              child: Text('Disconnect'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(LiveSshSessionState state) {
    switch (state) {
      case LiveSshSessionState.connecting:
        return Icons.sync;
      case LiveSshSessionState.active:
        return Icons.terminal;
      case LiveSshSessionState.suspended:
        return Icons.pause_circle;
      case LiveSshSessionState.disconnected:
        return Icons.link_off;
      case LiveSshSessionState.error:
        return Icons.error;
    }
  }

  String _labelFor(LiveSshSessionState state) {
    switch (state) {
      case LiveSshSessionState.connecting:
        return 'Connecting';
      case LiveSshSessionState.active:
        return 'Active';
      case LiveSshSessionState.suspended:
        return 'Suspended';
      case LiveSshSessionState.disconnected:
        return 'Disconnected';
      case LiveSshSessionState.error:
        return 'Error';
    }
  }
}

enum _ProfileAction { connect, edit, delete }

enum _LiveSessionAction { open, reconnect, disconnect }

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label),
      ),
    );
  }
}

extension on SshAuthType {
  String get label {
    switch (this) {
      case SshAuthType.password:
        return 'Password';
      case SshAuthType.privateKey:
        return 'Private key';
    }
  }
}
