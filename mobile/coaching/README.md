# اقتدِ — Flutter application

See the [project README](../../README.md) for fresh-checkout setup, architecture,
backend configuration, deployment and verification limits. Commands below assume
PowerShell in this directory, installed Flutter dependencies, and generated
recognizer assets. First run the root setup and `browser/build.ps1`; this recreates
`web/recognizer/`, which is excluded from Git.

```powershell
flutter run -d chrome --web-port 8781
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
```

All six prayer cards analyze recorded videos and live camera frames on-device,
retain three classifier decisions, and save/export/delete local reports. Only
Mosque Companion and optional accounts/monitoring use `BACKEND_URL`; monitoring
sends final scalar results only. References and static Arabic cues are local.
See [local training and deployment](../../docs/LOCAL_TRAINING.md).

For Android, use `flutter devices`, then `flutter run -d <android-device-id>`.
`flutter build apk --release --no-pub` produces
`build/app/outputs/flutter-apk/app-release.apk` with the current local-test signing
configuration. Gradle bundles models from `browser/assets/`. For an emulator's
optional backend, add `--dart-define=BACKEND_URL=http://10.0.2.2:8000`; a physical
phone needs the server's LAN/HTTPS address. The app also provides server settings.

For a production Web build, run:

```powershell
flutter build web --release --no-pub --pwa-strategy=none --no-web-resources-cdn
node browser/scripts/build-offline.mjs
```

Serve/publish all of `build/web/`, including recognizer assets. Camera access needs
HTTPS or localhost. Wait for the offline-ready notice after the initial download.
See [accounts deployment](../../docs/ACCOUNTS.md) for Web cookies and allowed origins.

Web uses a same-origin MediaPipe/ONNX WASM worker with a main-thread fallback.
Android uses the Heavy MediaPipe and three unchanged ONNX models in a native CPU
channel. Selected CPU parity and recorded-video flows are documented on Samsung
M52 / Android 13; physical live-camera and other-device acceptance remain incomplete.
Native iOS/desktop inference is unsupported; the Web app is the available local
inference route on those platforms. See [Android acceptance](../../docs/ANDROID_LOCAL_PERFORMANCE.md)
and [quality options](../../docs/LOCAL_QUALITY_OPTIONS.md). The separate geometry
trainer and explicitly synthetic simulation are retained. Package name `coaching`
is preserved for existing imports and platform identifiers.
