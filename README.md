# اقتدِ — Iqtadi

Arabic-first prayer training with the existing Flutter interface. Images, local
videos, camera recognition, three-model classification, sequence reports,
references, Arabic cues and session history run on-device. **Only Mosque
Companion uses a backend.** Reports describe observed movement coverage; they do
not judge religious validity, intention, recitation or acceptance.

## Project in 60 seconds

```text
Flutter: select prayer + local video/camera/image
    ↓ same-device decoding, oriented RGB, black letterbox and Heavy MediaPipe
166 float32 features → 3 unchanged ONNX classifiers
    ↓ separate softmax distributions → arithmetic probability mean
local temporal events → deterministic sequence alignment
    ↓
Arabic RTL report + three individual decisions + local evidence/history/export
```

Web uses a same-origin WASM worker with an on-device main-thread fallback.
Android uses a native CPU channel and bundles the same models. Existing six
prayer cards and report layouts are retained; the separate local geometry
trainer and clearly labelled synthetic demo remain available in source.
Native iOS/desktop inference is unsupported; physical mobile acceptance remains
unverified. See [deployment and platform limits](docs/LOCAL_TRAINING.md).

## Core concepts and main blocks

| Block | Responsibility | Main location |
|---|---|---|
| Browser recognizer | Exact preprocessing, Heavy landmarks, three ONNX probabilities | `mobile/coaching/browser/src/` |
| Android recognizer | Same preprocessing/models through a serial native channel | `android/app/src/main/kotlin/com/example/coaching/LocalInference*.kt` |
| Local session | Serial observations, stable capture, evidence selection and local save | `mobile/coaching/lib/local/session.dart` |
| Conservative report | Raw Python temporal/alignment semantics, ambiguity and review placement | `browser/src/session.mjs`, `lib/local/report_engine.dart` |
| Local history | Atomic IndexedDB or private Android files, export and explicit deletion | `lib/local/provider_*.dart`, `browser/src/storage.mjs` |
| Existing UI | Video/live progress, per-rakah evidence and all individual decisions | `lib/screens/{video,live}_analysis_screen.dart` |
| References and cues | Local reviewed reference JSON and static Arabic guidance | `lib/prayer/local_reference_*`, `lib/services/prayer_guidance_client.dart` |
| Mosque Companion | Existing optional backend demo integration | `backend/app/mosque/`, `lib/mosque/` |

Paths beginning `lib/`, `android/` and `browser/` are under `mobile/coaching/`.
Model weights/class order are unchanged. [Exact mathematical contract](docs/BROWSER_INFERENCE_SPEC.md).

## Typical flow and state

Choose Fajr → select a local video or open the camera → local models analyze
frames → review each rakah, uncertainty, images and three classifier decisions.
Completed reports survive navigation in **تقاريري على الجهاز**; delete removes
that report and its evidence. Source videos never enter saved history.
References can be imported, reviewed and activated in **المراجع المحلية**.
No trusted reference or religious verdict is invented.

Gallery auto-capture requires three consecutive confident matches; report
observations are retained independently. Live capture defaults to adaptive
throttling and never overlaps inference. Missing or ambiguous observations stay
`UNCONFIRMED`/`REVIEW_REQUIRED`. Probability confidence is not prayer validity.

History allows 10 sessions/128MB, selected evidence up to64MB. Full/denied storage
leaves the report visible and exportable, with a warning and no automatic removal
of older sessions. Prediction schema, model assets and native pipeline versions
invalidate incompatible cached sessions.

## If I want to change...

| Goal | Start here |
|---|---|
| Verify preprocessing/class ordering | `docs/BROWSER_INFERENCE_SPEC.md`, `browser/src/core.mjs` |
| Export unchanged classifiers | `browser/tools/export_models.py` |
| Change conservative report behavior | Python `backend/app/analysis/{temporal,sequence}.py` source; preserve JS/Dart parity |
| Change capture/sampling | `lib/live/live_controller.dart`, `lib/video/`, native camera/video bridges |
| Change history/retention | `lib/local/session.dart`, `browser/src/storage.mjs`, `provider_native.dart` |
| Change report layout | `lib/screens/video_analysis_screen.dart`, `lib/local/prediction_cards.dart` |
| Change design | `lib/ui/app_theme.dart`, `ui_kit.dart` |
| Configure Mosque Companion backend | `lib/config/env.dart`, its settings drawer, `backend/app/mosque/` |

Recommended reading: exact inference contract → local service/session →
browser bridge or native channel → raw report engine → existing results UI.

## Run, test and deploy

No Python backend process is required for prayer training. With the existing
export environment and installed locked dependencies:

```powershell
.\mobile\coaching\browser\build.ps1 -SkipInstall
cd mobile/coaching
flutter test --no-pub --concurrency=1
flutter analyze --no-pub
```

Publish `mobile/coaching/build/web` atomically over HTTPS. On first use download
the static app/model assets and wait for the offline-ready notice. About127MB is
currently cached; no image/landmark/feature request is sent. New updates require
explicit activation. Android bundles its models; device runtime remains
unverified until tested on a connected phone.

[Build/MIME/HTTPS details](docs/BROWSER_DEPLOYMENT.md),
[local training architecture](docs/LOCAL_TRAINING.md),
[measured acceptance](docs/LOCAL_TRAINING_ACCEPTANCE.md),
[references/provenance](docs/LOCAL_REFERENCES.md).

## Retained backend tooling

Only Mosque Companion is a default online feature:
[run the Mosque demo](docs/MOSQUE_COMPANION.md). `BACKEND_URL` configures that
feature. Existing prayer-analysis/reference/guidance backend modules remain
available for development compatibility and regression tests. They are not
selected by the default prayer UI and are not required for inference.

The sections below document that retained legacy server tooling and its
historical validation. The current client runtime and acceptance are described
above and in `LOCAL_TRAINING_ACCEPTANCE.md`.

## API and security

Under `/api/v1/prayer-analyses`: create, upload `/{id}/frames`, finalize
`/{id}/complete`, poll `/{id}`, retrieve `/{id}/report`, fetch
`/{id}/evidence/{evidence_id}`, delete `/{id}`, and public `/config`.
Creation requires explicit consent. Every job operation requires its bearer token.

[Full API schemas/lifecycle](docs/VIDEO_ANALYSIS.md) and
[32-keypoint/model contracts](docs/REAL_MODEL_INTEGRATION.md).
Public deployment requires HTTPS, stronger authentication, creation rate limits
and restricted CORS. Admin routes are loopback-only without `PRAYER_ADMIN_TOKEN`;
with a token every admin request requires its bearer header. Put the old admin
page behind an authenticated gateway that supplies the header before exposing it.
Do not expose default loopback admin through a proxy.

## Tests and current limits

```powershell
cd backend
.venv\Scripts\python.exe -m pytest -q
cd ../mobile/coaching
flutter analyze --no-pub
flutter test --no-pub
flutter build web --no-pub
flutter build apk --debug --no-pub
```

Automated tests require no camera, model weights or paid service. They cover job
ownership, lifecycle/limits/cleanup, temporal confidence, all prayer configurations,
ambiguous/missing/repeated/out-of-order sequences, reports, client state and UI.
Real model accuracy and native-device orientation still need separate acceptance.
Jobs are single-instance/in-memory; decode positions are approximate; codecs depend
on the target platform. Conservative global alignment may leave multiple rakahs
unconfirmed when repeated postures permit several equally plausible assignments.
Live camera JPEG streaming uses a dedicated authenticated WebSocket and the same
backend report engine. No voice, TTS or LLM report generation is used.
Choose **التحليل الدقيق** to retain every sampled image (temporary device storage,
backend disk queue, report after all inference), or **التحليل السريع** to adapt
capture rate to processing capacity. Storage/frame limits stop capture explicitly;
the app does not evict captured images to hide backlog. See [live camera guide](docs/LIVE_CAMERA.md).

Verified October 3, 2026: 56 backend tests and 54 Flutter tests passed; release web
build and Android debug APK assembly passed. `flutter analyze --no-pub` reports
six pre-existing informational findings, with no errors/warnings or findings in
new code. Actual browser tests extracted/uploaded 52 frames and rendered complete
and review-required Fajr reports. After a host CanvasKit shader failure, the optional
`?software=1` renderer displayed the report but evidence images remained blank in
the embedded browser; images had rendered in the earlier default-renderer run.
Chrome rendered the home screen, but its extension blocked file upload because
file URL access was disabled. No Android device runtime test was possible.

## Preserved local training and reference tooling

`التجربة المحلية السابقة` retains the earlier on-device trainer, labelled offline
simulation, calibration, detector/overlay and relevant tests. Administrative
reference videos remain separate from user analysis imagery. The active-reference
and optional guidance APIs remain available. [Local training details](docs/LEGACY_LOCAL_TRAINING.md)
are historical; their no-upload/admin statements are superseded for the new mode.
[Reference authoring guide](docs/prayer-reference-admin.md).

On October 3, 2026, recorded-video analysis became the primary home flow and
backend-owned sequence reports were added; earlier local training remains isolated.
