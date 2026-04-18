# LongLink SSH

Android-first Flutter SSH client for people who need longer connection timeouts when reaching overseas servers.

## What it does

- Save SSH profiles on device
- Create, edit, and delete profiles
- Support password auth and private key auth
- Reuse imported/generated private keys across multiple profiles with a shared in-app **SSH keychain**
- Keep backwards compatibility with older profiles that still store inline private key secrets per profile
- Import private keys from a file or paste them directly from the clipboard
- Generate a fresh ED25519 key pair inside the app and copy either the public or private key when needed
- Store non-secret profile data and key metadata in `shared_preferences`
- Store passwords / private keys / passphrases in `flutter_secure_storage`
- Use `SSHSocket.connect(host, port, timeout: Duration(seconds: ...))` so each profile can set a longer connect timeout
- Use `SSHClient keepAliveInterval` from the saved profile
- Keep terminal sessions alive in app memory when you leave the terminal page, then resume them from the home screen without reconnecting
- Show a dedicated **Live sessions** list on the home screen for active/suspended terminals
- Move reconnect into a safer overflow menu and keep explicit disconnect as a separate action
- Open an interactive remote shell with `dartssh2` + `xterm`
- Add a small Android-friendly shortcut row for Tab / Esc / Enter / Ctrl+C / arrows
- Add tmux-oriented quick buttons, including `tmux C-a` and one-tap `tmux detach`

## Current scope

- **Android only**
- MVP quality, intentionally straightforward
- Current version: **0.1.6+7**

## Requirements

- Flutter SDK
- Android SDK for local APK builds
- Android device or emulator
- Minimum Android SDK version: **24**

## Local setup

This repo is expected to use the local Flutter SDK at:

```bash
/root/.openclaw/workspace/.tooling/flutter-sdk/bin/flutter
```

Common commands:

```bash
/root/.openclaw/workspace/.tooling/flutter-sdk/bin/flutter pub get
/root/.openclaw/workspace/.tooling/flutter-sdk/bin/dart format lib test
/root/.openclaw/workspace/.tooling/flutter-sdk/bin/flutter analyze
/root/.openclaw/workspace/.tooling/flutter-sdk/bin/flutter test
/root/.openclaw/workspace/.tooling/flutter-sdk/bin/flutter run
```

Build release APK locally:

```bash
/root/.openclaw/workspace/.tooling/flutter-sdk/bin/flutter build apk --release
```

## Profile fields

Each saved profile includes:

- Display name
- Host
- Port
- Username
- Auth type: password or private key
- Password or private key
- Private key source:
  - profile-only inline secret, or
  - reusable shared keychain entry
- Optional passphrase for encrypted private keys
- Connection timeout in seconds
- Keepalive interval in seconds

## Shared SSH keychain

LongLink now has a simple in-app **SSH keychain**:

- Open it from the key icon on the home screen
- Import a private key once from file / clipboard, or generate a new ED25519 key pair
- Save the key in secure storage
- Reuse the same saved key across multiple SSH profiles
- Copy the stored public key when you need to add it to `authorized_keys`

Backwards compatibility:

- Existing profiles with inline private keys still work
- Editing those profiles keeps the inline-key option available
- New or updated profiles can switch to a shared keychain entry at any time

## Live sessions / suspended terminals

Terminal behavior changed:

- Leaving the terminal page **does not disconnect by default**
- The terminal UI is suspended, while the SSH session stays alive in memory/process
- The home screen now shows a **Live sessions** section
- Tap a suspended session to jump straight back into the same shell without reconnecting
- Use the terminal overflow menu or the home-screen live session menu to reconnect or disconnect explicitly

## CI / release workflow

Workflow file: `.github/workflows/android-release.yml`

Behavior:

- **push to `main`**: run `flutter pub get`, `flutter analyze`, `flutter test`, build release APK, upload APK as workflow artifact
- **`workflow_dispatch`**: same as above
- **tag push `v*`**: build release APK, upload artifact, then create/update a GitHub Release and attach the APK

Notes:

- The Android release build is currently signed with the debug signing config from the default Flutter scaffold. That is okay for MVP testing artifacts, but not for production store distribution.
- If you ship this to users, add a proper signing setup before calling it production-ready.

## Validation run

Validated in this environment after this iteration:

- `flutter pub get`
- `dart format lib test`
- `flutter analyze`
- `flutter test`

## Private key import note

On Android, the system file picker often hides the `.ssh` folder because dot-prefixed folders are treated as hidden. This app includes:

- **Paste from clipboard** for private keys
- built-in **Generate key pair** support
- a reusable **SSH keychain** so you do not have to keep copying the same private key into multiple profiles

If you still cannot browse to a key file:

- copy the private key text and use **Paste from clipboard**, or
- move/copy the key file into `Downloads` and import it from there, or
- tap **Generate key pair** and use the generated public key on your server.

## Known limitations

- **Host key verification is intentionally permissive right now.** For MVP, the app auto-accepts host keys so connections succeed quickly. This is documented in code and should be replaced with real host verification / known_hosts handling later.
- Suspended sessions are kept in app memory only; they are not restored after the app process is killed.
- No SFTP / file transfer support
- No SSH agent forwarding
- No port forwarding UI
- No biometric gating before reading saved secrets
- Terminal UX is intentionally simple and does not yet include a richer mobile keyboard overlay
- CI can build release APKs, but production signing is not configured

## Main packages used

- `dartssh2 2.17.1`
- `xterm 4.0.0`
- `shared_preferences 2.5.5`
- `flutter_secure_storage 10.0.0`
- `file_picker 11.0.2`
- `uuid 4.5.3`
