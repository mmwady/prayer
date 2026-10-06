# Project Map

- `mobile/coaching/lib/l10n/`: source-keyed bilingual presentation catalogs/delegate.
- `mobile/coaching/browser/src/i18n.mjs`, `i18n-copy.mjs`: separate embedded UI
  translation module, receiving same-origin parent locale messages without a reload.

## Default local prayer analysis

- `mobile/coaching/lib/local/` — typed local inference/repository contracts, serial
  sessions, deterministic JS/Dart-compatible reports, three-model cards and offline notice.
- `browser/src/bridge.mjs`, `session.mjs`, `storage.mjs` — Flutter shared worker service,
  raw Python temporal/sequence port, atomic IndexedDB evidence/history and local export.
- `android/app/src/main/kotlin/com/example/coaching/LocalInference*.kt` — Heavy/ONNX CPU
  channel, exact Pillow/float32 math, private storage location and system export picker.
- `lib/screens/local_sessions_screen.dart`, `local_prayer_references_screen.dart` — local
  report review/export/delete and reviewed JSON reference management.
- `browser/scripts/build-offline.mjs`, `web/iqtadi_service_worker.js` — atomically hashed
  same-origin app/model caching, explicit activation and no API-response caching.
- `docs/LOCAL_TRAINING.md`, `LOCAL_TRAINING_ACCEPTANCE.md` — current deployment and measured limits.

## Preserved Local Prayer Learning

- `mobile/coaching/lib/prayer/prayer_definition.dart` — types, pose/station enums, central
  catalog/rakah configuration.
- `mobile/coaching/lib/prayer/prayer_sequence_engine.dart` — observation/state models,
  stability, transitions and local summary counters.
- `mobile/coaching/lib/prayer/prayer_pose_classifier.dart` — configurable side-view geometry
  and conservative confidence handling.
- `mobile/coaching/lib/prayer/prayer_content.dart` — versioned static Arabic labels/feedback,
  pending human review.
- `mobile/coaching/lib/prayer/prayer_reference.dart` — loads the activated schema-2 reference
  and matches normalized 2D samples.
- `mobile/coaching/lib/prayer/prayer_calibration.dart`, `prayer_floor_check.dart` — pre-prayer
  framing/view/stability checks and the optional ruku/sujood floor-coverage probe.
- `mobile/coaching/lib/prayer/prayer_demo_detector.dart` — explicitly synthetic test/development
  source.
- `mobile/coaching/lib/state/prayer_controller.dart` — local orchestration, watchdog, lifecycle,
  and the optional advisory guidance hook.
- `mobile/coaching/lib/services/prayer_guidance_client.dart` — static local Arabic cues
  plus retained injectable HTTP compatibility provider and wire-id mappers.
- `mobile/coaching/lib/screens/prayer_training_screen.dart` — split preview, expected station,
  progress, guidance card, summary.
- `mobile/coaching/lib/screens/home_screen.dart` — Arabic prayer picker; the only entry route.
- `mobile/coaching/test/prayer_*_test.dart`, `test/widget_test.dart` — domain, classifier,
  calibration, guidance, lifecycle and demo tests.
- `docs/IQTADI_MIGRATION.md` — pre-edit migration map and verified final behavior.

## Live camera analysis

- `backend/app/analysis/live.py` — live session ownership, model readiness, ordered WS inference and finalization.
- `backend/app/analysis/jobs.py` — recorded workers/storage and shared report/evidence construction.
- `mobile/coaching/lib/live/` — camera and socket adapters, binary wire client, bounded lifecycle controller.
- `mobile/coaching/lib/live/frame_store*.dart` — native temporary JPEG files / Web IndexedDB
  pending storage, removed after storage ACK or explicit cancellation.
- `mobile/coaching/lib/screens/live_analysis_screen.dart` — Arabic preview, consent, live progress, final report.
- `mobile/coaching/web/live_camera.js` — browser camera/canvas/socket/wake-lock bridges.
- `mobile/coaching/android/app/src/main/kotlin/com/example/coaching/LiveCameraEncoder.kt` — YUV/JPEG conversion and screen awake flag.
- `docs/LIVE_CAMERA.md` — use, transport, limits and acceptance boundaries.
- `backend/tools/{live_smoke_server,verify_live_real}.py` — isolated synthetic transport / real-model no-body checks.

## Repository Root

- `README.md` — architecture narrative, API reference, run instructions.
- `docker-compose.yml` — single-service backend bring-up; healthcheck on `/healthz`.
- `.env` — compose-level `PORT` only. Secrets live in `backend/.env`.
- `.env.example` — full documented template; copy it to `backend/.env`.
- `Agents.md` — run `flutter analyze --no-pub` directly; minimal scoped changes.

## Backend (`backend/`)

- `Dockerfile` — python:3.12-slim, non-root, plain uvicorn (no WebSocket backend flag).
- `pyproject.toml` — PEP 621 dependency and tooling source of truth.
- `requirements.txt` — hand-maintained dev install list (not a full lock).
- `commands.txt` — hot-reload dev command.
- `app/main.py` — app factory: logging, CORS, `/healthz`, prayer reference + guidance routers.
- `app/config.py` — `Settings` (pydantic-settings) + cached `get_settings()`.
- `app/logging_config.py` — idempotent root-logger setup.
- `app/llm/deepseek_client.py` — `DeepSeekClient.complete()`, `LLMNotConfigured`, process singleton.
- `app/prayer/guidance.py` — request/response models, prompt guardrails, static fallback,
  bounded memoisation.
- `app/admin/prayer_references.py` — MP4 upload, per-frame MediaPipe extraction, segment
  annotation, drafts, activation, active-reference API.
- `app/admin/prayer.html` — Arabic frame/segment editor at `/admin/prayer`.
- `tests/test_prayer_references.py` — reference lifecycle and annotation boundaries.
- `tests/test_prayer_guidance.py` — guidance success path, degraded fallback, caching,
  validation, guardrails.

### Backend routes

| Method | Path |
|---|---|
| GET | `/healthz` |
| GET | `/admin/prayer` |
| POST/GET | `/admin/api/prayer-references` |
| GET | `/admin/api/prayer-references/{reference_id}` |
| GET | `/admin/api/prayer-references/{reference_id}/frames/{index}` |
| PUT | `/admin/api/prayer-references/{reference_id}` |
| POST | `/admin/api/prayer-references/{reference_id}/activate` |
| GET | `/api/v1/prayer-reference` |
| GET/POST | `/api/v1/prayer-guidance` |

## Backend Data (`backend/data/`)

- `prayer_references/` — uploaded reference videos, extracted frames, drafts, and `active.json`.

## Frontend (`mobile/coaching/`)

- `pubspec.yaml` — Flutter dependencies: `camera`, `provider`, `http`,
  `google_mlkit_pose_detection`, `js`.
- `web/mediapipe_wrapper.js` — promise-based MediaPipe Pose bridge exposed as `window.estimatePose`.
- `lib/main.dart` — `CoachingApp`, wires `buildAppTheme()` and RTL.
- `lib/ui/app_theme.dart` — design tokens (`AppColors`, `AppSpacing`, `AppRadius`) + the Material 3 dark theme.
- `lib/ui/ui_kit.dart` — shared presentation widgets: `AppCard`, `SectionTitle`, `StatusBanner`, `AppNote`, `PillTag`, `MetricTile`, `StatLine`, `StepTracker`/`TrackerStep`.
- `lib/config/env.dart` — `BACKEND_URL` dart-define.
- `lib/models/keypoint.dart` — `KeypointId`, `Keypoint`, `skeletonBones`, `JointTag`.
- `lib/services/pose_detector.dart` — `PoseDetector` contract + `StubPoseDetector`.
- `lib/services/pose_detector_provider.dart` — conditional export (stub / web / mobile).
- `lib/services/mobile_pose_detector.dart` — ML Kit + `CameraController` implementation.
- `lib/services/web_video_pose_detector.dart` — HTML video file -> inference loop + preview view.
- `lib/services/camera_pose_geometry.dart` — shared aspect/mirroring geometry.
- `lib/widgets/ar_overlay.dart` — stick-figure painter.
- `lib/widgets/prayer_calibration_preview.dart` — reference + tracked skeleton preview.
- `lib/state/locale_provider.dart` — RTL state (Arabic only).

## Generated / Ignored

`.venv/`, `__pycache__/`, `mobile/coaching/build/`, `mobile/coaching/.dart_tool/`,
platform build outputs, and `.env` / `backend/.env` are excluded via `.gitignore`.

## Recorded Video (primary home flow)

- `backend/app/analysis/{contracts,domain,inference,temporal,sequence}.py` — contracts,
  physical vocabulary/prayer configuration, replaceable adapters, stable events and backend reports.
- `backend/app/analysis/{jobs,api,security}.py` — managed workers/storage/retention, authenticated
  job/evidence transport and pre-parse body/admin boundaries.
- `backend/tests/test_video_analysis.py` — new deterministic domain/API/lifecycle tests.
- `backend/tools/create_mock_demo.py` — generates a consent-free H.264 integration video (FFmpeg).
- `mobile/coaching/lib/video/{analysis_client,analysis_controller,analysis_report}.dart` — transport,
  extraction/upload/polling/cancellation state and presentation-only wire models.
- `mobile/coaching/lib/video/video_source*.dart` — conditional native/web local extraction contract.
- `mobile/coaching/web/recorded_video.js` — local file, seeking, oriented canvas JPEGs.
- `mobile/coaching/web/flutter_bootstrap.js` — optional CPU renderer (`?software=1`) for host WebGL failures.
- `mobile/coaching/android/app/src/main/kotlin/com/example/coaching/MainActivity.kt` — document picker,
  unchanged method channel on a single executor, decoder lifecycle, sticky retriever fallback and timing.
- `mobile/coaching/android/app/src/main/kotlin/com/example/coaching/SequentialVideoDecoder.kt` —
  forward native decoding, nearest sample selection and GPU-scaled/rotated frame readback.
- `mobile/coaching/android/app/src/androidTest/kotlin/com/example/coaching/ExtractionInstrumentation.kt` —
  real-device decoding/image/lifecycle checks; `android/generate_extraction_fixtures.ps1` makes local fixtures.
- `docs/ANDROID_VIDEO_EXTRACTION.md` — native benchmark evidence and reproduction instructions.
- `mobile/coaching/lib/screens/video_analysis_screen.dart` — consent/processing/results/evidence UI.
- `mobile/coaching/test/video_analysis_test.dart` — mocked HTTP/state/report/consent/evidence tests.
- `docs/VIDEO_ANALYSIS.md`, `docs/REAL_MODEL_INTEGRATION.md` — lifecycle/demo and future model guide.
- `docs/LEGACY_LOCAL_TRAINING.md` — preserved historical README (superseded architecture statements).
- `backend/data/prayer_analyses/` — ignored temporary user imagery, never served as static content.

## Mosque Companion paths

- `backend/app/mosque/` — isolated demo API/domain/providers/seed/transactional SQLite storage.
- `mobile/coaching/lib/mosque/` — connected Arabic RTL feature and conditional location/Maps services.
- `mobile/coaching/android/app/src/main/kotlin/com/example/coaching/MosqueLocation.kt` — foreground one-shot location/permission/timeout/navigation bridge.
- `backend/start_mosque_demo.ps1`, `docs/MOSQUE_COMPANION.md` — repeatable committee demo setup and limitations.
- `backend/tools/verify_mosque_demo.py` — separate disposable sessions for actual HTTP walking/elder acceptance.
