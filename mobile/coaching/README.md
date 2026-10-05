# اقتدِ — Flutter application

See the [project README](../../README.md) for the prayer architecture, run commands,
Demo Rakah, tests, configuration and limitations.

```powershell
flutter pub get
flutter run -d chrome
flutter test
```

All six prayer cards analyze recorded videos and live camera frames on-device,
retain three classifier decisions, and save/export/delete local reports. Only
Mosque Companion uses `BACKEND_URL`. References and static Arabic cues are local.
See [local training and deployment](../../docs/LOCAL_TRAINING.md).

Web uses a same-origin MediaPipe/ONNX WASM worker with a main-thread fallback.
Android uses the Heavy MediaPipe and three unchanged ONNX models in a native CPU
channel. Native iOS/desktop channel support and physical device acceptance remain
unverified/unsupported; the Web app is available there. The separate geometry
trainer and explicitly synthetic simulation are retained. Package name `coaching`
is preserved for existing imports and platform identifiers.
