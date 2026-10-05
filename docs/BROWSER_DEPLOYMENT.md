# Iqtadi browser inference

All six existing Flutter prayer cards now process recorded videos and live camera
frames locally. Reports, sequence validation, references, Arabic cues and history
stay on-device. Only Mosque Companion contacts the configured backend. The Web
home's image/photo card and standalone `/recognizer/index.html` are also local.
Legacy backend tooling remains available for compatibility, outside default prayer
navigation. See [complete local flow](LOCAL_TRAINING.md).

## Deliverable locations

- Source, worker, export scripts, tests, deployment config: `mobile/coaching/browser/`.
- Validated ONNX files, exact float32 JSON, task model, manifest and numerical report:
  `mobile/coaching/browser/assets/`.
- Standalone static distribution: `mobile/coaching/web/recognizer/`.
- Integrated Flutter production distribution: `mobile/coaching/build/web/`.
- Mathematical source contract: `docs/BROWSER_INFERENCE_SPEC.md`.
- Measured acceptance: `docs/BROWSER_PARITY_REPORT.md`, `output/browser/browser-parity.json`.

## Build / export (PowerShell from repository root)

Use Python 3.11 with the existing working CPU Torch, NumPy, Pillow and MediaPipe environment.
No GPU/provider calls or training. Install export-only dependencies if needed:

```powershell
.\backend\.venv\Scripts\python.exe -m pip install -r mobile/coaching/browser/tools/requirements-export.txt
.\mobile\coaching\browser\build.ps1
```

The build always exports static `[1,166]` models with input `features`, output `logits`,
opset 17, checks ONNX contracts and compares each model's logits and class against
PyTorch. The script fails on conversion/test errors. Package versions are locked.
Build-only `npm run build` checks source fingerprints: any pipeline/package change
requires export/versioning again. It refuses an unreviewed MediaPipe package upgrade.
The upstream converter must retain protobuf presence; dropping it changes classifications.

For manual steps, run export, tests and JS build from `mobile/coaching/browser`, then
`flutter analyze --no-pub` and `flutter build web --release --no-pub --pwa-strategy=none --no-web-resources-cdn`
from `mobile/coaching`, followed by `node browser/scripts/build-offline.mjs`. Initial Flutter dependency resolution uses the existing lockfile.

## Local verification and three parity levels

Generate Python image references from a consented local directory or video:

```powershell
.\backend\.venv\Scripts\python.exe mobile/coaching/browser/tools/prepare_parity.py --images C:\local\prayer-images
# Alternative: sample at least 100 frames from a local video
.\backend\.venv\Scripts\python.exe mobile/coaching/browser/tools/prepare_parity.py --video C:\local\prayer.mp4 --count 100
# Re-export to include the real image feature vectors in model verification.
.\backend\.venv\Scripts\python.exe mobile/coaching/browser/tools/export_models.py
cd mobile/coaching/browser
npm.cmd run build
npm.cmd test
node scripts/verify-browser.mjs --chromium
node scripts/verify-flutter.mjs
node scripts/verify-live-privacy.mjs
node scripts/verify-local-services.mjs
node scripts/verify-local-flutter.mjs
```

Python source and weights are loaded unchanged. Feature fixtures compare identical
landmarks, model fixtures compare identical feature inputs, and images compare both
detectors end to end. The final JSON records disagreement, failed detections, recovery,
feature error, tested browser versions, and requests with bodies/external destinations.
The final corpus contains 200 frames sampled from the two user-supplied local videos
(100 per video). Earlier robustness checks used 100 variants of 10 illustrative images.
Frames from a video are correlated; agreement with Python is not ground-truth accuracy.
Fixtures/images are acceptance-only and never copied into the production distribution.
Generated image references and feature/landmark fixtures are Git-ignored because they
can contain user-video observations; recreate them locally with the scripts above.

Camera browser checks use simulated getUserMedia on Chrome/Edge. Mobile browsers,
physical cameras, native desktop Safari and low-memory phones need actual device tests.
WebKit automation is not a substitute for Safari/iOS device acceptance.
Chrome and Edge are the current acceptance targets, as requested. Firefox/WebKit were
deferred after unsuccessful engine runs on this host; neither is claimed as verified.
Optional future engine checks use `--all` after installing Playwright's Firefox/WebKit.

## HTTPS and static hosting

Publish **only** `mobile/coaching/build/web` to any HTTPS static host, or publish the
standalone recognizer directory with its vendor/assets/chunks intact. No inference
service, prediction endpoint, STUN/TURN server or API key is needed. A localhost-only
test server is `npm run serve`; its HTTP exception is for local development only.
Production example: `mobile/coaching/browser/deploy/nginx.conf`. Supply your real domain,
TLS certificate and root; no production domain/certificate was provisioned by this task.

Required MIME: `.wasm` application/wasm; `.onnx` and `.task` application/octet-stream;
`.json` application/json; `.js`/`.mjs` text/javascript. Do not rewrite a missing model,
worker or WASM path to Flutter's index.html. Worker and all vision/ORT binaries are
same-origin. Single-thread WASM works without SharedArrayBuffer/COOP/COEP. The CPU
delegate and WASM execution provider are the defaults; WebGPU is not required.

The recognizer CSP permits only same-origin asset connections; there is no fetch POST,
WebSocket, beacon, form upload or external telemetry. The Flutter prayer routes use the same
local pipeline. Mosque Companion remains the only default online integration.

## Caching, privacy and lifecycle

Normal HTTP caching plus Cache Storage stores hash-verified models under their version.
`manifest.json` revalidates. The model version fingerprints weights, preprocessing,
inference source and package lock; the result schema is independently versioned.
Old model caches are removed; old/corrupt/incomplete results, including results without
exactly three individual model slots, are rejected. No cached ONNX session survives an
engine/page restart. Deploy the full directory atomically; revalidate HTML/scripts and
use `--pwa-strategy=none` to disable the legacy Flutter cache. The generated custom
`iqtadi_service_worker.js` hash-verifies the complete app version before activation.
Old Flutter service workers are retired by `iqtadi_offline.js`. New app updates wait
for explicit activation; the UI shows download progress/offline readiness. Run the
offline generator after every Flutter build.

Images/landmarks/features never leave the device. The standalone gallery keeps the
newest 12 images in memory and numeric results in tab sessionStorage. Integrated
prayer reports use IndexedDB for selected evidence and complete predictions, capped
at 10 sessions/128MB with explicit full-storage warnings. Reports survive navigation;
explicit deletion removes saved data. Backgrounding closes camera tracks. Android
uses private application files and system document export.
Large image limits: 50 MB encoded, 40 megapixels decoded. Worker initialization failure
uses a visible slower main-thread WASM fallback; failures never call a backend or mock.

Local sequence reports port the existing raw conservative validator. Classification
confidence and classifier disagreement remain visible; ambiguous stations stay
UNCONFIRMED/REVIEW_REQUIRED. There is no religious validity/acceptance verdict. The local
report uses all sampled inference results in order; automatic gallery capture separately
retains the original three-stable-matches/70% default/three-second cooldown rule.

PNG transparency and eXIf use the exact RGB decoder path. Sub-8-bit interlaced PNG is
explicitly unsupported. JPEG/WebP native decoder and browser CPU numeric differences
must be measured on your target corpus; universal pixel-identical image parity is not claimed.
