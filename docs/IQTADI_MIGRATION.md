# Iqtadi architecture migration

> **Superseded in part (2026-10-02).** This document records the *first* migration, which
> isolated the sports stack while keeping it in the tree. That stack has since been **deleted**,
> not preserved: the WebSocket coaching endpoint, LangGraph graph, LLM coaching prompts, TTS
> providers, template/rule APIs, admin template dashboard and generator, the Flutter workout
> screen/controller, `FormAnalyzer`, both rep counters, `WsClient`, streaming audio playback and
> the bilingual dictionary are all gone. The backend is now prayer-only, and the guidance route
> (`POST /api/v1/prayer-guidance`, DeepSeek `deepseek-flash`) was added. Where the table below
> says "Preserve" or "Isolate", read it as "was preserved at the time, later deleted" — see
> `.copilotarch/DECISIONS.md` (ADR-016) and `.copilotarch/CHANGELOG.md`.

Inspected the repository inventory, `.copilotarch` and current Flutter/bootstrap,
detectors, keypoint models, analyzers, rep counter, screen/controller flow,
FastAPI schemas, WebSocket, LangGraph nodes, configuration and tests before edits.

| Existing component | Current purpose | Action | Prayer purpose |
|---|---|---|---|
| `main.dart`, Provider, Navigator | Bootstrap, locale, screen state/routes | Modify/reuse | Arabic-first prayer selection and scoped training state |
| `PoseDetector` + conditional providers | ML Kit camera / MediaPipe local video / desktop stub | Reuse | Local keypoints and preview; no backend dependency |
| `Keypoint`, `ArOverlay` | Normalized joints and skeleton rendering | Reuse | Physical posture observation and skeleton panel |
| FormAnalyzer | Sports angles/templates, confidence and consecutive confirmation | Isolate; reuse confirmation concepts (later deleted) | Configurable conservative prayer geometry classifier |
| DtwRepCounter | Exercise phases and repetition completion | Isolate; replace in prayer flow (later deleted) | Context-aware station/rakah sequence engine |
| WorkoutController | Detector → sports analysis → WS/audio | Preserve; adapt orchestration pattern (later deleted) | Prayer controller → classifier → local engine → static feedback |
| Sports templates/rules | Backend-configured exercise matching | Preserve, outside prayer route (later deleted) | Central local prayer definitions and tunable detection thresholds |
| WS / FastAPI / LangGraph / LLM / TTS | Generated sports coaching and summaries | Preserve, disconnected from prayer (later deleted) | Prayer-only FastAPI: reference authoring + Arabic guidance |
| Workout split screen / rep HUD | Skeleton + video, exercise count | Reuse layout pattern; replace HUD | Prayer, rakah, station progress and local summary |
| Default widget test | Stale `MyApp` scaffold | Replace | Arabic picker/demo tests, domain and confidence tests |

No new framework, wire protocol or provider calls. At the time of this migration, sports
modules remained available as legacy infrastructure and home navigation exclusively entered
prayer learning. **They were deleted on 2026-10-02** (see the banner above).

## Model and sequence decisions

Definitions centralize six core stations, intermediate sitting after rakah two
for 3/4-rakah sessions, and final sitting for full prayers. Demo has only six
core stations. Additional sittings count separately from the six core movements:
Dhuhr reports 24/24 core movements and 2/2 additional sittings.
This implements the supplied training sequence, not a doctrinal validity rule.

Technical classification has five poses. Sequence context distinguishes the two
standing and two sujood stations and all sitting meanings. Consecutive confident
frames AND elapsed persistence are required. Unknown, stale/gapped, missing or
non-finite observations cannot advance. Held poses do not advance repeatedly.
Unexpected stable poses leave the expected station unchanged and record one retry
per stable episode. Low-confidence events count episodes, not frames.

Static Arabic movement labels/feedback have an independent content version and
must receive human content review before release. Geometry is a prototype side-view
heuristic, not a trained prayer model or a religious assessment.

## Final verification and changed files

- 25 Flutter tests passed at the time of this migration (the suite now has 46; see
  `.copilotarch/CURRENT_STATE.md`): all configurations, transitions/sittings, confidence,
  gaps, repetition, synthetic geometry, source errors/watchdog, startup disposal,
  Arabic navigation and detector-to-summary demo flow.
- Final web build passed. Browser simulation verified Demo 1/1, 6/6 and Dhuhr
  4/4, 24/24 plus 2/2 additional sittings; no captured console errors.
- JSON/XML platform configuration parsed; `git diff --check` passed.
- No `flutter analyze` run (project rule); user should run `flutter analyze --no-pub`.
- No real-camera/video accuracy, Android/iOS build or external content review claimed.

Added:
- `mobile/coaching/lib/prayer/prayer_definition.dart`
- `mobile/coaching/lib/prayer/prayer_content.dart`
- `mobile/coaching/lib/prayer/prayer_pose_classifier.dart`
- `mobile/coaching/lib/prayer/prayer_sequence_engine.dart`
- `mobile/coaching/lib/prayer/prayer_demo_detector.dart`
- `mobile/coaching/lib/state/prayer_controller.dart`
- `mobile/coaching/lib/screens/prayer_training_screen.dart`
- `mobile/coaching/test/prayer_sequence_test.dart`
- `mobile/coaching/test/prayer_pose_classifier_test.dart`
- `mobile/coaching/test/prayer_controller_test.dart`
- This migration document.

Modified:
- `mobile/coaching/lib/main.dart`, `screens/home_screen.dart`, `state/locale_provider.dart`
- `mobile/coaching/lib/services/pose_detector.dart`, `mobile_pose_detector.dart`,
  `web_video_pose_detector.dart` (cleanup, startup errors and missing-pose handling)
- `mobile/coaching/test/widget_test.dart`
- `mobile/coaching/pubspec.yaml`, `android/app/src/main/AndroidManifest.xml`,
  `ios/Runner/Info.plist`, `web/index.html`, `web/manifest.json` (description, name, camera permission)
- `README.md`, `mobile/coaching/README.md`, all eight `.copilotarch` files.

New domain data: `PrayerType`, `PrayerPose`, `PrayerStation`, `PrayerDefinition`,
`RakahDefinition`, `PoseObservation`, `CompletedStation`, `PrayerSessionState`,
`SessionStatus`, `MovementFeedback`, `PrayerPoseThresholds`.

Run/Demo/per-prayer checks, current limitations and the next validation milestone
are documented in the root `README.md`. Existing backend files were unchanged by this
first migration; the later 2026-10-02 cleanup removed the sports modules and added the
prayer guidance route.
