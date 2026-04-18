import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/ssh_stored_key.dart';
import '../services/ssh_key_service.dart';
import '../services/ssh_keychain_repository.dart';

class SshKeyFormPage extends StatefulWidget {
  const SshKeyFormPage({super.key, required this.repository, this.initialKey});

  final SshKeychainRepository repository;
  final SshStoredKey? initialKey;

  bool get isEditing => initialKey != null;

  @override
  State<SshKeyFormPage> createState() => _SshKeyFormPageState();
}

class _SshKeyFormPageState extends State<SshKeyFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _privateKeyController = TextEditingController();
  final _passphraseController = TextEditingController();

  final _uuid = const Uuid();
  final _keyService = const SshKeyService();

  bool _isLoading = false;
  bool _isSaving = false;
  bool _obscurePassphrase = true;
  String? _publicKeyPreview;

  @override
  void initState() {
    super.initState();
    _privateKeyController.addListener(_handleKeyMaterialChanged);
    _passphraseController.addListener(_handleKeyMaterialChanged);
    _loadInitialValues();
  }

  @override
  void dispose() {
    _privateKeyController.removeListener(_handleKeyMaterialChanged);
    _passphraseController.removeListener(_handleKeyMaterialChanged);
    _nameController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialValues() async {
    final key = widget.initialKey;
    if (key == null) {
      return;
    }

    _nameController.text = key.name;
    _publicKeyPreview = key.publicKey;
    setState(() => _isLoading = true);

    try {
      final secrets = await widget.repository.loadSecrets(key.id);
      if (!mounted) {
        return;
      }
      _privateKeyController.text = secrets.privateKey ?? '';
      _passphraseController.text = secrets.passphrase ?? '';
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleKeyMaterialChanged() {
    final next = _derivePublicKeyPreview();
    if (next == _publicKeyPreview || !mounted) {
      return;
    }
    setState(() => _publicKeyPreview = next);
  }

  Future<void> _pickPrivateKey() async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final pickedFile = result.files.single;
      String? contents;
      if (pickedFile.bytes != null) {
        contents = utf8.decode(pickedFile.bytes!, allowMalformed: true);
      } else if (pickedFile.path != null) {
        contents = await File(pickedFile.path!).readAsString();
      }

      if (!mounted || contents == null) {
        return;
      }

      _importPrivateKeyText(
        contents,
        source: pickedFile.name.isNotEmpty ? pickedFile.name : 'file',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to import key file: $error')),
      );
    }
  }

  Future<void> _pastePrivateKeyFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) {
        return;
      }
      final contents = data?.text;
      if (contents == null || contents.trim().isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Clipboard is empty.')));
        return;
      }
      _importPrivateKeyText(contents, source: 'clipboard');
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to read clipboard: $error')),
      );
    }
  }

  void _importPrivateKeyText(String contents, {required String source}) {
    final normalized = contents.replaceFirst('\uFEFF', '').trim();
    if (normalized.isEmpty || !mounted) {
      return;
    }

    setState(() => _privateKeyController.text = normalized);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported private key from $source')),
    );
  }

  Future<void> _generateKeyPair() async {
    final hasExistingKey = _privateKeyController.text.trim().isNotEmpty;
    if (hasExistingKey) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace current private key?'),
          content: const Text(
            'Generating a new key will replace the private key currently in this form.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) {
        return;
      }
    }

    final generated = _keyService.generateEd25519(
      comment: _suggestKeyComment(),
    );

    setState(() {
      _privateKeyController.text = generated.privateKeyPem;
      _passphraseController.clear();
      _publicKeyPreview = generated.publicKeyAuthorized;
    });

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New key generated'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'A new ED25519 key pair has been generated. Save this form to keep it in the shared keychain on this device.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              const Text('Public key'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(generated.publicKeyAuthorized),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: generated.privateKeyPem),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Private key copied. Keep it safe.'),
                  ),
                );
              }
            },
            icon: const Icon(Icons.key),
            label: const Text('Copy private key'),
          ),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: generated.publicKeyAuthorized),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Public key copied.')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy public key'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyPrivateKey() async {
    final privateKey = _privateKeyController.text.trim();
    if (privateKey.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: privateKey));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Private key copied. Keep it safe.')),
    );
  }

  Future<void> _copyPublicKey() async {
    final publicKey = _publicKeyPreview;
    if (publicKey == null || publicKey.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: publicKey));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Public key copied.')));
  }

  String _suggestKeyComment() {
    final name = _nameController.text.trim().replaceAll(RegExp(r'\s+'), '-');
    return name.isEmpty ? 'longlink@android' : '$name@longlink';
  }

  String? _derivePublicKeyPreview() {
    final privateKey = _privateKeyController.text.trim();
    if (privateKey.isEmpty) {
      return null;
    }

    try {
      return _keyService.deriveAuthorizedPublicKey(
        privateKey,
        passphrase: _blankToNull(_passphraseController.text),
        fallbackComment: _suggestKeyComment(),
      );
    } catch (_) {
      return null;
    }
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final publicKey = _derivePublicKeyPreview();
    if (publicKey == null || publicKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The private key could not be parsed. Check the key text and passphrase.',
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final key = SshStoredKey(
        id: widget.initialKey?.id ?? _uuid.v4(),
        name: _nameController.text.trim(),
        publicKey: publicKey,
        createdAtMillis: widget.initialKey?.createdAtMillis ?? now,
        updatedAtMillis: now,
        hasPassphrase: _blankToNull(_passphraseController.text) != null,
      );

      final secrets = SshStoredKeySecrets(
        privateKey: _privateKeyController.text,
        passphrase: _passphraseController.text,
      );

      await widget.repository.saveKey(key, secrets);

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save key: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit SSH key' : 'New SSH key'),
      ),
      body: Stack(
        children: [
          IgnorePointer(
            ignoring: _isLoading || _isSaving,
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Key name',
                      hintText: 'Oracle root key',
                    ),
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _pickPrivateKey,
                        icon: const Icon(Icons.file_open),
                        label: const Text('Import key file'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pastePrivateKeyFromClipboard,
                        icon: const Icon(Icons.content_paste),
                        label: const Text('Paste from clipboard'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _generateKeyPair,
                        icon: const Icon(Icons.key),
                        label: const Text('Generate key pair'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Import or generate a key once here, then reuse it across multiple SSH profiles without copying the private key around.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _privateKeyController,
                    minLines: 8,
                    maxLines: 14,
                    decoration: const InputDecoration(
                      labelText: 'Private key',
                      alignLabelWithHint: true,
                      hintText: 'Paste your OpenSSH private key here',
                    ),
                    validator: _requiredValidator,
                  ),
                  if (_privateKeyController.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _copyPrivateKey,
                        icon: const Icon(Icons.key),
                        label: const Text('Copy private key'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passphraseController,
                    obscureText: _obscurePassphrase,
                    decoration: InputDecoration(
                      labelText: 'Passphrase (optional)',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() {
                          _obscurePassphrase = !_obscurePassphrase;
                        }),
                        icon: Icon(
                          _obscurePassphrase
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                  if (_publicKeyPreview != null &&
                      _publicKeyPreview!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Public key',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _copyPublicKey,
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy'),
                        ),
                      ],
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(_publicKeyPreview!),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add this line to authorized_keys on your server. LongLink stores the private key securely on this device.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: const Icon(Icons.save),
                    label: Text(_isSaving ? 'Saving...' : 'Save key'),
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading || _isSaving)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    return null;
  }
}
