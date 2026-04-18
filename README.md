# LongLink SSH

Android-first Flutter SSH client for people who need longer connection timeouts when reaching overseas servers.

## What it does

- Save SSH profiles on device
- Create, edit, and delete profiles
- Support password auth and private key auth
- Import private keys from a file or paste them directly from the clipboard
- Generate a fresh ED25519 key pair inside the app and copy either the public or private key when needed
- Store non-secret profile data in `shared_preferences`
- Store password / private key / passphrase in `flutter_secure_storage`
- Use `SSHSocket.connect(host, port, timeout: Duration(seconds: ...))` so each profile can set a longer connect timeout
- Use `SSHClient keepAliveInterval` from the saved profile
- Open an interactive remote shell with `dartssh2` + `xterm`
- Show connection status and connection failure messages clearly
- Add a small Android-friendly shortcut row for Tab / Esc / Ctrl+C / arrows

## Current scope

- **Android only**
- MVP quality, intentionally straightforward
- Current version: **0.1.3+4**

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
- Private key import via file picker or clipboard paste
- Built-in ED25519 key pair generation with public/private key copy support
- Optional passphrase for encrypted private keys
- Connection timeout in seconds
- Keepalive interval in seconds

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

Validated in this environment:

- `flutter pub get` ✅
- `dart format lib test` ✅
- `flutter analyze` ✅
- `flutter test` ✅

Local APK build status:

- `flutter build apk --release` ❌ blocked in this environment because no Android SDK is installed (`No Android SDK found. Try setting the ANDROID_HOME environment variable.`)

## Private key import note

On Android, the system file picker often hides the `.ssh` folder because dot-prefixed folders are treated as hidden. This app now includes a **Paste from clipboard** shortcut for private keys, built-in **Generate key pair** support, and file import reads the key content directly instead of relying on file extensions.

If you still cannot browse to a key file:

- copy the private key text and use **Paste from clipboard**, or
- move/copy the key file into `Downloads` and import it from there, or
- tap **Generate key pair** and use the generated public key on your server.

## Known limitations

- **Host key verification is intentionally permissive right now.** For MVP, the app auto-accepts host keys so connections succeed quickly. This is documented in code and should be replaced with real host verification / known_hosts handling later.
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
