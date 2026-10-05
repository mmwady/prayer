# Local Iqtadi prayer training

All six existing prayer cards use local inference for recorded videos and live
camera sessions. The Flutter UI, RTL layout, educational images and conservative
report presentation are retained. Only Mosque Companion uses the configured
backend. Legacy inference/reference/guidance APIs remain in the repository for
compatibility; default prayer navigation never creates their HTTP clients.

## Runtime and ownership

```text
Local camera/video/image
  -> oriented RGB -> black 384x512 Pillow-compatible letterbox/recovery
  -> Heavy MediaPipe IMAGE CPU detector -> exact float32 166 features
  -> three unchanged ONNX models -> separate softmax -> probability mean
  -> local temporal observations -> deterministic all-optimal sequence alignment
  -> Arabic report + selected evidence -> local history/export/delete
```

Web uses the existing same-origin worker/WASM engine through `window.iqtadiLocal`.
If worker initialization fails, the visible main-thread WASM fallback remains
on-device. Android uses `iqtadi/local_inference`, a serial native CPU executor,
MediaPipe Tasks 0.10.32 and ONNX Runtime 1.23.2. Android packages the same verified
model assets directly from `browser/assets`; it does not map ML Kit's legacy
geometry landmarks into the classifiers.

`lib/local/session.dart` serializes inference and rejects stale session results.
Live mode defaults to adaptive capture, throttles before image encoding, and
keeps the three consecutive confident matches rule (.70), three-second cooldown
and held-action deduplication. Buffered mode preserves its bounded local queue.
Gallery capture is separate from report observations; all analyzed observations
participate in the report, including uncertainty. No classifier disagreement is
removed. Confidence describes classification, never religious validity.

Temporal defaults match `backend/app/analysis/temporal.py`: confidence .65,
minimum one observation, minimum duration 0 ms, maximum gap 1000 ms. Reports
preserve the backend's raw deterministic alignment, ambiguity, representative
first-maximum frame and review placement. Optional prediction corrections remain
disabled. Takbir and both Salam directions remain in the expected sequence.

## Local data and references

- Web: atomic IndexedDB report/prediction/evidence writes; hash-verified Cache
  Storage model assets and a versioned service worker for the complete app shell.
- Android: private application files; models bundled in the APK; report export
  uses the system save-document picker.
- Original videos are decoded locally and are not retained in history. Selected
  evidence images and numeric predictions are retained until deletion or version
  invalidation. Leaving a completed report preserves history; its explicit delete
  button removes the saved session and evidence.
- Limits: 20 minutes, 2400 observations, 960px extraction side, 200KB sampled JPEG;
  evidence budget 64MB. History allows 10 sessions or 128MB. Full/denied storage
  shows a warning, leaves the current report visible and exportable, and does not
  silently delete older sessions.
- Prediction schema `2.0.0`, report schema `1.0`, model fingerprints and native
  pipeline version invalidate incompatible cached results, including old objects
  missing any individual classifier decision. Native preprocessing changes must
  increment `android-local-1` in addition to normal model asset versioning.
- **المراجع المحلية** imports, reviews, activates, edits, exports and deletes
  measured reference JSON on-device. No trusted reference is fabricated. New
  calibration-reference extraction from arbitrary video is not part of this
  editor. See [local reference provenance](LOCAL_REFERENCES.md).
- The retained geometry trainer uses static local Arabic cues and an optional
  local reference. It clearly identifies its separate geometry pipeline. The
  main six prayer cards always use the three-model action recognizer.

## Build and deploy

From repository root, use the existing Python 3.11 export environment and the
locked Node/Flutter dependencies:

```powershell
.\mobile\coaching\browser\build.ps1 -SkipInstall
cd mobile/coaching
flutter test --no-pub --concurrency=1
# Android (requires Android SDK/JDK):
flutter build apk --debug --no-pub
```

The browser build exports and numerically validates the unchanged TorchScript
models, runs JS tests, builds the Flutter app and generates the offline manifest.
After any Flutter production build, regenerate the offline manifest:

```powershell
flutter build web --release --no-pub --pwa-strategy=none --no-web-resources-cdn
node browser/scripts/build-offline.mjs
```

Publish `mobile/coaching/build/web` atomically over HTTPS. The app and model files
are static assets; there is no prayer prediction API. First Web use downloads the
app/model assets (currently about 127MB). Wait for the offline-ready notice before
disconnecting. Updates activate through an explicit button, not during training.
Browser storage clearing/eviction can require downloading assets again. Only
Mosque Companion still requires online service access. HTTPS/localhost permits
camera access; a production TLS domain was not provisioned in this task.

See [MIME, worker and WASM hosting](BROWSER_DEPLOYMENT.md) and
[explicit measured results](LOCAL_TRAINING_ACCEPTANCE.md). Native iOS/desktop are
not implemented by the new native channel; use the Web version there. Physical
mobile devices/cameras require device acceptance rather than desktop simulation.
