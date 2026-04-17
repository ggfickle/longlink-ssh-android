import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../models/ssh_profile.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, required this.profile, required this.secrets});

  final SshProfile profile;
  final SshProfileSecrets secrets;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

enum _ConnectionState { connecting, connected, disconnected, error }

class _TerminalPageState extends State<TerminalPage> {
  late final Terminal _terminal;

  SSHClient? _client;
  SSHSession? _session;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  StreamSubscription<void>? _doneSubscription;

  _ConnectionState _connectionState = _ConnectionState.connecting;
  String _statusText = 'Connecting...';
  String _title = 'Terminal';
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);
    _connect();
  }

  @override
  void dispose() {
    unawaited(_disconnect());
    _stdoutSubscription?.cancel();
    _stderrSubscription?.cancel();
    _doneSubscription?.cancel();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_isConnecting) {
      return;
    }

    setState(() {
      _isConnecting = true;
      _connectionState = _ConnectionState.connecting;
      _statusText =
          'Connecting to ${widget.profile.host}:${widget.profile.port}...';
      _title = widget.profile.displayName;
    });

    _terminal.buffer.clear();
    _terminal.buffer.setCursor(0, 0);
    _terminal.write('LongLink SSH\r\n');
    _terminal.write(
      'Target: ${widget.profile.username}@${widget.profile.host}:${widget.profile.port}\r\n',
    );
    _terminal.write('Timeout: ${widget.profile.connectionTimeoutSeconds}s\r\n');
    _terminal.write(
      'Keepalive: ${widget.profile.keepAliveIntervalSeconds}s\r\n\r\n',
    );
    _terminal.write('Connecting...\r\n');

    try {
      await _disconnect();

      final identities = widget.profile.authType == SshAuthType.privateKey
          ? SSHKeyPair.fromPem(
              widget.secrets.privateKey ?? '',
              _blankToNull(widget.secrets.passphrase),
            )
          : null;

      if (widget.profile.authType == SshAuthType.privateKey &&
          (identities == null || identities.isEmpty)) {
        throw StateError('No private key could be parsed from the saved PEM.');
      }

      final socket = await SSHSocket.connect(
        widget.profile.host,
        widget.profile.port,
        timeout: Duration(seconds: widget.profile.connectionTimeoutSeconds),
      );

      final client = SSHClient(
        socket,
        username: widget.profile.username,
        identities: identities,
        onPasswordRequest: widget.profile.authType == SshAuthType.password
            ? () => widget.secrets.password ?? ''
            : null,
        keepAliveInterval: widget.profile.keepAliveIntervalSeconds > 0
            ? Duration(seconds: widget.profile.keepAliveIntervalSeconds)
            : null,
        onVerifyHostKey: _acceptHostKeyForMvp,
      );

      await client.authenticated;

      final session = await client.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: max(_terminal.viewWidth, 80),
          height: max(_terminal.viewHeight, 24),
        ),
      );

      _client = client;
      _session = session;

      _terminal.onTitleChange = (title) {
        if (!mounted || title.isEmpty) {
          return;
        }
        setState(() => _title = title);
      };

      _terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        _session?.resizeTerminal(width, height, pixelWidth, pixelHeight);
      };

      _terminal.onOutput = (data) {
        _session?.write(Uint8List.fromList(utf8.encode(data)));
      };

      _stdoutSubscription = session.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder())
          .listen(_terminal.write);

      _stderrSubscription = session.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder())
          .listen(_terminal.write);

      _doneSubscription = session.done.asStream().listen((_) {
        final exitCode = session.exitCode;
        final signal = session.exitSignal;
        final details = exitCode != null
            ? 'Remote shell closed with exit code $exitCode.'
            : signal != null
            ? 'Remote shell closed with signal ${signal.signalName}.'
            : 'Remote shell closed.';

        if (mounted) {
          setState(() {
            _connectionState = _ConnectionState.disconnected;
            _statusText = details;
          });
        }

        _terminal.write('\r\n\r\n$details\r\n');
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _connectionState = _ConnectionState.connected;
        _statusText = 'Connected';
        _title = widget.profile.displayName;
      });

      _terminal.write('Connected.\r\n\r\n');
    } catch (error) {
      await _disconnect();
      _terminal.write('Connection failed: $error\r\n');
      if (mounted) {
        setState(() {
          _connectionState = _ConnectionState.error;
          _statusText = 'Connection failed: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<void> _disconnect() async {
    _terminal.onOutput = null;
    _terminal.onResize = null;

    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    await _doneSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    _doneSubscription = null;

    _session?.close();
    _session = null;

    _client?.close();
    await _client?.done.catchError((_) {});
    _client = null;
  }

  FutureOr<bool> _acceptHostKeyForMvp(String type, Uint8List fingerprint) {
    // MVP trade-off: auto-accept host keys so users can connect quickly.
    // Replace this with known_hosts style verification in a future version.
    return true;
  }

  void _sendShortcut(String text) {
    _session?.write(Uint8List.fromList(utf8.encode(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            onPressed: _isConnecting ? null : _connect,
            tooltip: 'Reconnect',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: _statusColor(context),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _statusIcon(),
                      size: 20,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusText,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: Colors.black,
              padding: const EdgeInsets.all(8),
              child: TerminalView(
                _terminal,
                autofocus: true,
                backgroundOpacity: 1,
                theme: const TerminalTheme(
                  cursor: Color(0xFF00E676),
                  foreground: Color(0xFFE0E0E0),
                  background: Color(0xFF000000),
                  selection: Color(0x8033B5E5),
                  black: Color(0xFF000000),
                  red: Color(0xFFE57373),
                  green: Color(0xFF81C784),
                  yellow: Color(0xFFFFF176),
                  blue: Color(0xFF64B5F6),
                  magenta: Color(0xFFBA68C8),
                  cyan: Color(0xFF4DD0E1),
                  white: Color(0xFFE0E0E0),
                  brightBlack: Color(0xFF757575),
                  brightRed: Color(0xFFEF5350),
                  brightGreen: Color(0xFF66BB6A),
                  brightYellow: Color(0xFFFFEE58),
                  brightBlue: Color(0xFF42A5F5),
                  brightMagenta: Color(0xFFAB47BC),
                  brightCyan: Color(0xFF26C6DA),
                  brightWhite: Color(0xFFFFFFFF),
                  searchHitBackground: Color(0xFF355E3B),
                  searchHitBackgroundCurrent: Color(0xFF4C7A50),
                  searchHitForeground: Color(0xFFFFFFFF),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Row(
                children: [
                  _ShortcutButton(
                    label: 'Tab',
                    onTap: () => _sendShortcut('\t'),
                  ),
                  _ShortcutButton(
                    label: 'Esc',
                    onTap: () => _sendShortcut('\x1b'),
                  ),
                  _ShortcutButton(
                    label: 'Ctrl+C',
                    onTap: () => _sendShortcut('\x03'),
                  ),
                  _ShortcutButton(
                    label: '↑',
                    onTap: () => _sendShortcut('\x1b[A'),
                  ),
                  _ShortcutButton(
                    label: '↓',
                    onTap: () => _sendShortcut('\x1b[B'),
                  ),
                  _ShortcutButton(
                    label: '←',
                    onTap: () => _sendShortcut('\x1b[D'),
                  ),
                  _ShortcutButton(
                    label: '→',
                    onTap: () => _sendShortcut('\x1b[C'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (_connectionState) {
      case _ConnectionState.connecting:
        return scheme.secondaryContainer;
      case _ConnectionState.connected:
        return scheme.primaryContainer;
      case _ConnectionState.disconnected:
        return scheme.tertiaryContainer;
      case _ConnectionState.error:
        return scheme.errorContainer;
    }
  }

  IconData _statusIcon() {
    switch (_connectionState) {
      case _ConnectionState.connecting:
        return Icons.sync;
      case _ConnectionState.connected:
        return Icons.check_circle;
      case _ConnectionState.disconnected:
        return Icons.link_off;
      case _ConnectionState.error:
        return Icons.error;
    }
  }

  String? _blankToNull(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value;
  }
}

class _ShortcutButton extends StatelessWidget {
  const _ShortcutButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilledButton.tonal(onPressed: onTap, child: Text(label)),
    );
  }
}
