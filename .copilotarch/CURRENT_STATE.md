# Current Project State

## Status

2026-10-06 Arabic / English: Arabic is the default; the home language menu switches
the whole Flutter presentation between RTL and LTR and remembers the choice on
the device. Presentation copy and SDK controls are localized; inference, prayer
rules, stored reports, API wire values and account state are unchanged.
Verification: 149 Flutter tests pass with `--concurrency=1`; release Web builds;
Chrome checks cover both languages at 320/390/820px, persistence after reload and
home/teaching/accounts/video/live navigation. Analyzer retains six existing infos.

2026-10-06 movement completion score: shared video/live report and local history/export
store detected/expected station counts and percentage. Paired scalar sync stores
schema-v2 nullable fields; guardian day/week views and leaderboard tie-breaking use
best attempt per prayer/day. Existing uncertainty and points remain independent.
Deployed 2026-10-06 from `wady` commit `b20b441` to the stable OVH host (web/backend).
Public HTTPS scalar score persistence, duplicate retry and guardian leaderboard passed;
schema v2 migration and backend health/dependency checks passed. Synthetic test data removed.
Public Chrome video and simulated-camera score persistence passed; physical camera unverified.

2026-10-05 VPS testing deployment: complete Flutter Release Web served through
public Nginx HTTPS at `vps-c79afd97.vps.ovh.ca` with automatic certificate renewal; the temporary tunnel is disabled. Docker backend uses Python
3.11/CPU Torch and persistent `/srv/iqtadi/shared/data`. Administration is blocked.
Hosted Web defaults to its own origin unless explicitly configured or overridden.
Mosque Companion remains simulated, paid guidance disabled, SMTP unconfigured;
Manual GitHub Actions deployment (web/backend/both, main only) is available; automatic push deployment remains disabled. Operations and verification: `docs/VPS_DEPLOYMENT.md`.
Public Chrome acceptance passed: 16 real video frames, 23 simulated-camera frames,
local reports, API/origin/admin checks; SQLite login session survived container
restart. Four settings tests passed; analyzer has six existing infos. Physical
camera/VPS reboot acceptance remains unverified. Stable-host HTTPS renewal, login
and health checks passed. Video opening is independent of model preparation, with
per-file download progress and retry; initialization no longer uses the inference
deadline. Public video/camera acceptance passed with one pose-model download.

2026-10-05 optional monitoring: backend-owned Argon2id/SMTP guardian accounts,
family/classroom profiles, one-use QR/manual pairing and revocable child sessions
are added under `/api/v1/accounts`. Flutter accounts are optional Provider/Navigator
modules; Web uses HttpOnly same-site cookies, Android secure storage. Only a scalar
post-result adapter in LocalSession feeds a persistent idempotent offline queue.
Standalone browser image reports remain local. Models, MediaPipe, preprocessing,
ensemble and deterministic assessment are unchanged. Domain rules centralize
reviewed timetable windows, positive scoring and all-five-day streaks. Setup and
runtime verification limits are in `docs/ACCOUNTS.md` and
`output/accounts/VERIFICATION.md`; Android build is distinct from physical acceptance.

2026-10-05 actual mobile follow-up: exported Samsung M52 report proved the old
performance APK was reinstalled (SHA `66fbbb...`); it had 3/16 stations and no
quality-options fields. The quality APK initially gave 12/16: transient floor
Standing split a rakah and early false Salam truncated the recording. Optional
normalization now uses the last witnessed left Salam and a standing/ruku/standing
anchor after floor/seated observations. Native busy release precedes delivery of
the method-channel reply, preventing a preview race. Original 256 frame decisions
and probabilities match before/after quality options. 42 focused Flutter tests,
including actual phone events, and 37 video-analysis backend tests pass. Final
physical acceptance is recorded in `output/mobile-current-review.md`.
Final physical replay: same Fajr video, all 256 frames, 16/16 stations and 2/2
rakahs, with 20 unexpected events and `REVIEW_REQUIRED`. This is sequence recovery,
not proof of perfect classifier accuracy. Final installed APK hash starts `4f4e3df7`.

2026-10-05 quality correction: Flutter local video/live sessions expose independent,
default-off sequence normalization, visible-leg Ruku gating and experimental seated
probability projection. The recommended button enables only the first two. Android
and Flutter Web share the Dart assessment/report engine; original three-model
predictions and raw alignment are retained separately from corrections. Options freeze
at session creation. Raw uncertainty still requires review after normalization.
Standalone browser recognizer remains on its original raw JS report path.

All six Flutter prayer cards now use local recorded-video/live inference and reports.
Full individual decisions, deterministic raw sequence assessment, history/export/delete,
reference management and static Arabic cues work without a prayer backend. Mosque
Companion and optional scalar-result monitoring contact the configured server.
Legacy backend modes remain as development tools.
Web uses same-origin worker/WASM and atomic versioned offline app caching; Android bundles
Heavy + three ONNX models in a native CPU executor. Acceptance/device limits are recorded
in `docs/LOCAL_TRAINING_ACCEPTANCE.md`; never claim physical devices from simulated streams.
Detailed earlier entries below are historical, preceding this 2026-10-05 migration.

2026-10-05 physical performance acceptance: Samsung M52/Android 13 native CPU
release passes 100 real-image cases with exactly matching features, three-model
predictions and evidence hashes versus the earlier debug CPU build. Native full
path mean 1283.85 -> 545.66 ms (includes previews; debug-versus-release, sequential
device runs). Deferred selected evidence, bounded RAM adaptive frames, direct codec
conversion, reused ONNX tensor and exact Lanczos coefficient caching preserve math.
GPU experiment changed 9/100 decisions and is rejected. Release R8 JNI/Protobuf/
Flogger/ONNX boundaries are retained. 111 Flutter and 6 Kotlin tests pass. See
`docs/ANDROID_LOCAL_PERFORMANCE.md`; physical camera/SAF and other devices remain
unverified pending explicit acceptance.

## Preserved Local Training (historical verification)

- Arabic-first RTL picker: Fajr 2, Dhuhr 4, Asr 4, Maghrib 3, Isha 4, Demo 1.
- Local five-class geometry classifier and one configured station/rakah engine.
- Confidence threshold, consecutive frames and 500 ms persistence; unknown, missing/stale and
  invalid observations never advance state.
- Six demo/core stations; configured intermediate/final sittings for full prayers.
- Arabic station progress, retry/uncertainty feedback and completion/stopped summaries.
- Reference calibration (framing/view/stability + optional floor probe) before the session starts.
- Explicit synthetic simulation; desktop sports stub cannot supply prayer evidence.
- Reused ML Kit camera / MediaPipe local-video provider contract and skeleton overlay.
- Backend is prayer-only: `/healthz`, `/admin/prayer` + reference routes, `/api/v1/prayer-reference`,
  and the new `/api/v1/prayer-guidance`.
- Guidance endpoint verified for: model success path, missing-key fallback, provider failure,
  empty reply, memoisation, kill switch, request validation, and prompt guardrails.
- Flutter guidance wiring verified for: no-source no-network, discrete-event-only requests,
  one cue per retry episode, completion cue, and a failing source never blocking the session.
- **46 Flutter tests pass** (`flutter test`). **23 backend tests pass** (`pytest`).
- No live frames, provider keys or paid calls are used by the test suites; the guidance tests
  replace the DeepSeek client with a fake.

## Deleted (sports)

Backend: `graph/`, `tts/`, `websocket/`, `session/`, `api/`, `schemas.py`, `admin/router.py`,
`admin/index.html`, `templates/`, `data/templates`, `data/exercise_rules`, `data/videos`,
`tests/test_graph.py`, `tests/test_ws_contract.py`.
Flutter: `screens/workout_screen.dart`, `state/workout_controller.dart`,
`services/{form_analyzer,rep_counter,ws_client,audio_player}.dart`, `widgets/rep_counter.dart`,
`models/{pose_event,coaching_reply}.dart`, `config/translations.dart`.
Dependencies dropped: `just_audio`, `web_socket_channel` (Flutter); `langgraph`,
`langchain-core`, `edge-tts`, explicit `websockets` pin (backend). The legacy coaching
wire protocol is gone. The new prayer-camera WS is isolated (see below).

## 2026-10-04 Live prayer camera

- Added selected-prayer live-camera option alongside recorded upload; Android and Web capture
  sampled consented JPEGs while the prayer runs. Explicit finish reuses the private report UI.
- Model readiness gates capture. UX offers buffered (all sampled JPEGs retained until storage ACK,
  ordered backend disk queue/asynchronous completion) and adaptive (capture gated by inference ACK).
  Reconnect replays identical frames; explicit storage/frame bounds replace eviction. Native temporary
  files/Web IndexedDB hold pending pictures; foreground lifecycle/cancel release resources.
- Backend preserves optional corrections, uncertainty, ownership, retention and no mock fallback.
  No video/audio recording, LLM call or automatic prayer termination is added.
- Earlier baseline: Android release APK and release Web built; 71 Flutter / 136 backend
  tests passed. Analyzer retains six pre-existing infos, no errors/warnings in the new flow.
  Actual bundled models processed eight no-body synthetic images with zero detected stations.
  Synthetic browser camera: 82 frames ACKed/inferred, forced reconnect, report/delete/return, no console errors.
- Mode verification: 141 backend / 75 Flutter tests passed; buffered tests held inference while saving
  60 frames and verified complete ordered drain/replay, late delivery and cancellation. Slow mock
  browser (700ms/frame): precise 32 frames/backlog 23 then complete drain (17s wait), fast 8 frames/
  no backlog (0.38s wait); IndexedDB fidelity/delete and reconnect passed without console errors.
- Pending: physical Android live camera/rotation/network/battery acceptance and real prayer
  accuracy; native iOS/desktop unsupported. Single-process sessions do not survive restart.

## Partially Verified / Pending

- Backend reference authoring: timestamped video frames/keypoints, manual six-station segments,
  representative frames, exclusions, draft persistence and independent activated snapshot.
- `GET /api/v1/prayer-reference` serves normalized samples, angles and observed ranges. Flutter
  downloads schema-2 references; aspect-corrected matching gates the local classifier.
  Observed ranges are not calibrated acceptance bounds.
- Real Android/iOS camera and local prayer-video acceptance testing.
- Side-view classifier threshold calibration against consented local examples.
- Camera orientation/aspect ratio, floor-level occlusion and lighting validation.
- Human review of versioned static Arabic movement content (not yet approved).
- The guidance prompt and model output have **not** been reviewed by a human reviewer of Arabic
  religious content. The prompt forbids rulings, but the feature should be treated as unreviewed.
- Docker changes were not built locally; only the compose file and env wiring were edited.
- Optional local summary persistence, reviewed backend content/version management.

## Next Logical Milestone

Evaluate the integrated prayer-action model on consented videos
and native device orientation/codec behavior before claiming real recognition.

## Notes for the Next Agent

- Only `deepseek-flash` and `deepseek-v4-pro` are valid DeepSeek model names. `deepseek-chat`
  is retired and fails at request time — do not reintroduce it.
- `deepseek-flash` enables thinking mode by default at effort=high. Guidance disables it
  (`DEEPSEEK_THINKING=false`); enabling it requires a much larger `DEEPSEEK_MAX_TOKENS`.
- Env var names must match `Settings` field names exactly. The old `QWEN_*` names were silently
  ignored (`extra="ignore"`); this was the root cause of the container running unconfigured.
- `backend/.env` is the single secrets file; `docker-compose.yml` loads it directly.
- If `DEEPSEEK_API_KEY` is unset or still `changeme` the guidance route returns static text with
  `degraded: true` and HTTP 200 by design.
- The `DEEPSEEK_API_KEY` currently in `backend/.env` was exposed in plain text during a chat
  session and should be rotated.

## Recorded Video MVP

- Prayer/video selection, upload consent, bounded sampled JPEG batches, job polling/cancellation,
  Arabic per-rakah reports, UNCONFIRMED notes and private representative imagery implemented.
- Android native extraction and web extraction implemented; iOS/desktop explicitly unsupported.
- Backend: 56 tests passed including preserved guidance/reference tests, all six prayers,
  ambiguity/spikes/low confidence, ownership, limits, idempotency, cancellation and cleanup.
- Flutter: 54 tests passed (46 preserved + 8 new); analyzer has six pre-existing infos,
  no errors/warnings or findings in new code. Release web build passed.
- Browser end-to-end: actual 26-second H.264 synthetic video → 52 extracted/uploaded frames →
  full Fajr (2/2) and low-confidence Fajr (1/2, ruku UNCONFIRMED) reports. No ML accuracy claim.
- No paid provider calls, camera or real weights used. Synthetic media/screenshots in `docs/demo/`.
- Android debug APK assembled successfully with a 2GB bounded-memory Gradle invocation.
  Initial 8GB heap settings exhausted native memory; no project/global Gradle settings were changed.
  Native sampling/orientation/lifecycle were subsequently verified on Samsung M52
  (2026-10-04); see `docs/ANDROID_VIDEO_EXTRACTION.md`. Other devices remain unverified.
- Job state is in memory, temporary imagery expires, and production authentication/HTTPS remain pending.
- After the host's WebGL shader failure, release CPU fallback rendered report text/layout,
  but embedded-browser evidence images remained blank despite valid JPEGs. Earlier default-renderer
  end-to-end run displayed evidence. Chrome home rendering passed; its extension blocked local
  file upload (file URL access disabled). Native device execution remains pending.

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

## 2026-10-04 Mosque Companion

- Working: request/publish flows, proposed meeting selection, walking/driver matching with synthetic routing, demo guardian/elder roles, actor-filtered API responses, atomic held/final reservations, rejection/timeouts/cancellation, manual outbound and independent return milestones.
- Working: U01–U11 deterministic seed, persisted shared persona session, fixed Riyadh demo clock, reset/advance/failure controls, explicit demo-only isolation with no real notifications or AI calls.
- Validation: 119 backend tests and 65 Flutter tests passed. Web release and Android debug APK built. Analyzer: six existing infos outside new feature, no errors/warnings. Phone layouts at 320/390/820px passed, including denied/weak mock GPS.
- Live browser at 390px: Ahmed→Yusuf request/accept/confirm/arrival/completion; Omar→Mahmoud→Khalid request/accept/confirm/arrival with return still open. No browser console errors/warnings. Final real HTTP smoke also completed the independent return.
- Pending: physical-device acceptance of native GPS permission/accuracy/Maps, iOS/desktop location bridge, real street routes/approved pickup/entrances, production account authentication/helper approval, retention/encryption and distributed deployment. Current feature remains explicitly demonstration-only.
