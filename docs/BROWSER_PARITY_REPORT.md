# Browser/Python parity and acceptance results

Verified locally on Windows, 2026-10-05 (Africa/Cairo). No images or model inputs were
uploaded. This report measures implementation agreement with the supplied Python
predictor; it does not measure religious validity or accuracy against human labels.

## Delivered implementation

All six existing Flutter Web prayer cards now run videos/live locally, with local
reports/history/reference management and static cues. The image/photo home card opens
a same-origin local recognizer. Its image/photo/live
pipeline uses the original Heavy task, Pillow-compatible letterboxing/recovery, float32
166-feature preprocessing and three independently executed WASM ONNX classifiers.
Each model is softmaxed separately; the ensemble is their arithmetic probability mean.
Three model cards and disagreement remain visible, including expandable captured results.
Raw deterministic sequence reports run locally. Legacy backend tooling remains for
compatibility; default prayer navigation uses no backend. Only Mosque Companion does.

Source contract: `BROWSER_INFERENCE_SPEC.md`. Build/deployment: `BROWSER_DEPLOYMENT.md`.
No weights were trained or edited. Model version:
`IMCSPD-MLP-Attention-Hierarchy-v1-e5bdabe3dd0bd9a7`; result schema `2.0.0`.

## Reference corpus

200 evenly sampled, original-resolution frames, 100 from each supplied local recording:

- `E:\New folder (3)\20261003_121030.mp4`
- `E:\New folder (3)\WhatsApp Video 2026-10-03 at 3.49.15 AM.mp4`

One sequential OpenCV decode pass; JPEG quality 95, 4:4:4, orientation applied. Exactly
the same extracted bytes were given to Python and the browser. Frames are correlated
within each video and have no human ground-truth annotations. All eight classes occur
in the Python decisions: Qiyam 12, Takbir 19, Recitation 34, Ruku 47, Sujud 35, Jalsa 19,
Salam Right 26, Salam Left 7; one frame fails all pose recovery attempts.

An earlier robustness corpus had 100 brightness/contrast/rotation/size variants of
10 illustrative project images: Chrome and Edge also matched all 100 decisions.
Those variants are supplementary and are not counted as independent recordings.
Acceptance images/landmarks remain local fixtures and are excluded from production builds.

## Level 1: identical landmarks → features

263 cases: 64 deterministic synthetic landmark sets plus 199 real Python detections.
All 166 values match exactly: maximum absolute feature difference **0**. Acceptance
tolerance: `atol=2e-5, rtol=2e-6`, including hip-centered XYZ, XY scale, visibility,
presence, standardization and final `1.0`.

RGB pixel tests match Pillow exactly for four input dimensions and all five recovery
candidates (20 prepared images, zero differing channels). This includes small images,
Lanczos reduction, black padding, 1% autocontrast, contrast 1.15 and ±5° bicubic rotation.
48 PNG decoding fixtures match Pillow RGB output across all eight EXIF orientations,
alpha, palette and grayscale/16-bit modes. Invalid/nonfinite/degenerate poses are rejected.

The pinned MediaPipe Web public converter originally discarded protobuf presence.
The build preserves the actual emitted field 5 with a hash-guarded converter adapter.
Without that adapter, the initial 10-image check matched only 3 classes; after correction,
10/10 and the subsequent full corpora passed. Graph, task and classifier weights are unchanged.

## Level 2: identical features → model predictions

Python 3.11, Torch `2.14.1+cpu`, ONNX Runtime `1.23.2`. Static ONNX opset 17,
input `features` `[1,166]`, output `logits` `[1,8]`.

| Seed | Feature arrays | Max absolute logit error | Individual class agreement |
|---|---:|---:|---:|
| 2026 | 303 | 0.000011444091796875 | 303/303 |
| 3407 | 303 | 0.000011444091796875 | 303/303 |
| 8111 | 303 | 0.000009536743164063 | 303/303 |

Arrays comprise 64 synthetic normalized poses, 199 actual detections and 40 numerical
stress inputs. Each export passes ONNX checking and `atol=2e-5, rtol=2e-5` comparisons
against a fresh load of the unchanged TorchScript file. Conversion hashes and results:
`mobile/coaching/browser/assets/conversion_report.json`.

Both browsers execute all 303 arrays through ONNX Runtime Web/WASM. Maximum probability
error versus softmax of PyTorch reference logits: **0.000002235180411092053**, within
`atol=2e-6, rtol=2e-5`. Every individual class and the ensemble class matches.
All results contain exactly three seeded decisions. Ensemble probabilities equal the
individual probability arithmetic mean within `1e-12`; the selected class is its maximum.
100 vectors produce classifier disagreement; the UI retains the differing model in both
the primary cards and expandable captured cards. Disagreement UI tests use real numerical
model outputs, rather than fabricated confidence values.

## Level 3: identical images → measured end-to-end agreement

| Browser on Windows | Version | Image class agreement | Pose outcome agreement | Recovery agreement |
|---|---|---:|---:|---:|
| Chrome | 154.0.8037.97 | 200/200 | 200/200 | 200/200 |
| Edge | 154.0.4258.53 | 200/200 | 200/200 | 200/200 |

199/199 detected poses have matching actions; the remaining frame fails in both implementations.
Recovery counts in each implementation: standard 185, autocontrast 0, contrast 1.15
8, rotation −5° 4, rotation +5° 2, failed 1. Autocontrast pixel behavior is independently
covered, even though no corpus image succeeds first through that method.

End-to-end feature vectors are **not universally bit-identical**: the largest standardized
feature difference is **0.21306133270263672** in both browsers. Native JPEG decoding and
MediaPipe CPU/runtime numerics can change detected landmarks. This does not conflict with
the zero-error identical-landmarks test. Universal pixel/landmark equality, image-level
probability equality and future-corpus agreement are not claimed.

Detailed per-image actions, recovery, pose agreement and feature differences:
`output/browser/browser-parity.json`. Earlier robustness results: `variant-parity.json`.

## Application and regression checks

- 32 Node test groups pass: preprocessing, nonfinite rejection, softmax, averaging,
  class order, three complete model slots, schema/version/cache invalidation, hashed
  assets, denied-cache fallback, PNG/Pillow transformations and sequence behavior.
- 96 golden cases match the existing Python raw conservative sequence validator,
  covering all six prayer definitions and missing/repeated/uncertain events.
- Both browsers initialize actual Worker/WASM. Deliberately disabling Worker initializes
  the visible main-thread WASM fallback and passes feature/image inference.
- Upload and camera-photo file controls work; browser-simulated camera snapshot and
  live start/stop work. Physical-camera/mobile acceptance is unverified.
- Responsive 390px primary/captured cards inspected; classifier disagreement remains visible.
- Final Flutter home → local recognizer iframe initializes in Chrome, no page errors:
  `output/browser/flutter-integration.json` and `flutter-local-recognizer.png`.
- `flutter analyze --no-pub`: no errors/warnings; six existing informational lints outside
  the browser integration (command returns 1 for infos). They were not suppressed.
- `flutter test --no-pub --concurrency=1`: final local migration suite106/106 passes. The earlier initial concurrent suite had
  two timing failures in existing live-analysis tests; their isolated run passed and the
  full serial run passed. No backend/live test logic was changed to hide these failures.
- `flutter build web --release --no-pub --pwa-strategy=none --no-web-resources-cdn`: succeeds.
  Existing Cupertino font notice and deprecated PWA-option notice remain. The custom
  versioned offline service worker caches78 required static assets atomically.

Current full Flutter video/live/history/export/delete and network-offline reload
checks passed in Chrome and Edge. Native Android compilation/APK and mathematical
tests also passed; physical device runtime is unverified. See
[complete local migration acceptance](LOCAL_TRAINING_ACCEPTANCE.md) and
`output/local-training/{flutter-workflows,browser-local-services,android-build-verification}.json`.

The focused live/privacy acceptance additionally checks single-flight rejection,
stable automatic capture, held-action deduplication, upload during live recognition,
and network requests across the whole browser context, including UI and Worker traffic.
Both Chrome and Edge pass: one automatic capture for a held action, three model cards,
fresh upload result during live inference, and explicit overlapping-request rejection.
Each context records 30 same-origin static requests, zero requests with payloads/external
destinations and zero page errors. Its measured results are in `output/browser/live-privacy.json`.

## Compatibility and deployment limits

| Target | Actual status |
|---|---|
| Windows Chrome, WASM | Tested: images, worker, fallback, UI and synthetic camera |
| Windows Edge, WASM | Tested: images, worker, fallback, UI and synthetic camera |
| Firefox | Unverified; deferred at user's request after failed host launch attempt |
| Playwright WebKit engine | Unverified; deferred after initialization closed the page |
| Desktop Safari | Unverified; no macOS/Safari device was tested |
| Android Chrome | Unverified; no physical Android browser/camera was tested |
| iOS Safari | Unverified; no physical iOS browser/camera was tested |
| WebGPU | Not used or required; WASM is the default |
| Public HTTPS deployment | Configuration supplied; no domain/certificate was provisioned |

No prediction endpoint was added. Local recognizer code has no image/landmark/feature
upload, WebSocket, beacon or telemetry path. The production nginx template restricts its
asset connections to the same origin and supplies correct WASM/ONNX/JSON/task MIME types.
Existing consented backend flows retain their previous behavior; only the explicit local
recognizer path provides the new fully client-side privacy guarantee.

Remaining acceptance before claiming broad production/device support: physical camera
permissions/orientation, Android/iOS performance/memory, actual Safari, and real HTTPS
hosting rollout including retirement of any previous Flutter service worker. Sub-8-bit
interlaced PNG is explicitly rejected; native JPEG/WebP color/decode differences remain
documented. Existing backend functions are retained while those checks remain outstanding.
