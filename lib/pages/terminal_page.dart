import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../services/live_ssh_session_manager.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({
    super.key,
    required this.session,
    required this.connectOnOpen,
  });

  final LiveSshSessionController session;
  final bool connectOnOpen;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_handleSessionChanged);
    widget.session.attachUi();
    if (widget.connectOnOpen) {
      unawaited(widget.session.ensureConnected());
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_handleSessionChanged);
    widget.session.detachUi();
    super.dispose();
  }

  void _handleSessionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleMenuAction(_TerminalAction action) async {
    switch (action) {
      case _TerminalAction.suspend:
        if (mounted) {
          Navigator.of(context).pop();
        }
        break;
      case _TerminalAction.reconnect:
        await _confirmAndReconnect();
        break;
      case _TerminalAction.disconnect:
        await _confirmAndDisconnect();
        break;
    }
  }

  Future<void> _confirmAndReconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reconnect session?'),
        content: Text('Reconnect ${widget.session.profile.displayName} now?'),
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

    await widget.session.reconnect();
  }

  Future<void> _confirmAndDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect session?'),
        content: Text('Close ${widget.session.profile.displayName} now?'),
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

    await widget.session.close();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;

    return Scaffold(
      appBar: AppBar(
        title: Text(session.title),
        actions: [
          PopupMenuButton<_TerminalAction>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _TerminalAction.suspend,
                child: Text('Suspend and go back'),
              ),
              PopupMenuItem(
                value: _TerminalAction.reconnect,
                child: Text('Reconnect'),
              ),
              PopupMenuItem(
                value: _TerminalAction.disconnect,
                child: Text('Disconnect'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: _statusColor(context, session.state),
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
                      _statusIcon(session.state),
                      size: 20,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        session.statusText,
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
                session.terminal,
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
                    onTap: () => session.sendShortcut('\t'),
                  ),
                  _ShortcutButton(
                    label: 'Esc',
                    onTap: () => session.sendShortcut('\x1b'),
                  ),
                  _ShortcutButton(label: 'Enter', onTap: session.sendEnter),
                  _ShortcutButton(
                    label: 'Ctrl+C',
                    onTap: () => session.sendShortcut('\x03'),
                  ),
                  _ShortcutButton(
                    label: 'tmux C-a',
                    onTap: session.sendTmuxPrefix,
                  ),
                  _ShortcutButton(
                    label: 'tmux detach',
                    onTap: session.sendTmuxDetach,
                  ),
                  _ShortcutButton(
                    label: '↑',
                    onTap: () => session.sendShortcut('\x1b[A'),
                  ),
                  _ShortcutButton(
                    label: '↓',
                    onTap: () => session.sendShortcut('\x1b[B'),
                  ),
                  _ShortcutButton(
                    label: '←',
                    onTap: () => session.sendShortcut('\x1b[D'),
                  ),
                  _ShortcutButton(
                    label: '→',
                    onTap: () => session.sendShortcut('\x1b[C'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(BuildContext context, LiveSshSessionState state) {
    final scheme = Theme.of(context).colorScheme;
    switch (state) {
      case LiveSshSessionState.connecting:
        return scheme.secondaryContainer;
      case LiveSshSessionState.active:
      case LiveSshSessionState.suspended:
        return scheme.primaryContainer;
      case LiveSshSessionState.disconnected:
        return scheme.tertiaryContainer;
      case LiveSshSessionState.error:
        return scheme.errorContainer;
    }
  }

  IconData _statusIcon(LiveSshSessionState state) {
    switch (state) {
      case LiveSshSessionState.connecting:
        return Icons.sync;
      case LiveSshSessionState.active:
        return Icons.check_circle;
      case LiveSshSessionState.suspended:
        return Icons.pause_circle;
      case LiveSshSessionState.disconnected:
        return Icons.link_off;
      case LiveSshSessionState.error:
        return Icons.error;
    }
  }
}

enum _TerminalAction { suspend, reconnect, disconnect }

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
