# Historical local-training documentation

This records the pre-video-analysis architecture. For the current primary flow, see ../README.md and VIDEO_ANALYSIS.md. The no-upload and unrestricted-admin descriptions below are historical and superseded.

# اقتدِ — Iqtadi

**Arabic-first prayer movement learning.** The Flutter app observes physical postures
with on-device pose detection, a deterministic local engine tracks the six movement
stations of each rak'ah, and an optional backend service turns a handful of structured
session facts into one short Arabic guidance sentence.

It does not assess intention, recitation, dhikr, acceptance, religious rulings or
overall prayer validity. Camera frames, keypoints, video and identity never leave the
device.

> **Status:** pre-release prototype. The backend suite passes; real-camera accuracy,
> side-view threshold calibration and human review of the Arabic movement content are
> still pending — see [Current state and limits](#current-state-and-limits).

## Project in 60 seconds

The learner selects a prayer, loads the activated prayer reference from the backend,
starts the camera (Android/iOS) or chooses a local video (web), and follows Arabic
station prompts. Pose detection stays on device. A local classifier produces five
physical pose classes. One sequence engine uses prayer definitions to track six
movement stations per rakah plus configured additional sittings. Low-confidence or
unexpected movements never advance state. An optional advisory guidance request adds
one Arabic sentence per discrete session event; it can never advance or block the
session.

`Camera/local video → PoseDetector → keypoints → PrayerPoseClassifier → PrayerSequenceEngine → PrayerController → Arabic UI/summary`

Standalone simulation (`محاكاة للتجربة — دون كاميرا`) needs no camera and no backend,
and is always labelled as synthetic. There is no WebSocket, no audio/TTS playback, no
video upload and no recording anywhere in the stack.

## Architecture invariants

These constraints are deliberate. Treat them as review gates, not style preferences.

| # | Invariant | Why / how it is held |
|---|---|---|
| 1 | **No media or identity reaches the backend.** Only structured JSON facts — prayer, station, event, rakah, indexes, counters. No frames, keypoints, images, video, audio or personal data. | The guidance request model is a fixed set of enum/number fields; `backend/tests/test_prayer_guidance.py` asserts the exact field set. Uploading a reference MP4 is a separate, explicit operator action. |
| 2 | **Station progression is deterministic and local on device and never waits on the network.** | `PrayerSequenceEngine` owns all transitions and consumes only local pose observations. Guidance calls are fire-and-forget mirrors of state, never inputs to it. |
| 3 | **Guidance is advisory and degrades to static text.** | Every backend failure returns HTTP 200 with bundled Arabic text and `degraded: true`; the Flutter client returns `null` on any failure and the session continues untouched. There is no retry loop and no offline queue — a stale cue is worse than no cue. |
| 4 | **Simulation stays explicitly labelled and cannot masquerade as camera evidence.** | The training screen prints `محاكاة — بيانات اصطناعية` and the summary prints `ملخص محاكاة — ليس رصداً لحركاتك`; simulated sessions are constructed with `guidance: null`, so they never produce guidance text. |
| 5 | **No religious validity or acceptance scoring.** | Nothing in the classifier, engine, UI or prompts rules on the validity or acceptance of a prayer; the guidance system prompt forbids verdicts and fatwas. Sequence support is technical movement tracking, not a doctrinal rule. |
| 6 | **Draft edits never mutate an activated reference.** | Authoring writes to `backend/data/prayer_references/<id>/reference.json`; activation compiles a reviewed snapshot and atomically replaces `active.json`. |

## Core concepts and code map

| Concept | Purpose / ownership | Main location under `mobile/coaching/lib/` |
|---|---|---|
| Prayer definition | Central prayer counts, rakahs and sitting configuration | `prayer/prayer_definition.dart` |
| Physical pose | Standing, ruku, sujood, sitting, unknown; no sequence meaning | `prayer/prayer_pose_classifier.dart` |
| Station | Context distinguishes standing-after-ruku, two sujood and sittings | `prayer/prayer_sequence_engine.dart` |
| Session controller | Owns detector subscription, keypoints, errors, watchdog, engine and guidance requests | `state/prayer_controller.dart` |
| Static content | Versioned Arabic labels and feedback; human review pending | `prayer/prayer_content.dart` |
| Prayer reference | Activated schema-2 recording, matching and 2D/3D samples | `prayer/prayer_reference.dart` |
| Calibration | Pre-session framing, distance, posture and approximate view checks | `prayer/prayer_calibration.dart`, `widgets/prayer_calibration_preview.dart` |
| Floor coverage probe | Optional ruku/sujood framing check; observations never enter the engine | `prayer/prayer_floor_check.dart` |
| Screens | Prayer selection, calibration, progress and local completion/stopped summary | `screens/home_screen.dart`, `screens/prayer_training_screen.dart` |
| UI kit / theme | Semantic colors, spacing scale and the shared cards, banners, pills and step tracker | `ui/app_theme.dart`, `ui/ui_kit.dart` |
| Detector/overlay | Conditional platform pipeline and skeleton rendering | `services/pose_detector_provider.dart`, `services/camera_pose_geometry.dart`, `widgets/ar_overlay.dart` |
| Arabic guidance | Advisory text client and wire-id mappers | `services/prayer_guidance_client.dart` |
| Simulation | Explicit synthetic development/test source | `prayer/prayer_demo_detector.dart` |

Read definitions → engine → classifier → controller → training screen to follow the
flow. The engine owns progression; the detector only observes; static content supplies
feedback; the backend only phrases advisory text. UI widgets do not decide prayer rules.

## Typical flow

Choose Demo → standing is stable → ruku becomes expected → an unclear observation
leaves ruku expected → stable ruku advances to standing-after-ruku → two sujood
separated by sitting complete six stations → local summary reports 1/1 and 6/6.

Full prayers reuse the same engine: Fajr 2, Dhuhr 4, Asr 4, Maghrib 3, Isha 4.
Final sitting is added for each full prayer; 3/4-rakah definitions also include
intermediate sitting after rakah two. Demo ends after the six core stations.

With a real source, the screen first loads the activated reference, then runs
calibration (`ضبط التصوير قبل الصلاة`) until the standing hold is stable, and only then
enables `ابدأ التدريب`. During the session the `إرشاد نصي` card shows one cue for the
session start and then one per retry or low-confidence episode; the completion and stop
cues are shown with the local summary. No cue is ever requested per frame.

## If I want to change...

| Goal | Start here |
|---|---|
| Prayer station configuration | `prayer/prayer_definition.dart` |
| Confidence/stability policy or transition handling | `prayer/prayer_sequence_engine.dart` |
| Geometry thresholds | `PrayerPoseThresholds` in `prayer/prayer_pose_classifier.dart` |
| Reviewed movement labels / feedback | `prayer/prayer_content.dart` |
| Screen layout | `screens/prayer_training_screen.dart` |
| Colors, spacing, shared cards/banners/steppers | `ui/app_theme.dart`, `ui/ui_kit.dart` |
| Camera / local-video inference | `services/pose_detector_provider*.dart`, `services/mobile_pose_detector.dart`, `services/web_video_pose_detector.dart` |
| Pre-session calibration or floor probe | `prayer/prayer_calibration.dart`, `prayer/prayer_floor_check.dart` |
| Reference matching tolerance | `PrayerReferenceMatcher` in `prayer/prayer_reference.dart` |
| Guidance prompt, guardrails or static Arabic fallback | `backend/app/prayer/guidance.py` |
| Guidance request shape, dedupe or UI card | `services/prayer_guidance_client.dart`, `state/prayer_controller.dart` |
| Backend env knobs | `backend/app/config.py`, `.env.example` |

## Run and Demo Rakah

```powershell
cd D:\SofDev\prayer\mobile\coaching
flutter pub get
flutter run
# Physical device on the same network as the backend:
flutter run --dart-define=BACKEND_URL=http://<lan-ip>:8000
```

`Env.backendUrl` comes from `--dart-define=BACKEND_URL=...` and defaults to
`http://127.0.0.1:8000`. Web inference uses the local MediaPipe wrapper under
`mobile/coaching/web/`; mobile inference uses ML Kit. Desktop has no real pose detector
and must use the explicitly labelled simulation.

Select **ركعة تجريبية**. Choose **محاكاة للتجربة — دون كاميرا** for a roughly nine-second
synthetic demo — that path needs no backend. For real input, enter the backend address
in **عنوان backend**, press **تحميل المرجع المفعّل** (camera mode requires an activated
prayer reference served by the backend), then choose a local side-view prayer video on
web or open the camera on mobile. Include the whole body, keep the phone upright and
fixed, and hold each posture for at least half a second.

## Test each prayer

```powershell
cd D:\SofDev\prayer\mobile\coaching
flutter test
flutter build web --no-pub
```

Per project rules, static analysis is for the user to run:

```powershell
flutter analyze --no-pub
```

Test files: `prayer_sequence_test`, `prayer_pose_classifier_test`,
`prayer_controller_test`, `prayer_calibration_test`, `prayer_calibration_widget_test`,
`prayer_guidance_test`, `prayer_guidance_controller_test`, `widget_test`.

Select any prayer and use simulation to exercise every configured rakah and sitting.
Expected core totals: Demo 6, Fajr 12, Maghrib 18, Dhuhr/Asr/Isha 24. Additional
sittings: Demo 0, Fajr 1, all other full prayers 2. The summary reports these
separately. Simulation results are labelled and are not camera evidence.

For real-input checks: follow the sequence, skip standing-after-ruku to check that
progress stalls, return to ruku after standing-after-ruku to check a repeated movement,
and obscure joints to check low-confidence feedback. Restore the expected posture to
recover. End early (`إنهاء التدريب`) to verify a stopped session is not labelled
complete.

## Backend

`backend/` is a small FastAPI app with three route groups and no authentication:

- `/healthz` — liveness probe: `{"status":"ok","guidance_enabled":true}`.
- `/api/v1/prayer-guidance` — the Arabic guidance feature (below).
- `/api/v1/prayer-reference` plus the `/admin/prayer` authoring API (below).

There is no WebSocket, session manager, LangGraph graph, TTS engine, audio pipeline or
exercise-template code left in the repository.

### Arabic prayer guidance API

`app/prayer/guidance.py`. The route turns structured session facts into **one short
Arabic sentence** (max twenty words) advising on the current physical movement.

#### Capability probe

```http
GET /api/v1/prayer-guidance
→ 200 {"enabled": true, "model": "deepseek-flash", "thinking": false}
```

Useful for ops checks and for a client that wants to hide guidance UI when the feature is
switched off. The Flutter app does not call it today — it simply attempts the `POST` and
renders nothing when the request yields no text.

#### Request

`POST /api/v1/prayer-guidance` — structured facts only, never media:

```json
{
  "prayer": "dhuhr",
  "station": "ruku",
  "event": "retry",
  "rakah": 1,
  "station_index": 1,
  "total_stations": 6,
  "retries": 1,
  "core_movements_done": 1
}
```

| Field | Type / allowed values | Notes |
|---|---|---|
| `prayer` | `fajr`, `dhuhr`, `asr`, `maghrib`, `isha`, `demo` | |
| `station` | six core ids `standing`, `ruku`, `standing_after_ruku`, `sujood_first`, `sitting`, `sujood_second` plus `intermediate_sitting`, `final_sitting` | Byte-identical to `STATIONS` in `app/admin/prayer_references.py`; a test enforces that. |
| `event` | `start`, `retry`, `uncertain`, `completed`, `stopped` | Discrete events only — never per frame. |
| `rakah` | int 1–10, default 1 | |
| `station_index` | int 0–200, default 0 | Zero-based position of the current station. |
| `total_stations` | int 1–200, default 1 | Stations in the current rakah. |
| `retries` | int 0–1000, default 0 | Retry episodes so far. |
| `core_movements_done` | int 0–1000, default 0 | Completed core movements. |

Unknown values return `422` from Pydantic validation.

#### Response

```http
POST /api/v1/prayer-guidance
→ 200 {"text": "خذ نفسًا هادئًا وأعد الحركة بتمهّل مع الحفاظ على نفس الوضعية.",
       "model": "deepseek-flash", "degraded": false}
```

| Field | Meaning |
|---|---|
| `text` | One Arabic sentence. |
| `model` | Configured model name, or `static` when the fallback was used. |
| `degraded` | `true` when the text is bundled static content rather than a model reply. |

#### Fallback contract

The client is never blocked and the route never returns an error for an LLM problem.
All of these yield **HTTP 200** with `text` from the bundled `STATIC_FALLBACK` map,
`model: "static"` and `degraded: true`:

- `DEEPSEEK_API_KEY` empty or still `changeme` (`LLMNotConfigured`);
- network failure, DNS error, timeout (`DEEPSEEK_TIMEOUT_S`), quota or any provider 4xx/5xx;
- an empty or whitespace-only model reply;
- the kill switch `PRAYER_GUIDANCE_ENABLED=false` — static text without any network call.

The fallback text is per event and deliberately free of any religious ruling, e.g.
`start`: `ابدأ واقفًا بثبات ودع الكاميرا ترى جسمك كاملًا من الجانب.`

#### Guardrails and cost control

- The system prompt forbids religious rulings, fatwa-style claims, judging the validity
  or acceptance of the prayer, and any request for personal data; it asks for one short
  sentence about the physical posture only.
- Results are memoised in-process, keyed by `(prayer, station, event)`. The cache is
  bounded to 256 entries (cleared when full) and is not persisted; static fallbacks are
  not cached. A multi-worker deployment therefore gets one cache per worker.
- `DEEPSEEK_MAX_TOKENS=160` bounds cost; guidance is not a chat feature.

#### Flutter client wiring

`mobile/coaching/lib/services/prayer_guidance_client.dart` defines `PrayerGuidance`
(`text`, `model`, `degraded`), `PrayerGuidanceRequest`, the injectable
`PrayerGuidanceSource` interface, `PrayerGuidanceClient`, and the `wireStation` /
`wirePrayer` mappers that must stay identical to the backend vocabularies.

`PrayerController` takes an optional `guidance:` source. When it is `null` the
controller performs **zero network I/O** and progression stays entirely local. When a
source is present, the controller requests a cue only on discrete events (session
start, retry episode, low-confidence episode, completion, stop) and dedupes by
`(event, station, rakah)` — never per frame. A request that yields no text clears the
dedupe key so a later event can retry, and the session carries on untouched.

Note that `PrayerGuidanceClient` swallows every transport error and returns `null`, so an
offline device simply shows no guidance card. `PrayerController.guidanceError`
(`تعذر جلب الإرشاد النصي.`) is only set when an injected `PrayerGuidanceSource`
implementation throws — the production client never does. `degraded: true` (static
fallback text) is the visible signal that the model was unreachable.

The training screen renders the `إرشاد نصي` card and, when `degraded` is true, the note
`نص احتياطي — خدمة الإرشاد غير متاحة الآن.` Simulated sessions are constructed with
`guidance: null`, and the training screen only creates a client for real observation.

### Prayer reference authoring API

`app/admin/prayer_references.py` + `app/admin/prayer.html`. This is the only place
video enters the system, and it is an explicit operator flow: upload an MP4, label the
segments, review, then activate.

| Method | Route | Purpose |
|---|---|---|
| `GET` | `/admin/prayer` | Arabic frame/segment editor (HTML/JS). |
| `POST` | `/admin/api/prayer-references` | Upload an MP4 (`name`, `view` ∈ `side_left`, `side_right`, `front`, `oblique_left`, `oblique_right`) and extract per-frame keypoints. |
| `GET` | `/admin/api/prayer-references` | List drafts plus the active id/revision. |
| `GET` | `/admin/api/prayer-references/{id}` | Full draft: frames, keypoints, segments, revision. |
| `GET` | `/admin/api/prayer-references/{id}/frames/{index}` | Decoded JPEG for a frame. |
| `PUT` | `/admin/api/prayer-references/{id}` | Save a draft annotation (six ordered segments). |
| `POST` | `/admin/api/prayer-references/{id}/activate` | Compile the reviewed draft and atomically replace `active.json`. |
| `GET` | `/api/v1/prayer-reference` | Serve the activated schema-2 reference to Flutter (`404` until activation). |

What the flow guarantees:

- Six ordered, non-overlapping station segments plus a representative frame each, with
  optional excluded frames for bad detections; segments must appear in prayer order.
  Station ids: `standing`, `ruku`, `standing_after_ruku`, `sujood_first`, `sitting`,
  `sujood_second`.
- Every decoded frame is stored — including frames where no pose was detected — so image
  indexes stay aligned with source frame indexes.
- Activation requires at least three usable, non-excluded frames and a usable
  representative per station, plus usable 3D (MediaPipe world) evidence and a standing
  representative showing head, torso and both legs.
- Limits: 200 MB per upload and 18000 decoded frames. Vision dependencies
  (`cv2`, `mediapipe`) are imported lazily, so the app starts without them.
- Media and drafts live under `backend/data/prayer_references/`; `active.json` is
  replaced atomically, and later draft edits never mutate the activated revision.
- Observed joint/angle ranges describe the supplied recording. They are not calibrated
  acceptance tolerances.

Full operator notes: [prayer reference authoring](docs/prayer-reference-admin.md).

## How to Run the backend

### Local

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate          # Windows; source .venv/bin/activate elsewhere
pip install -r requirements.txt
cp ../.env.example .env         # then fill DEEPSEEK_API_KEY
uvicorn app.main:app --reload --port 8000
```

Run from `backend/`: `Settings` reads `.env` from the process CWD, so the same file
works for uvicorn and for the container. Without a real `DEEPSEEK_API_KEY` everything
still starts and guidance serves static Arabic text.

Set `LOG_LEVEL=DEBUG` to enable the OpenAPI docs at `/docs`.

### Docker

```bash
# from the repository root
docker compose up --build
```

`docker-compose.yml` loads application settings from `./backend/.env` via `env_file`,
so that file must exist. The compose-level `PORT` comes from the root `.env`
(default `8000`). The healthcheck hits `/healthz`.

### Tests

```bash
cd backend
pytest -v        # 23 tests
```

## Runtime Configuration

All backend behavior is environment-driven through `pydantic-settings`. Variable names
must match the `Settings` field names in `backend/app/config.py` exactly, upper-cased —
there is **no prefix**:

| Variable | Default | Description |
|---|---|---|
| `HOST` | `0.0.0.0` | Bind address inside the container. |
| `PORT` | `8000` | Server port. |
| `LOG_LEVEL` | `INFO` | `DEBUG` \| `INFO` \| `WARNING` \| `ERROR`; `DEBUG` also enables `/docs`. |
| `DEEPSEEK_BASE_URL` | `https://api.deepseek.com` | OpenAI-compatible endpoint (vLLM, Ollama, Together, …). |
| `DEEPSEEK_API_KEY` | `changeme` | Bearer token. Empty or `changeme` is treated as unconfigured and degrades to static text. |
| `DEEPSEEK_MODEL` | `deepseek-flash` | Model name — see the constraint below. |
| `DEEPSEEK_MAX_TOKENS` | `160` | Hard cap per guidance reply. |
| `DEEPSEEK_TEMPERATURE` | `0.5` | Sampling temperature; ignored by the provider while thinking is enabled. |
| `DEEPSEEK_TIMEOUT_S` | `20.0` | Per-request timeout in seconds. |
| `DEEPSEEK_THINKING` | `false` | Keep false for short cues — see the thinking note below. |
| `PRAYER_GUIDANCE_ENABLED` | `true` | Kill switch; `false` serves static Arabic text and never calls the network. |

**Only two model names are valid:** the DeepSeek API accepts exactly `deepseek-flash`
and `deepseek-v4-pro`. The retired alias `deepseek-chat` fails at request time, so it
must never be used as a default or in a deployment `.env`.

**Thinking mode:** `deepseek-flash` enables thinking by default at effort `high`.
Reasoning tokens are billed as output, would consume the whole `DEEPSEEK_MAX_TOKENS`
budget, and can return empty `content` for a one-sentence cue — which the route would
then serve as static text. Guidance therefore disables thinking
(`extra_body.thinking.type = "disabled"`) unless `DEEPSEEK_THINKING=true`. Thinking also
makes `temperature` a no-op.

**Where secrets live:** `backend/.env` is the single place for application settings and
credentials. `docker-compose.yml` loads it via `env_file: ./backend/.env`; the root
`.env` holds the compose-level `PORT` only. `.env.example` is the documented template —
copy it to `backend/.env`.

Flutter configuration is one compile-time constant: `Env.backendUrl` in
`mobile/coaching/lib/config/env.dart`, fed by `--dart-define=BACKEND_URL=...`
(default `http://127.0.0.1:8000`).

## Project Layout

```
├── backend/                          # FastAPI backend: guidance + reference authoring
│   ├── app/
│   │   ├── main.py                   # App factory, CORS, /healthz, router mounts
│   │   ├── config.py                 # pydantic-settings Settings + cached get_settings()
│   │   ├── logging_config.py         # Idempotent logging setup
│   │   ├── admin/
│   │   │   ├── prayer_references.py  # Upload, frame extraction, annotation, activation
│   │   │   └── prayer.html           # Arabic frame/segment editor at /admin/prayer
│   │   ├── llm/
│   │   │   └── deepseek_client.py    # Async OpenAI-compatible client + LLMNotConfigured
│   │   └── prayer/
│   │       └── guidance.py           # Arabic guidance route, prompt, static fallback
│   ├── tests/
│   │   ├── test_prayer_references.py # Authoring API tests (synthetic extraction)
│   │   └── test_prayer_guidance.py   # Guardrails, degraded fallback, memoisation
│   ├── data/prayer_references/       # Generated uploads/drafts/active.json (git-ignored)
│   ├── Dockerfile
│   ├── pyproject.toml
│   ├── requirements.txt
│   └── commands.txt
│
├── mobile/
│   └── coaching/                     # Flutter app (package name kept: `coaching`)
│       ├── pubspec.yaml              # camera, provider, http, google_mlkit_pose_detection, js
│       ├── web/mediapipe_wrapper.js  # Web pose inference
│       └── lib/
│           ├── main.dart             # App bootstrap, dark theme, RTL
│           ├── config/
│           │   └── env.dart          # Env.backendUrl (--dart-define=BACKEND_URL)
│           ├── models/
│           │   └── keypoint.dart     # Keypoint + joint identifiers
│           ├── prayer/
│           │   ├── prayer_calibration.dart
│           │   ├── prayer_content.dart
│           │   ├── prayer_definition.dart
│           │   ├── prayer_demo_detector.dart
│           │   ├── prayer_floor_check.dart
│           │   ├── prayer_pose_classifier.dart
│           │   ├── prayer_reference.dart
│           │   └── prayer_sequence_engine.dart
│           ├── screens/
│           │   ├── home_screen.dart
│           │   └── prayer_training_screen.dart
│           ├── ui/
│           │   ├── app_theme.dart    # Color/spacing tokens + Material 3 theme
│           │   └── ui_kit.dart       # Cards, banners, pills, metric tiles, stepper
│           ├── services/
│           │   ├── camera_pose_geometry.dart
│           │   ├── mobile_pose_detector.dart
│           │   ├── pose_detector.dart
│           │   ├── pose_detector_provider.dart
│           │   ├── pose_detector_provider_mobile.dart
│           │   ├── pose_detector_provider_stub.dart
│           │   ├── pose_detector_provider_web.dart
│           │   ├── prayer_guidance_client.dart
│           │   └── web_video_pose_detector.dart
│           ├── state/
│           │   ├── locale_provider.dart
│           │   └── prayer_controller.dart
│           └── widgets/
│               ├── ar_overlay.dart
│               └── prayer_calibration_preview.dart
│
├── docs/
│   ├── IQTADI_MIGRATION.md           # Historical sports → Iqtadi migration record
│   └── prayer-reference-admin.md     # Operator guide for the authoring flow
│
├── .env.example                      # Backend environment template
├── .env                              # Compose-level PORT only
├── docker-compose.yml                # Backend container + healthcheck
└── README.md
```

`__init__.py` files exist in `backend/app/` and each subpackage. Platform folders
(`android/`, `ios/`, `web/`, `linux/`, `macos/`, `windows/`) are standard Flutter
scaffolding; the deleted sports code left no files behind.

## Current state and limits

- `cd backend && pytest -v` → **23 passed** (guidance fallback/memoisation/guardrails and
  the reference authoring API, with synthetic frame extraction).
- `cd mobile/coaching && flutter test` → **46 passed** at the last recorded run, across
  prayer sequences, pose classification, calibration and its widget flow, controller
  behaviour, guidance client/controller wiring and the demo navigation flow.
  **Flutter tests are not real-camera accuracy evidence.**
- A web build and browser simulation runs for the Demo and Dhuhr summaries were verified
  before the guidance wiring landed; neither has been re-run since. No paid provider calls
  are required to run the test suite.
- Real camera and prayer-video accuracy remain unverified. The classifier is a
  conservative side-view geometry prototype, not a prayer-trained ML model.
- Still pending: real Android/iOS camera acceptance testing, side-view threshold
  calibration against consented local examples, camera orientation/lighting/floor
  occlusion validation, and human review of the static Arabic movement content.
- Camera rotation/aspect-ratio behaviour and low floor-level or occluded postures need
  device acceptance testing. Front views or rotated cameras may remain unknown.
- Repetitions are detected only where sequence context makes them distinguishable.
- Guidance text quality is not reviewed by a religious authority. The prompt guardrails
  reduce, but cannot guarantee, the absence of inappropriate phrasing — always check the
  `degraded` flag and the fallback text in review.
- Sessions and summaries are in memory and disappear when leaving the screen. No
  accounts, recording, analytics persistence, voice playback or summary upload exists.
- The authoring page and API have no authentication. Run them locally; any external
  deployment needs access controls.
- The Docker/compose path is wired to `backend/.env` but has not been built or run in
  this environment.
- MediaPipe may download its public model asset on first use if it is not cached.

Next: collect consented, local side-view validation examples, tune geometry and
confidence thresholds on devices, and review the static movement content before release.

## Related docs

- [Prayer reference authoring guide](docs/prayer-reference-admin.md)
- [Iqtadi migration record](docs/IQTADI_MIGRATION.md) — historical; it describes the
  migration away from the sports system and its original verification dates.

