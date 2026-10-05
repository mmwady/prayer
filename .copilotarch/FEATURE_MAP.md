# Feature Map

## Optional account monitoring (2026-10-05)

- `mobile/coaching/lib/accounts/`: backend login/signup, SMTP email actions,
  secure native tokens / HttpOnly Web cookies, child QR/manual pairing, scoped
  persistent result queue, Arabic responsive dashboard and device revocation.
- `backend/app/accounts/`: Argon2id, SQLite ownership/device authorization,
  atomic hashed expiring pairing, strict scalar attempts and deterministic timing/scoring.
- Post-result hook: `local/session.dart`, shared by the selected-prayer video
  and live-camera workflows. Standalone browser reports remain local only.
  No MediaPipe/166-feature/ONNX/sequence algorithm changes.
- `docs/ACCOUNTS.md`: deployment settings, endpoint/files inventory and exact gates.
- `test/accounts_test.dart`, `backend/tests/test_accounts.py`,
  `browser/scripts/verify-accounts.mjs`: queue/privacy/security/browser acceptance.

## On-device browser prayer action recognition

- Home Web-only card → conditional `lib/browser/recognizer_screen.dart` → same-origin iframe.
- `mobile/coaching/browser/src/`: exact float32 features, Pillow-compatible RGB/Lanczos/recovery,
  tasks-vision Heavy IMAGE detector, classic Web Worker, visible main-thread WASM fallback,
  three separate ONNX model probabilities, versioned complete individual results and local reports.
- `tools/export_models.py`: unchanged TorchScript → opset-17 static [1,166], validated models,
  preprocessing JSON, asset + runtime fingerprints. `scripts/mediapipe-presence.mjs` retains the
  genuine protobuf presence field dropped by the pinned upstream JS converter (hash guard).
- `src/sequence.mjs`: raw conservative Python sequence alignment; optional corrections absent.
- `src/app.mjs`: upload/photo/live controls; no overlapping inference; three confident matches,
  cooldown/dedup; aggregate and individual cards; uncertainty; tab-local result cache.
- Static output `web/recognizer/` and integrated `build/web/`; no prediction endpoint.
- Tests and parity harness `browser/test/`, `browser/scripts/verify-browser.mjs`; docs
  `docs/BROWSER_INFERENCE_SPEC.md`, `BROWSER_DEPLOYMENT.md`, `BROWSER_PARITY_REPORT.md`.
- All six main prayer routes now share this local pipeline via `lib/local/`; legacy backend
  flows remain development/test tools and are never selected by default. Local history,
  export/delete, reference editor and static cues are part of the existing Flutter experience.

## Preserved Local Iqtadi Prayer Training

Entry points:
- `mobile/coaching/lib/screens/home_screen.dart`
- `mobile/coaching/lib/screens/prayer_training_screen.dart`

Core implementation:
- `mobile/coaching/lib/state/prayer_controller.dart`
- `mobile/coaching/lib/prayer/prayer_definition.dart`
- `mobile/coaching/lib/prayer/prayer_sequence_engine.dart`
- `mobile/coaching/lib/prayer/prayer_pose_classifier.dart`
- `mobile/coaching/lib/prayer/prayer_content.dart`

Development source:
- `mobile/coaching/lib/prayer/prayer_demo_detector.dart`

Tests:
- `mobile/coaching/test/prayer_sequence_test.dart`
- `mobile/coaching/test/prayer_pose_classifier_test.dart`
- `mobile/coaching/test/prayer_controller_test.dart`
- `mobile/coaching/test/prayer_calibration_test.dart`
- `mobile/coaching/test/prayer_calibration_widget_test.dart`
- `mobile/coaching/test/widget_test.dart`

Important constraints:
- Reuses the conditional detector and ArOverlay; no video upload.
- Central configuration, one shared engine, contextual stations and stable confidence.
- Final/intermediate sittings are explicit stations; six core movements counted separately.
- Static content is versioned, but human review remains pending.
- Desktop simulation is labelled and cannot claim observed prayer performance.

## Arabic Prayer Guidance (DeepSeek `deepseek-flash`)

Entry points:
- `backend/app/prayer/guidance.py` (`GET`/`POST /api/v1/prayer-guidance`)
- `mobile/coaching/lib/services/prayer_guidance_client.dart`

Core implementation:
- `backend/app/llm/deepseek_client.py` (`complete`, `LLMNotConfigured`)
- `backend/app/config.py` (`DEEPSEEK_*`, `PRAYER_GUIDANCE_ENABLED`)
- `mobile/coaching/lib/state/prayer_controller.dart` (`_maybeRequestGuidance`, `_requestGuidance`)

Tests:
- `backend/tests/test_prayer_guidance.py`
- `mobile/coaching/test/prayer_guidance_test.dart`
- `mobile/coaching/test/prayer_guidance_controller_test.dart`

Important constraints:
- Advisory only: the route never gates station progression and always returns HTTP 200.
- Every failure path returns static Arabic text with `model: "static"`, `degraded: true`.
- Requests fire on discrete events only and are deduped by `(event, station, rakah)`.
- The payload carries no pixels, keypoints, frames or identity.
- The prompt forbids religious rulings and any validity/acceptance judgement.
- Thinking mode stays disabled: `deepseek-flash` defaults to effort=high reasoning, which would
  consume the token budget and can return empty `content`.
- Only `deepseek-flash` and `deepseek-v4-pro` are valid model names; `deepseek-chat` is retired.

## Prayer Reference Authoring

- Backend routes/extraction/storage: `backend/app/admin/prayer_references.py`.
- Arabic frame/segment editor: `backend/app/admin/prayer.html` (`/admin/prayer`).
- Active reference API: `GET /api/v1/prayer-reference`.
- Focused lifecycle/boundary tests: `backend/tests/test_prayer_references.py`.
- Usage/limitations: `docs/prayer-reference-admin.md`.
- The six core station ids and their order are mirrored by `prayer/guidance.py`; a test guards drift.

## Reference Calibration

`prayer_reference.dart` loads activated schema-2 JSON and matches normalized 2D samples.
`prayer_calibration.dart` checks projected view, framing and stability; `prayer_floor_check.dart`
optionally probes ruku/sujood visibility. `PrayerController` keeps calibration frames out of
station counting. `prayer_calibration_preview.dart` shares camera aspect/mirroring with both
reference and tracked skeletons. Native experimental ML Kit depth is tagged separately from
MediaPipe world3D. Tests: calibration domain and widget files; real device accuracy is pending.

## Flutter Pose Detection Providers

Entry points:
- `mobile/coaching/lib/services/pose_detector_provider.dart`

Core implementation:
- `mobile/coaching/lib/services/pose_detector.dart` (contract + stub)
- `mobile/coaching/lib/services/mobile_pose_detector.dart`
- `mobile/coaching/lib/services/web_video_pose_detector.dart`
- `mobile/coaching/lib/services/pose_detector_provider_web.dart`
- `mobile/coaching/web/mediapipe_wrapper.js`

Important constraints:
- Android/iOS use ML Kit; every other `dart:io` target falls back to the stub.
- Web keys off a user-selected local video file, not the camera.
- The prayer screen rejects `StubPoseDetector` and points at labelled simulation instead.

## Flutter AR Overlay

Entry points:
- `mobile/coaching/lib/widgets/ar_overlay.dart`

State / Storage:
- `mobile/coaching/lib/models/keypoint.dart` (`skeletonBones`, `JointTag`)

Important constraints:
- Bones and joints below 0.3 confidence are skipped.
- The overlay renders the observed skeleton only; it carries no coaching state.

## RTL / Locale

Entry points:
- `mobile/coaching/lib/state/locale_provider.dart`
- `mobile/coaching/lib/main.dart` (RTL `Directionality`)

Important constraints:
- Arabic is the only supported locale and the UI strings are hard-coded Arabic.
- There is no translation dictionary or language switcher any more.

## Removed Sports Features (do not resurrect)

The following were deleted along with the sports product: realtime coaching WebSocket
(`/ws/coach`), LangGraph decision graph, LLM coaching prompts, pluggable TTS providers,
exercise template/rule APIs, the admin template dashboard and generator, the Flutter workout
screen/controller, `FormAnalyzer`, DTW/phase rep counters, `WsClient`, streaming audio playback
and the bilingual translation dictionary. There is no WebSocket wire protocol.

## Recorded Prayer Video Analysis

- Entry: `screens/home_screen.dart` → `screens/video_analysis_screen.dart`.
- Client: `lib/video/analysis_controller.dart`, `analysis_client.dart`, `analysis_report.dart`.
- Extraction: conditional `lib/video/video_source_provider.dart`, `web/recorded_video.js`, Android bridge.
- Backend: `/api/v1/prayer-analyses` in `app/analysis/api.py`, lifecycle/storage in `jobs.py`.
- Inference: independent keypoint/pose interfaces in `inference.py`; explicit mock opt-in/scenarios;
  real mode fails MODEL_NOT_CONFIGURED, never silently falls back.
- Events/sequence/report: `temporal.py`, `sequence.py`, `domain.py`, `contracts.py`.
- Privacy: explicit consent, bounded JPEGs, job bearer token, no-store evidence, temporary retention.
- Tests: `backend/tests/test_video_analysis.py`, Flutter `test/video_analysis_test.dart`.
- Evidence: confirmed stations only; mock frames visibly labelled as illustrative synthetic associations.
- Real report evidence (including review/unexpected events) is annotated with confidence-filtered MediaPipe joints and emerald bones, preserving original resolution and reversing detection letterbox/rotation. JPEG evidence uses quality 95; the existing private endpoint serves it. No anatomical data is added to the report contract. Flutter evidence previews are 260px high with rounded edges.
- Flutter renders backend decisions; local trainer/LLM never determines this report.
- Unconfirmed stations show bundled educational examples from `mobile/coaching/assets/prayer_positions/` (supplied in `backend/images/`). When exactly one station is missing between two timestamped stations, same-rakah review evidence in that interval is displayed alongside its example, highest confidence first. Multiple missing stations retain separate review evidence; this presentation never confirms or judges posture correctness.

## 2026-10-03 Prayer action model integration

- Recorded real mode uses the bundled 33-landmark / 166-feature three-seed CPU TorchScript predictor in `app/analysis/prayer_action_predictor.py`.
- Opening takbir and terminal right/left salam are explicit backend report stations; original local training is unchanged.
- `PRAYER_MODEL_BUNDLE_DIR` selects weights; Weights live under `backend/models/prayer_action`; Docker copies them into the image. Missing weights fail without mock fallback.
- Actual runtime and accuracy verification are recorded in `docs/REAL_MODEL_INTEGRATION.md`; real-video accuracy remains pending.

## 2026-10-03 Recorded-video movement correction

- Recorded demo now includes final sitting and both salam directions. Transition takbir and seated intervals between salam gestures no longer count as unexpected.
- Added head-down geometry-gated mirrored Sujud recovery, visible straight-leg Ruku gating and seated subclass probability projection. Confidence remains 65% with 500ms stability.
- Supplied 50-second video verified through actual HTTP JPEG pipeline: 200 frames, real mode, 1/1 rakah, all 10 stations DETECTED. Other videos/angles remain pending. 74 backend tests pass.

## Live Prayer Camera Analysis

- Entry: selected prayer's `video_analysis_screen.dart` → `live_analysis_screen.dart`.
- Client/state/transport: `lib/live/live_controller.dart`, `live_client.dart`, conditional camera/socket adapters.
- Web: `web/live_camera.js`; Android: `LiveCameraEncoder.kt` through `iqtadi/live_camera`.
- Backend: `app/analysis/live.py`; shared reports: `jobs.py.build_report` and existing temporal/sequence modules.
- Tests: `backend/tests/test_live_analysis.py`, Flutter `test/live_analysis_test.dart`.
- Readiness gates capture; consent gates transmission; buffered storage ACK/ordered disk queue,
  adaptive capture gate/inference ACK; client `frame_store*.dart` temp files/IndexedDB until ACK,
  async buffered completion/progress polling, explicit bounds without eviction/reconnect,
  explicit end/cancel, private evidence, uncertainty and retention. No video/audio file is recorded.
- Docs/tools: `docs/LIVE_CAMERA.md`, `tools/verify_live_real.py`, `tools/live_smoke_server.py`.
- Android/Web supported; physical live-camera acceptance and native iOS/desktop remain pending.

## Mobile-first visual identity

- Shared emerald/ivory theme and bundled Noto Sans Arabic: `mobile/coaching/lib/ui/app_theme.dart`, `mobile/coaching/assets/fonts/`.
- Original architecture image and scalable arch header: `mobile/coaching/lib/ui/brand_header.dart`, `mobile/coaching/assets/branding/`.
- Home prayer grid and recorded-video consent/processing/report retain existing navigation and backend contracts. Mobile comparison stacks below 540px; web content caps at 880px.
- Visual QA: `mobile/coaching/test/design_render_test.dart`; fixture screenshots are explicitly synthetic, not model acceptance.

## Mosque Companion

- Home card → `mobile/coaching/lib/mosque/screen.dart`; connected origin/mosque/details/matches/inbox/trip flows.
- HTTP/shared demo capability: `client.dart`; labelled coordinate map: `demo_map.dart`; conditional foreground GPS/navigation: `location*.dart`, Android `MosqueLocation.kt`.
- Backend: `app/mosque/api.py` (contracts/demo gate), `domain.py` (matching/privacy/lifecycle), `store.py` (SQLite transactions), `providers.py` (interfaces and synthetic network), `seed.py` (U01–U11).
- Tests: `backend/tests/test_mosque_companion.py`, Flutter `test/mosque_companion_test.dart`. Live local HTTP runner: `backend/tools/verify_mosque_demo.py`.
- Run: `backend/start_mosque_demo.ps1`; instructions, accounts, scenarios, env and limitations: `docs/MOSQUE_COMPANION.md`.
