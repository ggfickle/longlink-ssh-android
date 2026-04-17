import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/ssh_profile.dart';
import '../services/ssh_profile_repository.dart';

class ProfileFormPage extends StatefulWidget {
  const ProfileFormPage({
    super.key,
    required this.repository,
    this.initialProfile,
  });

  final SshProfileRepository repository;
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

  late SshAuthType _authType;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _obscurePassword = true;
  bool _obscurePassphrase = true;

  @override
  void initState() {
    super.initState();
    _authType = widget.initialProfile?.authType ?? SshAuthType.password;
    _loadInitialValues();
  }

  @override
  void dispose() {
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
    if (profile == null) {
      return;
    }

    _displayNameController.text = profile.displayName;
    _hostController.text = profile.host;
    _portController.text = profile.port.toString();
    _usernameController.text = profile.username;
    _timeoutController.text = profile.connectionTimeoutSeconds.toString();
    _keepAliveController.text = profile.keepAliveIntervalSeconds.toString();

    setState(() => _isLoading = true);

    try {
      final secrets = await widget.repository.loadSecrets(profile.id);
      if (!mounted) {
        return;
      }
      _passwordController.text = secrets.password ?? '';
      _privateKeyController.text = secrets.privateKey ?? '';
      _passphraseController.text = secrets.passphrase ?? '';
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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

      if (!mounted || contents == null || contents.trim().isEmpty) {
        return;
      }

      setState(() {
        _privateKeyController.text = contents!;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to import key file: $error')),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
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
      );

      final secrets = SshProfileSecrets(
        password: _authType == SshAuthType.password
            ? _passwordController.text
            : null,
        privateKey: _authType == SshAuthType.privateKey
            ? _privateKeyController.text
            : null,
        passphrase: _authType == SshAuthType.privateKey
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
                    FilledButton.tonalIcon(
                      onPressed: _pickPrivateKey,
                      icon: const Icon(Icons.file_open),
                      label: const Text('Import private key file'),
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
                      validator: _secretRequiredValidator,
                    ),
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
