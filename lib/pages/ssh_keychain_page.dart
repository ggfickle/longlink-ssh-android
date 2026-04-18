import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ssh_stored_key.dart';
import '../services/ssh_keychain_repository.dart';
import 'ssh_key_form_page.dart';

class SshKeychainPage extends StatefulWidget {
  const SshKeychainPage({super.key, required this.repository});

  final SshKeychainRepository repository;

  @override
  State<SshKeychainPage> createState() => _SshKeychainPageState();
}

class _SshKeychainPageState extends State<SshKeychainPage> {
  bool _isLoading = true;
  List<SshStoredKey> _keys = const [];

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    setState(() => _isLoading = true);

    try {
      final keys = await widget.repository.loadKeys();
      if (!mounted) {
        return;
      }
      setState(() => _keys = keys);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load keys: $error')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openKeyForm([SshStoredKey? key]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            SshKeyFormPage(repository: widget.repository, initialKey: key),
      ),
    );

    if (changed == true) {
      await _loadKeys();
    }
  }

  Future<void> _copyPublicKey(SshStoredKey key) async {
    await Clipboard.setData(ClipboardData(text: key.publicKey));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied public key for ${key.name}.')),
    );
  }

  Future<void> _copyPrivateKey(SshStoredKey key) async {
    try {
      final secrets = await widget.repository.loadSecrets(key.id);
      if (!mounted) {
        return;
      }
      if (!secrets.hasPrivateKey) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${key.name} has no private key saved.')),
        );
        return;
      }
      await Clipboard.setData(ClipboardData(text: secrets.privateKey!));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied private key for ${key.name}. Keep it safe.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to copy private key: $error')),
      );
    }
  }

  Future<void> _deleteKey(SshStoredKey key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete SSH key?'),
        content: Text(
          'Remove ${key.name} from the shared keychain on this device?',
        ),
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
      await widget.repository.deleteKey(key.id);
      await _loadKeys();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete key: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH keychain'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadKeys,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openKeyForm(),
        icon: const Icon(Icons.key),
        label: const Text('New key'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _keys.isEmpty
          ? _EmptyKeychain(onCreateKey: () => _openKeyForm())
          : RefreshIndicator(
              onRefresh: _loadKeys,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: _keys.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final key = _keys[index];
                  return Card(
                    child: ListTile(
                      onTap: () => _openKeyForm(key),
                      contentPadding: const EdgeInsets.all(16),
                      leading: const CircleAvatar(child: Icon(Icons.key)),
                      title: Text(key.name),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(key.publicKeySummary),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _KeyChip(label: key.algorithm),
                                _KeyChip(
                                  label: key.hasPassphrase
                                      ? 'Passphrase saved'
                                      : 'No passphrase',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      trailing: PopupMenuButton<_KeyAction>(
                        onSelected: (action) async {
                          switch (action) {
                            case _KeyAction.edit:
                              await _openKeyForm(key);
                              break;
                            case _KeyAction.copyPublic:
                              await _copyPublicKey(key);
                              break;
                            case _KeyAction.copyPrivate:
                              await _copyPrivateKey(key);
                              break;
                            case _KeyAction.delete:
                              await _deleteKey(key);
                              break;
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: _KeyAction.edit,
                            child: Text('Edit'),
                          ),
                          PopupMenuItem(
                            value: _KeyAction.copyPublic,
                            child: Text('Copy public key'),
                          ),
                          PopupMenuItem(
                            value: _KeyAction.copyPrivate,
                            child: Text('Copy private key'),
                          ),
                          PopupMenuItem(
                            value: _KeyAction.delete,
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

enum _KeyAction { edit, copyPublic, copyPrivate, delete }

class _EmptyKeychain extends StatelessWidget {
  const _EmptyKeychain({required this.onCreateKey});

  final VoidCallback onCreateKey;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.key_outlined, size: 64),
            const SizedBox(height: 16),
            Text(
              'No shared SSH keys yet.',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Import or generate a key once here, then reuse it across multiple connection profiles.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreateKey,
              icon: const Icon(Icons.key),
              label: const Text('Create key'),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyChip extends StatelessWidget {
  const _KeyChip({required this.label});

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
