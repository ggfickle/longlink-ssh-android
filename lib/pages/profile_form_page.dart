import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/ssh_profile.dart';
import '../models/ssh_stored_key.dart';
import '../services/ssh_key_service.dart';
import '../services/ssh_keychain_repository.dart';
import '../services/ssh_profile_repository.dart';
import 'ssh_keychain_page.dart';

enum _PrivateKeyStorageMode { inline, reusable }

class ProfileFormPage extends StatefulWidget {
  const ProfileFormPage({
    super.key,
    required this.repository,
    required this.keychainRepository,
    this.initialProfile,
  });

  final SshProfileRepository repository;
  final SshKeychainRepository keychainRepository;
  final SshProfile? initialProfile;

  bool get isEditing => initialProfile != null;

  @override
  State<ProfileFormPage> createState() => _ProfileFormPageState();
}

class _ProfileFormPageState extends State<ProfileFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _privateKeyController = TextEditingController();
  final _passphraseController = TextEditingController();
  final _timeoutController = TextEditingController(text: '30');
  final _keepAliveController = TextEditingController(text: '15');

  final _uuid = const Uuid();
  final _keyService = const SshKeyService();

  late SshAuthType _authType;
  late _PrivateKeyStorageMode _privateKeyStorageMode;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _obscurePassword = true;
  bool _obscurePassphrase = true;
  String? _publicKeyPreview;
  String? _selectedReusableKeyId;
  List<SshStoredKey> _availableKeys = const [];

  SshStoredKey? get _selectedReusableKey {
    final selectedId = _selectedReusableKeyId;
    if (selectedId == null) {
      return null;
    }
    for (final key in _availableKeys) {
      if (key.id == selectedId) {
        return key;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final initialProfile = widget.initialProfile;
    _authType = initialProfile?.authType ?? SshAuthType.password;
    _privateKeyStorageMode = initialProfile?.usesReusableKey == true
        ? _PrivateKeyStorageMode.reusable
        : _PrivateKeyStorageMode.inline;
    _selectedReusableKeyId = initialProfile?.reusableKeyId;
    _privateKeyController.addListener(_handleKeyMaterialChanged);
    _passphraseController.addListener(_handleKeyMaterialChanged);
    _loadInitialValues();
  }

  @override
  void dispose() {
    _privateKeyController.removeListener(_handleKeyMaterialChanged);
    _passphraseController.removeListener(_handleKeyMaterialChanged);
    _displayNameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
    _timeoutController.dispose();
    _keepAliveController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialValues() async {
    final profile = widget.initialProfile;
    if (profile != null) {
      _displayNameController.text = profile.displayName;
      _hostController.text = profile.host;
      _portController.text = profile.port.toString();
      _usernameController.text = profile.username;
      _timeoutController.text = profile.connectionTimeoutSeconds.toString();
      _keepAliveController.text = profile.keepAliveIntervalSeconds.toString();
    }

    setState(() => _isLoading = true);

    try {
      final keys = await widget.keychainRepository.loadKeys();
      if (!mounted) {
        return;
      }
      _availableKeys = keys;

      if (profile != null && !profile.usesReusableKey) {
        final secrets = await widget.repository.loadSecrets(profile.id);
        if (!mounted) {
          return;
        }
        _passwordController.text = secrets.password ?? '';
        _privateKeyController.text = secrets.privateKey ?? '';
        _passphraseController.text = secrets.passphrase ?? '';
      }

      if (_selectedReusableKeyId != null &&
          !_availableKeys.any((key) => key.id == _selectedReusableKeyId)) {
        _selectedReusableKeyId = null;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleKeyMaterialChanged() {
    if (_privateKeyStorageMode != _PrivateKeyStorageMode.inline) {
      return;
    }

    final next = _derivePublicKeyPreview();
    if (next == _publicKeyPreview || !mounted) {
      return;
    }
    setState(() => _publicKeyPreview = next);
  }

  Future<void> _openKeychain() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SshKeychainPage(repository: widget.keychainRepository),
      ),
    );

    final keys = await widget.keychainRepository.loadKeys();
    if (!mounted) {
      return;
    }

    setState(() {
      _availableKeys = keys;
      if (_selectedReusableKeyId != null &&
          !_availableKeys.any((key) => key.id == _selectedReusableKeyId)) {
        _selectedReusableKeyId = null;
      }
    });
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

    setState(() {
      _privateKeyStorageMode = _PrivateKeyStorageMode.inline;
      _privateKeyController.text = normalized;
    });

    final recognized = _looksLikePrivateKey(normalized);
    final message = recognized
        ? 'Imported private key from $source'
        : 'Imported text from $source. If login fails, paste an OpenSSH private key block.';

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
      _privateKeyStorageMode = _PrivateKeyStorageMode.inline;
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
                'A new ED25519 key pair has been generated for this profile. Save the profile to keep the private key securely on this device.',
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
    final publicKey = _privateKeyStorageMode == _PrivateKeyStorageMode.reusable
        ? _selectedReusableKey?.publicKey
        : _publicKeyPreview;

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

  bool _looksLikePrivateKey(String contents) {
    final normalized = contents.trim();
    const markers = [
      'BEGIN OPENSSH PRIVATE KEY',
      'BEGIN RSA PRIVATE KEY',
      'BEGIN EC PRIVATE KEY',
      'BEGIN DSA PRIVATE KEY',
      'BEGIN PRIVATE KEY',
      'PuTTY-User-Key-File-',
    ];

    return markers.any(normalized.contains);
  }

  String _suggestKeyComment() {
    final username = _usernameController.text.trim();
    final host = _hostController.text.trim();
    final displayName = _displayNameController.text.trim().replaceAll(
      RegExp(r'\s+'),
      '-',
    );

    if (username.isNotEmpty && host.isNotEmpty) {
      return '$username@$host';
    }
    if (displayName.isNotEmpty) {
      return '$displayName@longlink';
    }
    return 'longlink@android';
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

    if (_authType == SshAuthType.privateKey &&
        _privateKeyStorageMode == _PrivateKeyStorageMode.reusable &&
        _selectedReusableKeyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a shared key first.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final profile = SshProfile(
        id: widget.initialProfile?.id ?? _uuid.v4(),
        displayName: _displayNameController.text.trim(),
        host: _hostController.text.trim(),
        port: int.parse(_portController.text.trim()),
        username: _usernameController.text.trim(),
        authType: _authType,
        connectionTimeoutSeconds: int.parse(_timeoutController.text.trim()),
        keepAliveIntervalSeconds: int.parse(_keepAliveController.text.trim()),
        reusableKeyId:
            _authType == SshAuthType.privateKey &&
                _privateKeyStorageMode == _PrivateKeyStorageMode.reusable
            ? _selectedReusableKeyId
            : null,
      );

      final secrets = SshProfileSecrets(
        password: _authType == SshAuthType.password
            ? _passwordController.text
            : null,
        privateKey:
            _authType == SshAuthType.privateKey &&
                _privateKeyStorageMode == _PrivateKeyStorageMode.inline
            ? _privateKeyController.text
            : null,
        passphrase:
            _authType == SshAuthType.privateKey &&
                _privateKeyStorageMode == _PrivateKeyStorageMode.inline
            ? _passphraseController.text
            : null,
      );

      await widget.repository.saveProfile(profile, secrets);

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
      ).showSnackBar(SnackBar(content: Text('Failed to save profile: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedReusableKey = _selectedReusableKey;
    final reusablePublicKey = selectedReusableKey?.publicKey;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit profile' : 'New profile'),
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
                    controller: _displayNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      hintText: 'Tokyo VPS',
                    ),
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _hostController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Host',
                      hintText: 'example.com or 203.0.113.10',
                    ),
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _portController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(labelText: 'Port'),
                          validator: _portValidator,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _usernameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                          ),
                          validator: _requiredValidator,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<SshAuthType>(
                    initialValue: _authType,
                    decoration: const InputDecoration(labelText: 'Auth type'),
                    items: const [
                      DropdownMenuItem(
                        value: SshAuthType.password,
                        child: Text('Password'),
                      ),
                      DropdownMenuItem(
                        value: SshAuthType.privateKey,
                        child: Text('Private key'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _authType = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_authType == SshAuthType.password) ...[
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          onPressed: () => setState(() {
                            _obscurePassword = !_obscurePassword;
                          }),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                      validator: _secretRequiredValidator,
                    ),
                  ] else ...[
                    Text(
                      'Private key source',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<_PrivateKeyStorageMode>(
                      segments: const [
                        ButtonSegment<_PrivateKeyStorageMode>(
                          value: _PrivateKeyStorageMode.inline,
                          label: Text('This profile only'),
                          icon: Icon(Icons.person),
                        ),
                        ButtonSegment<_PrivateKeyStorageMode>(
                          value: _PrivateKeyStorageMode.reusable,
                          label: Text('Shared keychain'),
                          icon: Icon(Icons.key),
                        ),
                      ],
                      selected: {_privateKeyStorageMode},
                      onSelectionChanged: (selection) {
                        setState(() {
                          _privateKeyStorageMode = selection.first;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_privateKeyStorageMode ==
                        _PrivateKeyStorageMode.reusable) ...[
                      if (_availableKeys.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'No shared keys yet. Open the keychain to import or generate one first.',
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _openKeychain,
                                  icon: const Icon(Icons.key),
                                  label: const Text('Open keychain'),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        DropdownButtonFormField<String>(
                          initialValue: _selectedReusableKeyId,
                          decoration: const InputDecoration(
                            labelText: 'Shared SSH key',
                          ),
                          items: _availableKeys
                              .map(
                                (key) => DropdownMenuItem<String>(
                                  value: key.id,
                                  child: Text(key.name),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() => _selectedReusableKeyId = value);
                          },
                          validator: (value) {
                            if (_authType == SshAuthType.privateKey &&
                                _privateKeyStorageMode ==
                                    _PrivateKeyStorageMode.reusable &&
                                (value == null || value.trim().isEmpty)) {
                              return 'Choose a shared key';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _openKeychain,
                              icon: const Icon(Icons.manage_accounts),
                              label: const Text('Manage keychain'),
                            ),
                            const SizedBox(width: 12),
                            if (selectedReusableKey != null)
                              Expanded(
                                child: Text(
                                  selectedReusableKey.hasPassphrase
                                      ? 'Passphrase saved with key'
                                      : 'No passphrase saved',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ] else ...[
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
                          OutlinedButton.icon(
                            onPressed: _openKeychain,
                            icon: const Icon(Icons.manage_accounts),
                            label: const Text('Open keychain'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Android file pickers often hide the .ssh folder because it starts with a dot. If you cannot see your key file, paste it from the clipboard, move it into Downloads first, or let LongLink generate a new ED25519 key pair for you.',
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
                        validator: (value) {
                          if (_authType == SshAuthType.privateKey &&
                              _privateKeyStorageMode ==
                                  _PrivateKeyStorageMode.inline &&
                              (value == null || value.trim().isEmpty)) {
                            return 'Required';
                          }
                          return null;
                        },
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
                    ],
                    if ((_privateKeyStorageMode ==
                                _PrivateKeyStorageMode.inline &&
                            _publicKeyPreview != null &&
                            _publicKeyPreview!.isNotEmpty) ||
                        (_privateKeyStorageMode ==
                                _PrivateKeyStorageMode.reusable &&
                            reusablePublicKey != null &&
                            reusablePublicKey.isNotEmpty)) ...[
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
                        child: SelectableText(
                          _privateKeyStorageMode ==
                                  _PrivateKeyStorageMode.reusable
                              ? reusablePublicKey!
                              : _publicKeyPreview!,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _privateKeyStorageMode ==
                                _PrivateKeyStorageMode.reusable
                            ? 'This is the public key for the selected shared keychain entry.'
                            : 'Add this public key to the server\'s authorized_keys. For generated keys, this is the line you need on the server side.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _timeoutController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Connect timeout (s)',
                          ),
                          validator: _positiveSecondsValidator,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _keepAliveController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Keepalive (s)',
                            helperText: '0 disables',
                          ),
                          validator: _nonNegativeSecondsValidator,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: const Icon(Icons.save),
                    label: Text(_isSaving ? 'Saving...' : 'Save profile'),
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

  String? _secretRequiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    return null;
  }

  String? _portValidator(String? value) {
    final error = _positiveSecondsValidator(value);
    if (error != null) {
      return error;
    }

    final port = int.parse(value!.trim());
    if (port < 1 || port > 65535) {
      return 'Use 1-65535';
    }

    return null;
  }

  String? _positiveSecondsValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }

    final seconds = int.tryParse(value.trim());
    if (seconds == null || seconds <= 0) {
      return 'Use a number above 0';
    }

    return null;
  }

  String? _nonNegativeSecondsValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }

    final seconds = int.tryParse(value.trim());
    if (seconds == null || seconds < 0) {
      return 'Use 0 or more';
    }

    return null;
  }
}
