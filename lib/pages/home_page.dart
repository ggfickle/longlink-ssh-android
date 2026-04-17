import 'package:flutter/material.dart';

import '../models/ssh_profile.dart';
import '../services/ssh_profile_repository.dart';
import 'profile_form_page.dart';
import 'terminal_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.repository});

  final SshProfileRepository repository;

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
      setState(() {
        _profiles = profiles;
      });
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
          initialProfile: profile,
        ),
      ),
    );

    if (changed == true) {
      await _loadProfiles();
    }
  }

  Future<void> _connect(SshProfile profile) async {
    try {
      final secrets = await widget.repository.loadSecrets(profile.id);

      if (!mounted) {
        return;
      }

      if (profile.authType == SshAuthType.password && !secrets.hasPassword) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This profile has no saved password.')),
        );
        return;
      }

      if (profile.authType == SshAuthType.privateKey &&
          !secrets.hasPrivateKey) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This profile has no saved private key.'),
          ),
        );
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TerminalPage(profile: profile, secrets: secrets),
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

  Future<void> _deleteProfile(SshProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
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
        );
      },
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('LongLink SSH'),
        actions: [
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
          : _profiles.isEmpty
          ? _EmptyProfiles(onCreateProfile: () => _openProfileForm())
          : RefreshIndicator(
              onRefresh: _loadProfiles,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: _profiles.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final profile = _profiles[index];
                  return Card(
                    child: ListTile(
                      onTap: () => _connect(profile),
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
                            Text(
                              '${profile.username}@${profile.host}:${profile.port}',
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _ProfileChip(label: profile.authType.label),
                                _ProfileChip(
                                  label:
                                      'Timeout ${profile.connectionTimeoutSeconds}s',
                                ),
                                _ProfileChip(
                                  label:
                                      'Keepalive ${profile.keepAliveIntervalSeconds}s',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      trailing: PopupMenuButton<_ProfileAction>(
                        onSelected: (action) async {
                          switch (action) {
                            case _ProfileAction.connect:
                              await _connect(profile);
                            case _ProfileAction.edit:
                              await _openProfileForm(profile);
                            case _ProfileAction.delete:
                              await _deleteProfile(profile);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: _ProfileAction.connect,
                            child: Text('Connect'),
                          ),
                          PopupMenuItem(
                            value: _ProfileAction.edit,
                            child: Text('Edit'),
                          ),
                          PopupMenuItem(
                            value: _ProfileAction.delete,
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

enum _ProfileAction { connect, edit, delete }

class _EmptyProfiles extends StatelessWidget {
  const _EmptyProfiles({required this.onCreateProfile});

  final VoidCallback onCreateProfile;

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
              'Create one for your overseas server, set a longer connect timeout, and jump straight into a terminal.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreateProfile,
              icon: const Icon(Icons.add),
              label: const Text('Create profile'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.label});

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
