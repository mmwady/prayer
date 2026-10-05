# Local training acceptance — 2026-10-05

Verified on Windows in Africa/Cairo. All training tests used local files and CPU
inference; no input image, landmarks or feature vector was uploaded. These results
measure implementation parity and observable movement coverage, not religious
validity or accuracy against human labels.

## Delivered artifacts and versions

- Static production app: `mobile/coaching/build/web/`.
- Browser source/worker/export script: `mobile/coaching/browser/`.
- Validated models: `browser/assets/main_seed_{2026,3407,8111}.onnx`, static
  `features:[1,166] -> logits:[1,8]`, opset17; `preprocessing.json` includes the
  exact165 float32 mean/std values. No retraining or weight changes.
- Model version `IMCSPD-MLP-Attention-Hierarchy-v1-e5bdabe3dd0bd9a7`;
  prediction schema `2.0.0`, report schema `1.0`, native pipeline `android-local-1`.
- Offline app version `a87851bb3ed719c373145ca3`: **78 required static assets,
  126,482,161 bytes**, SHA256 checked before activation.
- Android debug APK: `mobile/coaching/build/app/outputs/flutter-apk/app-debug.apk`,
  **333,807,371 bytes**. This is a development artifact, not a signed release.

## Numerical parity

| Level | Actual result |
|---|---|
| Identical landmarks →166 features |263 cases, maximum absolute error0.0 in JS and Kotlin |
| Pillow image/recovery math |20 prepared RGB candidates byte-identical;48 PNG mode/orientation cases pass in JS |
| PyTorch →ONNX, identical features |303 arrays per seed; all individual classes match; max logit errors1.1444092e-5,1.1444092e-5,9.5367432e-6 |
| Browser ONNX WASM, identical features |303 arrays per browser; max probability error2.235180411e-6 within atol2e-6+rtol2e-5 |
| Identical image bytes, Chrome |200/200 action/pose/recovery outcomes match Python |
| Identical image bytes, Edge |200/200 action/pose/recovery outcomes match Python |
| Raw conservative sequence |96 golden cases across all six prayers match |
| Full temporal/report semantics |72 Python cases match JS and Dart, including candidates, ambiguity and review placement |

The corpus contains100 evenly sampled frames from each of the two user-provided
videos in `E:\New folder (3)`. All eight action classes occur;199 poses are valid
and one fails all recovery in both Python and browsers. Frames from the same
videos are correlated and are not independently annotated ground truth.

End-to-end image feature vectors are not universally identical: maximum
standardized feature difference **0.2130613327** (median about0.0017619133), from
native JPEG/MediaPipe numeric differences. The identical-landmark stage is exact.
Universal image-level probability or future-corpus agreement is not claimed.
The100 numerical disagreement cases retain and display all individual decisions.
Each ensemble is the arithmetic mean of three separately softmaxed models, with
the displayed class equal to its maximum. No logits averaging or majority vote.

## Actual application checks

Chrome **154.0.8037.97** and Edge **154.0.4258.53**, using WASM:

- All six original prayer cards open the local video/live routes. No server
  consent checkbox or prediction API is used by those default routes.
- A four-second real local video clip, decoded into16 observations, produces a
  saved local `COMPLETED` report containing exactly three decisions per frame.
  The incomplete observed sequence correctly stays `REVIEW_REQUIRED`.
- Actual UI export downloads JSON; history reopens the report; explicit deletion
  removes a saved session. Complete probability means/ensemble maxima are checked.
- A simulated camera stream from a real local frame produces four analyzed
  observations and one automatic captured action. Three confident consecutive
  matches, held-action deduplication and three retained individual decisions pass.
  This tests the browser capture path, not physical camera hardware.
- Upload, camera-photo and live controls on the standalone recognizer pass;
  upload during active inference releases the camera and shows a fresh result.
- Worker initialization and deliberate main-thread WASM fallback pass. Concurrent
  inference requests are rejected/serialized; no overlapping frame inference.
- Atomic IndexedDB report/evidence save, reopen, export and delete pass. The real
  bridge preserves a32,691-byte annotated evidence JPEG with all three decisions.
- After complete asset caching, network is disabled, Flutter is reloaded, and the
  real Heavy detector plus three ONNX WASM models run again. Saved predictions
  and evidence remain available. The ready notice is visible in the Arabic UI.
- Browser contexts, including worker traffic, report **zero external requests,
  zero image/model-input payload requests, zero prediction API requests, and zero
  page errors** during the local workflows.
- Rendered phone-width screenshots inspected: existing theme/layout retained;
  three cards follow aggregate confidence and captured actions remain expandable.

## Automated checks/builds

- **32/32 Node test groups pass**, including exact preprocessing, softmax/mean,
  class ordering, strict three-model schema, malformed/stale result invalidation,
  cache denial/quota handling, atomic offline updates and required-Web-asset selection.
- **106/106 Flutter tests pass** with `flutter test --no-pub --concurrency=1`.
- `flutter analyze --no-pub`: **zero errors/warnings**, six existing informational
  diagnostics in legacy geometry code. Exit1 for those infos was not suppressed.
- Release Flutter Web build passes with local CanvasKit/WASM and the generated
  offline manifest. Existing PWA-option/Cupertino font notices remain.
- Android Kotlin compilation and debug APK assembly pass; **6/6 Kotlin tests**
  and the three Dart report parity tests pass. APK model/preprocessing/task hashes
  and compiled backup exclusion XML/manifest were verified.
- Android private prayer history and local reference preferences are excluded
  from OS cloud backup/device transfer; actual OS backup execution is unverified.

## Honest compatibility/feature limits

| Target/feature | Actual status |
|---|---|
| Windows Chrome/Edge, WASM |Verified: images, actual video UI, simulated live/photo, worker/fallback, reports/history/export/delete, offline reload/inference |
| Android native |Samsung M52/Android 13 CPU release: 100 real-image cases with exact previous-CPU features/predictions/evidence parity; camera/system export and other devices unverified. See ANDROID_LOCAL_PERFORMANCE.md |
| Android Chrome |Unverified on a physical device |
| Desktop/iOS Safari |Unverified; no Apple device available |
| Firefox/Playwright WebKit |Deferred at the user's request; not claimed as verified |
| Native iOS/desktop inference |Not implemented by the Android channel; Web version available |
| Local references/cues |Unit-tested; measured JSON import/edit/review/activate/export/delete and static guidance; no fabricated reference |
| New calibration reference from arbitrary video |Not implemented by the JSON editor; legacy operator extraction remains in source, unused by training |
| WebGPU |Optional future enhancement; not used or required |
| Production HTTPS domain |Hosting/MIME configuration supplied; no domain/certificate provisioned |

First Web use requires the static asset download. Browser clearing/eviction can
require re-download. Updates activate explicitly; the app/model cache is versioned
as a whole. Only Mosque Companion still depends on an online backend.

## Reproducible evidence

- `output/browser/browser-parity.json`, `live-privacy.json`.
- `mobile/coaching/browser/assets/conversion_report.json`.
- `output/local-training/flutter-workflows.json` and video/live/card screenshots.
- `output/local-training/browser-local-services.json`, `chrome-offline.png`, `msedge-offline.png`.
- `output/local-training/android-build-verification.json` and
  `mobile/coaching/build/app/test-results/testDebugUnitTest/TEST-com.example.coaching.LocalInferenceParityTest.xml`.

Re-run `browser/scripts/verify-browser.mjs`, `verify-live-privacy.mjs`,
`verify-local-flutter.mjs` and `verify-local-services.mjs` after preparing the local
fixtures and production build. Test media and extracted landmarks/features remain
local acceptance fixtures and are not bundled in the production app/APK.
