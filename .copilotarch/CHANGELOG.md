# Changelog

## 2026-10-06: authorized VPS account/email update

- Direct SSH deployed review commit 51efdb6 Web/backend, with data/env snapshot
  rollback and the stable origin. Main/source branches remain unchanged.
- Explicitly approved Gmail SMTP transfer; actual published registration, inbox
  link activation, login/secure-cookie reload and correct profile persistence pass.
- Public six-prayer routes, real 16-frame local video/three-model inference and
  simulated live input/report pass; no prayer media upload. Physical camera pending.

## 2026-10-06: reliable account email

- Schema v4 adds durable account mail intent and private signed Resend receipts.
- Submit after commit; retry frozen links with leases/backoff across restarts.
- SMTP auto SSL/STARTTLS, honest queued/accepted UI, no automatic verification.
- Local Chrome signup/outage/retry/verification/login acceptance passes. Real
  Gmail SMTP received-link activation/login/secure-cookie reload and correct
  account/SELF persistence also pass on an isolated HTTPS host; live Resend remains
  unverified. Prayer pipeline and main release gate unchanged.
- Final account suites 62 pass, Flutter 153 pass, Web/Android build, v4 migration
  and protected model hashes pass; inherited analyzer/backend/lint/type gates remain.

## 2026-10-06: Wady / Ezz semantic integration

- Retained Wady offline prayer pipeline and Ezz complete auth/family/mosque APIs;
  adapted nullable scalar coverage, profile progress, rankings and navigation.
- Additive schema v3 safely upgrades either source branch; original rows and
  sessions survive. Pinned inference bytes and packaged models match Wady.
- Flutter 151 tests, Web/Android builds pass. Main remains unchanged because
  inherited backend boundary tests, lint and type checks fail; see integration report.

## 2026-10-06: movement completion score

- Shared video/live results show observed station coverage; local history/export and
  paired scalar sync retain detected/expected counts and percentage.
- Additive accounts schema v2 preserves old rows/queue payloads. Guardian daily/week
  percentages use best attempt per prayer/day; coverage breaks equal-point ranks.
- Coverage preserves raw decisions and review states; no posture/validity verdict.

## 2026-10-05: manual VPS deployment workflow

- Added Run workflow for web/backend/both on main with strict SSH host verification.
- Web hash preflight/atomic activation; isolated backend health preflight and stopped-container
  data snapshots; previous web/image/data rollback on failed public smoke checks.
- Three isolated deployment regressions pass; Actions syntax passes actionlint.
- Preserved exact model JSON bytes across Windows/Linux Git checkouts.

## 2026-10-05: hosted Web model preparation

- Stable OVH HTTPS with automatic renewal; temporary tunnel disabled.
- Video selection no longer waits for model initialization. Added per-file download
  percentage/bytes, separate preparation state and explicit retry.
- Worker initialization has no two-minute inference deadline; active downloads no
  longer restart in the main-thread fallback. Asset hashes and inference rules preserved.
- 30 Flutter and seven JS tests passed; public real-video/simulated-camera acceptance
  passed with worker inference and one pose-model download.

## 2026-10-05: actual phone report follow-up

- Exported current Samsung M52 report and verified installed APK hash: older
  performance release, 3/16 stations and 58 unexpected events.
- Replayed full 256-frame video with quality settings. Found premature floor
  Standing rakah split and early false Salam cutoff; fixed optional normalization
  in shared Dart and Python paths. Actual-phone events now have a regression test.
- Fixed native method-channel busy-release/reply ordering after a physical
  `LOCAL_INFERENCE_BUSY` failure. No model, image or confidence changes.
- 42 focused Flutter and 37 backend video tests pass; analyzer has six existing
  infos and no errors/warnings. Physical replay evidence is kept separately.

## 2026-10-05: local report quality options

- Ported configured Python sequence normalization and Ruku geometry gate into the
  shared Flutter Dart report path; independently optional seated projection remains
  experimental. Default raw behavior is preserved; a visible recommended preset
  enables normalization and Ruku gating only.
- Retained original individual/ensemble probabilities, raw station alignment,
  correction reasons, options snapshot, export/history and raw uncertainty review.
- Both real user videos at 4 fps (457 frames) pass all eight settings combinations
  against Python station/event assignment. 131 Flutter tests pass; analyzer has
  no errors/warnings and six existing infos. Physical full-video acceptance remains
  separate from measured-result report parity.

## 2026-10-05: native performance and physical model parity

- Reduced storage/codec/evidence overhead without changing models, preprocessing,
  class ordering, probability averaging or three-stable-match capture.
- Fixed actual release R8 failures in MediaPipe/ONNX JNI and reflection boundaries.
- Samsung M52: 100/100 exact CPU feature/prediction/evidence matches. Full native
  mean 1.284s debug -> 0.546s optimized release; per-change speed attribution unverified.
- GPU was 15.35% faster but changed 9 decisions; shipping remains CPU. 111 Flutter
  and 6 Kotlin tests pass. Actual device limits are in `docs/ANDROID_LOCAL_PERFORMANCE.md`.

## 2026-10-05: local training migration

- Existing six prayer cards now analyze videos/live on-device through local services.
- Added Android Heavy/ONNX CPU channel and pixel/feature/native report parity tests.
- Added local evidence/history/export/delete, references/cues, version invalidation,
  atomic offline app caching and explicit update/readiness UI; backend settings move
  to Mosque Companion. Legacy backend modules remain for compatibility.
- See `docs/LOCAL_TRAINING_ACCEPTANCE.md` for actual test results and device limits.

## 2026-10-04 Browser inference

- Added a Web-only local image/photo/live pipeline beside existing backend experiences.
- Preserved float32 preprocessing and three-model probability averaging; validated ONNX export,
  versioned complete result schemas, worker fallback, local conservative sequence reports.
- Preserved actual MediaPipe protobuf presence during JS conversion; no model/graph retraining.
- Mathematical contract, static deployment and measured parity are documented under `docs/BROWSER_*`.
- Final 2026-10-05 acceptance: Chrome/Edge each match Python on 200 supplied-video frames;
  263 identical-landmark cases, 303 feature vectors/model, local live/privacy and Flutter entry pass.
  Physical mobile/Safari remain unverified; Firefox/WebKit deferred at user's request.

Reverse chronological. Records project-level changes, not memory-file edits.

## 2026-10-04

- Added UX-selectable precise buffering and adaptive fast live-camera modes. Precise mode ACKs
  validated disk saves independently of ordered inference and finishes asynchronously; pending
  client JPEGs use temporary files/IndexedDB until ACK. Fast mode gates sampling before encoding.
  Explicit storage/frame limits replace oldest-frame eviction; progress and timing distinguish backlog.
  141 backend / 75 Flutter tests pass; browser slow-mock transport kept all 32 precise frames
  with backlog 23, while adaptive captured 8 without backlog. Model accuracy is not established by this QA.

- Added consented Android/Web live prayer camera alongside recorded upload: binary JPEG WebSocket,
  model readiness before capture, ordered inference/ACK and idempotent reconnect, bounded buffering,
  explicit finish/cancel, lifecycle release and shared private reports. Blind gaps stay uncertain.
  136 backend / 71 Flutter tests pass; analyzer retains six existing infos; Web/release APK built.
  Browser synthetic camera verified 82 frames, forced reconnect, report and deletion; actual model
  no-body smoke verified eight frames. Physical camera/prayer accuracy and native iOS/desktop remain pending.

- Android recorded-video sampling now decodes forward once with MediaExtractor/MediaCodec and
  GPU-scaled selected frames; preserves channel/JPEG/timestamp/upload contracts and retriever fallback.
  Seven synthetic codec/orientation cases plus decoder and actual bridge lifecycle passed on Samsung
  M52. 1080p test extraction: 39.649s retriever -> 2.681s sequential. 61 Flutter tests pass; analyzer
  retains six existing infos. Other devices and real-video ML accuracy remain unverified.

## 2026-10-03

- Added Arabic branded home drawer with validated, persisted test backend URL and reset. Added temporary Cloudflare launcher and public API gateway without changing backend handlers/model settings. Public health/config verified 200, admin 404; 102 backend tests and 60 Flutter tests plus mobile layout check pass. Analyzer retains six existing infos.
- Removed the forced CPU CanvasKit bootstrap option after a real browser comparison showed it hides decoded asset and memory images without load errors. Normal rendering displays the same images, including the rounded high-quality evidence widget.
- Real analysis now persists original-resolution skeleton overlays on report evidence; coordinates undo detection padding/rotation, unreliable joints are omitted, and Flutter previews are enlarged. Verified 12 real frames visually, 48-frame HTTP run with 8 annotated evidence images, 100 backend tests and 10 Flutter report tests. Analyzer retains six existing infos.
- Added primary recorded-video analysis: consented client JPEG sampling, managed private backend jobs,
  replaceable 32-keypoint/pose adapters, deterministic labelled mock, temporal events and conservative
  backend per-rakah reports/evidence. Real models remain unconfigured.
- Superseded global no-upload/local-only ownership for this mode; preserved isolated local training.
- Added Android/web extraction, Arabic report UI, bounded transport/retention/cancellation and admin
  loopback/token protection, plus model integration and repeatable synthetic demo documentation.

## 2026-10-02

- Removed the sports product entirely. Backend deleted: `graph/`, `tts/`, `websocket/`,
  `session/`, `api/`, `schemas.py`, the admin template dashboard (`admin/router.py`,
  `admin/index.html`), `templates/generate_template.py`, `templates/` and
  `templates`/`exercise_rules`/`videos` data, plus the graph and wire-contract tests. Flutter
  deleted: the workout screen/controller, `FormAnalyzer`, both rep counters, `WsClient`,
  streaming audio playback, the rep-counter widget, the sports models and the bilingual
  translation dictionary.
- Backend is now prayer-only: `/healthz`, the reference authoring/editor routes, the active
  reference API, and the new guidance routes.
- Added Arabic prayer guidance: `GET`/`POST /api/v1/prayer-guidance` generating one short
  Arabic sentence with DeepSeek `deepseek-flash`. Advisory only, always HTTP 200, static Arabic
  fallback with `degraded: true` on any failure, in-process memoisation bounded to 256 entries,
  and prompt guardrails against religious rulings.
- Disabled DeepSeek thinking mode for guidance. `deepseek-flash` defaults to effort=high
  reasoning, which consumes the `max_tokens` budget and can return empty `content`.
- Retargeted the model from the retired `deepseek-chat` to `deepseek-flash`; the API now accepts
  only `deepseek-flash` and `deepseek-v4-pro`.
- Fixed configuration drift: `.env.example` and the root `.env` documented `QWEN_*` names that
  `Settings` silently ignored. All variables are now `DEEPSEEK_*`/`PRAYER_GUIDANCE_ENABLED`, and
  `docker-compose.yml` loads `backend/.env` so dev and Docker share one secrets file.
- Added a Flutter guidance client with an injectable `PrayerGuidanceSource`; `PrayerController`
  requests a cue only on discrete events and dedupes by `(event, station, rakah)`. Simulation
  runs without guidance.
- Dropped now-unused dependencies: `just_audio`, `web_socket_channel` (Flutter);
  `langgraph`, `langchain-core`, `edge-tts` and the explicit `websockets` pin (backend).
- Tests: 23 backend tests pass; Flutter suite covers the new guidance client and controller hook.
- UI/UX pass over every screen: added `lib/ui/app_theme.dart` (semantic color/spacing/radius tokens plus
  the Material 3 dark theme used by `main.dart`) and `lib/ui/ui_kit.dart` (shared card, section header,
  status banner, pill, metric tile, summary line and step-tracker widgets).
- Rebuilt `home_screen.dart` (hero card, icon prayer list, tappable cards, help bottom sheet) and
  `prayer_training_screen.dart` (setup with simulation offered first, calibration status banner +
  labelled preview, live session header/metrics/station tracker, summary stat card). Simulation-only
  and no-validity-wording behaviour is unchanged; all test-asserted Arabic strings were preserved.
- `prayer_calibration_preview.dart` now frames the viewport by calibration state and shows a
  "waiting for a body" pill while no keypoints are tracked.
- Replaced the last English placeholder copy shown inside the preview panels
  (`Camera is starting...`, `No live video source`, `Load a video to show preview`) with Arabic.

## 2026-10-01

- Added backend prayer-reference video upload and Arabic frame/segment review,
  persisted drafts, independent activation and active-reference delivery API.
- Adapted home flow to Iqtadi Arabic RTL prayer movement learning.
- Added central prayer/rakah definitions, five-pose local classifier, stable contextual
  station engine, static versioned feedback, progress and local summaries.
- Added explicitly labelled simulation, camera permissions, and detector cleanup/error handling.
- Added schema-2 estimated 3D reference extraction, mobile reference loading/matching,
  pre-prayer calibration overlay and optional floor framing probe.

## 2026-09-30

- Bootstrapped `.copilotarch/` architecture memory.

## 2026-06-11

- Initial sports release: FastAPI WebSocket + LangGraph + LLM + pluggable TTS, the Flutter
  edge app, the admin template pipeline and Docker packaging. (Removed 2026-10-02.)


## 2026-10-03 Prayer action model integration

- Recorded real mode uses the bundled 33-landmark / 166-feature three-seed CPU TorchScript predictor in `app/analysis/prayer_action_predictor.py`.
- Opening takbir and terminal right/left salam are explicit backend report stations; original local training is unchanged.
- `PRAYER_MODEL_BUNDLE_DIR` selects weights; Weights live under `backend/models/prayer_action`; Docker copies them into the image. Missing weights fail without mock fallback.
- Actual runtime and accuracy verification are recorded in `docs/REAL_MODEL_INTEGRATION.md`; real-video accuracy remains pending.

## 2026-10-03 Recorded-video movement correction

- Recorded demo now includes final sitting and both salam directions. Transition takbir and seated intervals between salam gestures no longer count as unexpected.
- Added head-down geometry-gated mirrored Sujud recovery, visible straight-leg Ruku gating and seated subclass probability projection. Confidence remains 65% with 500ms stability.
- Supplied 50-second video verified through actual HTTP JPEG pipeline: 200 frames, real mode, 1/1 rakah, all 10 stations DETECTED. Other videos/angles remain pending. 74 backend tests pass.

## 2026-10-03 Experimental correction switches

- Four independent `PRAYER_*` switches control mirrored Sujud recovery, Ruku geometry, seated probability projection and sequence normalization. All default false; local configuration is false.
- Raw model output and strict conservative sequence are the default. Earlier supplied-video success used opt-in corrections. Demo terminal stations remain configured. 82 tests pass.

## 2026-10-04

- Added Mosque Companion as an independent Flutter/FastAPI feature preserving existing prayer flows, with transactional SQLite demo sessions, actor-scoped privacy, deterministic route/preference matching and independent outbound/return commitments.
- Added U01–U11 seed, fixed Riyadh clock and committee controls; live browser walking/elder flows, 119 backend/65 Flutter tests and Web/Android builds verified. No production identity or external routing/notifications implied.
