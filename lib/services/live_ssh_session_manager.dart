import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../models/ssh_profile.dart';

class LiveSshSessionManager extends ChangeNotifier {
  final Map<String, LiveSshSessionController> _sessionsByProfileId = {};

  List<LiveSshSessionController> get sessions {
    final items = _sessionsByProfileId.values.toList();
    items.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return items;
  }

  LiveSshSessionController obtainSession({
    required SshProfile profile,
    required SshProfileSecrets secrets,
  }) {
    final existing = _sessionsByProfileId[profile.id];
    if (existing != null) {
      existing.updateProfile(profile, secrets);
      return existing;
    }

    final session = LiveSshSessionController(
      profile: profile,
      secrets: secrets,
      onChanged: notifyListeners,
      onRemoved: () => _removeSession(profile.id),
    );
    _sessionsByProfileId[profile.id] = session;
    notifyListeners();
    return session;
  }

  void _removeSession(String profileId) {
    _sessionsByProfileId.remove(profileId);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final session in _sessionsByProfileId.values) {
      session.dispose();
    }
    _sessionsByProfileId.clear();
    super.dispose();
  }
}

enum LiveSshSessionState { connecting, active, suspended, disconnected, error }

class LiveSshSessionController extends ChangeNotifier {
  LiveSshSessionController({
    required SshProfile profile,
    required SshProfileSecrets secrets,
    required VoidCallback onChanged,
    required VoidCallback onRemoved,
  }) : _profile = profile,
       _secrets = secrets,
       _notifyManager = onChanged,
       _removeFromManager = onRemoved,
       terminal = Terminal(maxLines: 10000) {
    _title = profile.displayName;
    _statusText = 'Ready to connect';
  }

  final Terminal terminal;
  final VoidCallback _notifyManager;
  final VoidCallback _removeFromManager;

  SshProfile _profile;
  SshProfileSecrets _secrets;
  SSHClient? _client;
  SSHSession? _session;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  StreamSubscription<void>? _doneSubscription;

  bool _uiAttached = false;
  bool _isConnecting = false;
  bool _isDisposed = false;
  bool _wasExplicitlyClosed = false;
  DateTime _updatedAt = DateTime.now();
  LiveSshSessionState _state = LiveSshSessionState.disconnected;
  String _statusText = '';
  String _title = 'Terminal';

  SshProfile get profile => _profile;
  DateTime get updatedAt => _updatedAt;
  LiveSshSessionState get state => _state;
  String get statusText => _statusText;
  String get title => _title;
  bool get isConnecting => _isConnecting;
  bool get isAlive =>
      _state == LiveSshSessionState.active ||
      _state == LiveSshSessionState.suspended;
  String get targetLabel =>
      '${_profile.username}@${_profile.host}:${_profile.port}';

  void updateProfile(SshProfile profile, SshProfileSecrets secrets) {
    _profile = profile;
    _secrets = secrets;
    if (_title.trim().isEmpty || _title == 'Terminal') {
      _title = profile.displayName;
    }
    _touch();
    _notifyAll();
  }

  void attachUi() {
    _uiAttached = true;
    terminal.onTitleChange = (title) {
      if (title.trim().isEmpty) {
        return;
      }
      _title = title;
      _touch();
      _notifyAll();
    };
    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      _session?.resizeTerminal(width, height, pixelWidth, pixelHeight);
    };
    terminal.onOutput = (data) {
      _session?.write(Uint8List.fromList(utf8.encode(data)));
    };

    if (_state == LiveSshSessionState.suspended) {
      _state = LiveSshSessionState.active;
      _statusText = 'Connected';
      _touch();
    }

    _notifyAll();
  }

  void detachUi() {
    _uiAttached = false;
    terminal.onOutput = null;
    terminal.onResize = null;
    terminal.onTitleChange = null;

    if (_state == LiveSshSessionState.active) {
      _state = LiveSshSessionState.suspended;
      _statusText = 'Suspended. Session is still connected.';
      _touch();
    }

    _notifyAll();
  }

  Future<void> ensureConnected() async {
    if (_isConnecting || isAlive) {
      return;
    }
    await connect(clearTerminal: true);
  }

  Future<void> reconnect() async {
    await connect(clearTerminal: true, isReconnect: true);
  }

  Future<void> connect({
    bool clearTerminal = true,
    bool isReconnect = false,
  }) async {
    if (_isConnecting || _isDisposed) {
      return;
    }

    _wasExplicitlyClosed = false;
    _isConnecting = true;
    _state = LiveSshSessionState.connecting;
    _statusText = isReconnect
        ? 'Reconnecting to ${_profile.host}:${_profile.port}...'
        : 'Connecting to ${_profile.host}:${_profile.port}...';
    _title = _profile.displayName;
    _touch();
    _notifyAll();

    if (clearTerminal) {
      terminal.buffer.clear();
      terminal.buffer.setCursor(0, 0);
      terminal.write('LongLink SSH\r\n');
      terminal.write('Target: $targetLabel\r\n');
      terminal.write('Timeout: ${_profile.connectionTimeoutSeconds}s\r\n');
      terminal.write(
        'Keepalive: ${_profile.keepAliveIntervalSeconds}s\r\n\r\n',
      );
      terminal.write(isReconnect ? 'Reconnecting...\r\n' : 'Connecting...\r\n');
    } else {
      terminal.write('\r\nReconnecting...\r\n');
    }

    try {
      await _teardownTransport();

      final identities = _profile.authType == SshAuthType.privateKey
          ? SSHKeyPair.fromPem(
              _secrets.privateKey ?? '',
              _blankToNull(_secrets.passphrase),
            )
          : null;

      if (_profile.authType == SshAuthType.privateKey &&
          (identities == null || identities.isEmpty)) {
        throw StateError('No private key could be parsed from the saved PEM.');
      }

      final socket = await SSHSocket.connect(
        _profile.host,
        _profile.port,
        timeout: Duration(seconds: _profile.connectionTimeoutSeconds),
      );

      final client = SSHClient(
        socket,
        username: _profile.username,
        identities: identities,
        onPasswordRequest: _profile.authType == SshAuthType.password
            ? () => _secrets.password ?? ''
            : null,
        keepAliveInterval: _profile.keepAliveIntervalSeconds > 0
            ? Duration(seconds: _profile.keepAliveIntervalSeconds)
            : null,
        onVerifyHostKey: _acceptHostKeyForMvp,
      );

      await client.authenticated;

      final session = await client.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: max(terminal.viewWidth, 80),
          height: max(terminal.viewHeight, 24),
        ),
      );

      _client = client;
      _session = session;

      _stdoutSubscription = session.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder())
          .listen(terminal.write);
      _stderrSubscription = session.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder())
          .listen(terminal.write);
      _doneSubscription = session.done.asStream().listen((_) {
        if (_isDisposed || _wasExplicitlyClosed) {
          return;
        }

        final exitCode = session.exitCode;
        final signal = session.exitSignal;
        final details = exitCode != null
            ? 'Remote shell closed with exit code $exitCode.'
            : signal != null
            ? 'Remote shell closed with signal ${signal.signalName}.'
            : 'Remote shell closed.';

        terminal.write('\r\n\r\n$details\r\n');
        _state = LiveSshSessionState.disconnected;
        _statusText = details;
        _touch();
        _notifyAll();
      });

      _state = _uiAttached
          ? LiveSshSessionState.active
          : LiveSshSessionState.suspended;
      _statusText = _uiAttached ? 'Connected' : 'Connected in background';
      _touch();
      _notifyAll();

      terminal.write('Connected.\r\n\r\n');
    } catch (error) {
      await _teardownTransport();
      terminal.write('Connection failed: $error\r\n');
      _state = LiveSshSessionState.error;
      _statusText = 'Connection failed: $error';
      _touch();
      _notifyAll();
    } finally {
      _isConnecting = false;
      _notifyAll();
    }
  }

  Future<void> close() async {
    if (_isDisposed) {
      return;
    }

    _wasExplicitlyClosed = true;
    terminal.write('\r\n\r\nDisconnecting...\r\n');
    await _teardownTransport();
    _state = LiveSshSessionState.disconnected;
    _statusText = 'Disconnected';
    _touch();
    _notifyAll();
    _removeFromManager();
  }

  void sendShortcut(String text) {
    _session?.write(Uint8List.fromList(utf8.encode(text)));
  }

  void sendTmuxPrefix() {
    sendShortcut('\x01');
  }

  void sendTmuxDetach() {
    sendShortcut('\x01d');
  }

  void sendEnter() {
    sendShortcut('\r');
  }

  Future<void> _teardownTransport() async {
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    await _doneSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    _doneSubscription = null;

    _session?.close();
    _session = null;

    final client = _client;
    _client = null;
    client?.close();
    try {
      await client?.done;
    } catch (_) {
      // Ignore teardown errors.
    }
  }

  FutureOr<bool> _acceptHostKeyForMvp(String type, Uint8List fingerprint) {
    return true;
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  void _touch() {
    _updatedAt = DateTime.now();
  }

  void _notifyAll() {
    if (_isDisposed) {
      return;
    }
    notifyListeners();
    _notifyManager();
  }

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    unawaited(_teardownTransport());
    super.dispose();
  }
}
