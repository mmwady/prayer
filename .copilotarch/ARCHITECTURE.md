# Architecture

Flutter prayer routes use `AnalysisService`/`LiveAnalysisService` with local defaults.
`lib/local/` owns inference adapters, serial sessions, raw temporal/sequence ports,
evidence and private history. Web bridges to the same-origin Heavy/ONNX WASM worker;
Android uses `iqtadi/local_inference` CPU tasks/ONNX. The model contract is unchanged.
Only Mosque Companion uses FastAPI. HTTP analysis clients remain injectable compatibility
tools; no default prayer route constructs them. See `docs/LOCAL_TRAINING.md`.

## Preserved Local Training Runtime

The home route is Arabic prayer learning. `PrayerController` uses the conditional
`PoseDetector`, keypoints and skeleton overlay:

```
Activated reference -> calibration overlay/explicit start -> Camera/local video
-> keypoints -> aspect-corrected classifier + reference matcher -> sequence engine
-> Arabic UI
```

- Provider `ChangeNotifier` ownership and Navigator routes are preserved.
- `PrayerDefinition`/`RakahDefinition` centralize counts, six core stations and sittings.
- Five technical poses have no prayer meaning outside current sequence context.
- At least 4 consecutive frames, confidence >= 0.65 and 500 ms persistence are required;
  gaps > 400 ms reset persistence. Unknown/non-finite input never advances.
- Held poses do not re-count. Stable unexpected movement holds the expected station, records
  one retry per episode and classifies obvious skip/repetition.
- The controller handles source errors and a no-frame watchdog, and releases detector
  subscriptions/resources when leaving. A stopped session is distinct from completion.
- Session snapshots are immutable and in memory. Core movement totals and additional sittings
  are separate; no religious assessment fields exist.
- Content is static in `PrayerContent` with an independent version; human review pending.
- The separate geometry trainer uses ML Kit on mobile; web shares actual Heavy MediaPipe
  landmarks from the local bridge. All model/WASM assets are same-origin. Desktop real
  observation is unsupported; labelled simulation uses synthetic geometry.
- The geometry trainer loads optional local reference JSON and static local Arabic cues; it never
  uploads video and never stores camera media.

## Prayer Guidance (advisory, never on the critical path)

Current default: `PrayerController -> LocalPrayerGuidance -> static Arabic content`.
The network provider below is retained only for explicit compatibility injection;
default prayer screens create no HTTP guidance source.

```
PrayerController (discrete event) -> PrayerGuidanceClient -> POST /api/v1/prayer-guidance
-> DeepSeek deepseek-flash -> one Arabic sentence -> UI card
```

- `PrayerController` takes an optional `guidance:` source. When it is null the controller
  performs **zero** network I/O — this is the default in tests.
- A request is issued only on a discrete transition: session start, retry episode,
  low-confidence episode, session completion, or explicit stop. Never per frame.
- Requests are deduped by `(event, station, rakah)`; held postures do not re-request.
- The payload is structured facts only: prayer, station, event, rakah, station index/total,
  retry count, completed core movements. No pixels, keypoints, frames or identity.
- The route always answers HTTP 200 with `{text, model, degraded}`. Missing key, timeout,
  provider error, empty reply or the `PRAYER_GUIDANCE_ENABLED=false` kill switch all return
  bundled static Arabic text with `model: "static"` and `degraded: true`.
- The prompt forbids religious rulings, fatwas, and any judgement about validity or acceptance
  of the prayer, and forbids requesting personal data.
- Results are memoised in-process, keyed by `(prayer, station, event)`, bounded to 256 entries.
- Thinking mode is disabled by default. `deepseek-flash` enables thinking at effort=high by
  default; reasoning tokens would consume the whole `max_tokens` budget and can leave `content`
  empty. Thinking also makes `temperature` a no-op.

## Prayer Reference Authoring (backend)

- `/admin/prayer` is an Arabic frame/segment editor.
- `app/admin/prayer_references.py` handles MP4 upload and per-frame MediaPipe extraction;
  imports vision dependencies lazily and runs synchronous handlers in FastAPI's threadpool.
- Keeps every decoded frame index/time, including missing-pose observations. One process
  serializes extraction and reference writes. Limit: 200 MB, 18000 decoded frames.
- Operator labels six ordered, nonoverlapping station segments and representative frames,
  excludes bad detections, saves drafts, and explicitly activates a reviewed snapshot.
- Schema-2 activation requires three usable 2D/3D frames per station, a usable representative
  and full-body standing landmarks for calibration.
- Stores media/drafts under `backend/data/prayer_references/`; `active.json` is atomically
  replaced. Later draft edits do not mutate the activated revision.
- `/api/v1/prayer-reference` serves relative/torso-scaled coordinates, angles, observed ranges
  and camera-view metadata. Observed ranges are not calibrated acceptance bounds.
- The authoring upload is an intentional operator-supplied reference video; user prayer
  recordings use the separate consented analysis-job API, not reference authoring.

## Backend Layers

| Layer | Module | Responsibility |
|---|---|---|
| Transport | `main.py` | App factory, CORS, `/healthz`, router registration |
| Config | `config.py` | Typed env settings behind cached `get_settings()` |
| Guidance | `prayer/guidance.py` | Prompt assembly, guardrails, fallback, memoisation, route |
| Generation | `llm/deepseek_client.py` | Async chat completion via the OpenAI-compatible client |
| Authoring | `admin/prayer_references.py` | Extraction, annotation, drafts, activation, delivery |

## Storage and Data

- Prayer runtime/job state is in-process. Mosque Companion demo sessions use SQLite (see the feature section below).
- Reference media/drafts/`active.json` are JSON + images on disk under
  `backend/data/prayer_references/`.
- Guidance memoisation is process-local and bounded; nothing is persisted.

## External Integrations

- LLM: DeepSeek via any OpenAI-compatible Chat Completions endpoint (`DEEPSEEK_BASE_URL`,
  `DEEPSEEK_MODEL`). Only `deepseek-flash` and `deepseek-v4-pro` are valid model names.
- Web pose: same-origin Heavy MediaPipe Tasks through `web/mediapipe_wrapper.js` and the shared local bridge; no CDN runtime dependency.
- Mobile pose: Google ML Kit, on-device.
- Reference extraction: OpenCV + MediaPipe.

## Deployment Topology

- The Cloudflare gateway forwards `/api/v1/mosque-demo/` including browser preflight to the existing app. `MOSQUE_DEMO_ENABLED` and demo bearer-session authorization remain enforced by the feature API; operator routes remain blocked.

- `backend/start_cloudflare.ps1` starts the existing app through `tools/tunnel_gateway.py` and a temporary Cloudflare HTTPS tunnel. Only client API routes and health are public; admin routes return 404. Stop the normal backend first; the gateway preserves the single-process job lifecycle. See `docs/CLOUDFLARE_TESTING.md`.
- `docker-compose.yml` publishes the backend on the configured `PORT` (default 8000) with a
  `/healthz` healthcheck, and loads settings from `backend/.env`.
- The Flutter client is never containerized; devices reach the host over the LAN.
- Single-process assumption: the guidance client singleton and memoisation cache are per-process.

## Security Boundaries

- Client code holds no backend secrets. `Env.backendUrl` configures only default Mosque Companion requests; its drawer validates root HTTP(S) URLs. Prayer routes use local service adapters.
- Admin endpoints filter reference ids to 32 hex characters. `/admin*` is loopback-only
  without a configured token; with `PRAYER_ADMIN_TOKEN` every request needs that bearer header.
- CORS is permissive (`allow_origins=["*"]`) and OpenAPI docs are exposed only when
  `LOG_LEVEL=DEBUG`.

## Architecture Invariants

- The Web-only local recognizer is an additional privacy boundary: camera/image → local RGB
  preprocessing → MediaPipe Tasks worker → float32 features → three ONNX/WASM classifiers →
  per-model softmax probability mean → local conservative sequence report. No user image,
  landmark, features or report request crosses to a backend. CPU/WASM initialization fallback
  stays on-device and is visible. No browser report judges prayer validity. The older backend
  recorded/live modes retain their explicit consent behavior; they are separate experiences.

- Default prayer videos, images, landmarks and features stay on-device. Explicitly injected legacy HTTP clients retain their old consent gate for compatibility tests.
  Per-job bearer ownership guards upload, polling, reports, evidence and deletion; no identity inference.
- Flutter recorded/live station decisions use the shared Dart port of the Python engine.
  Raw alignment remains conservative; independent opt-in normalization/Ruku/seated
  corrections preserve raw predictions and alignment, disclose their effects and
  cannot erase the raw report's review requirement. Standalone browser JS remains raw.
  The preserved local trainer keeps its own local engine and never supplies new-mode results.
- Guidance is advisory only and must degrade to static text, never block or mutate a session.
- No religious validity/acceptance score, identity inference or video/audio recording in prayer sessions.
  Live-camera sampled JPEGs leave the device only after explicit consent/start, with job capability ownership.
- Simulation must remain explicitly labelled and cannot masquerade as camera evidence.
- Station/rakah rules belong in domain configuration, never UI widgets.
- Dart guidance vocabularies (`wireStation`, `wirePrayer`) must stay in lockstep with the
  literals in `backend/app/prayer/guidance.py`.
- The six core station ids in `prayer/guidance.py` must stay identical to
  `admin/prayer_references.py`'s `STATIONS`; a test enforces this.
- Backend file paths are relative to the process CWD, so uvicorn must be launched from `backend/`.
- Flutter platform code uses conditional detector/video-source exports; `dart:html` and
  `dart:io` must not be imported unconditionally into shared code.

## Recorded Video Analysis

- `app/analysis/contracts.py`: strict schema-1.0 reports, 32 opaque ordered keypoint slots,
  confidence/null conventions, result enums. `domain.py` separates physical postures from stations.
- `inference.py`: independent extractor/classifier Protocols and explicit fixture-based mock.
  Real adapters raise MODEL_NOT_CONFIGURED; no fallback. Model framework/order remain unspecified.
- `temporal.py`: recorded-video observations need one detected frame / no minimum duration /
  .65 confidence by default, per user request. Low-confidence/missing observations stay uncertain;
  consecutive same-pose observations still form one event; gaps over 1000ms split runs.
  Station assignment remains a separate sequence decision. Local training is unchanged.
- `sequence.py`: raw mode retains all-optimal-path alignment. With normalization enabled,
  row-bounded temporal matching maximizes observed station coverage, then frame confidence,
  leaving skipped stations unconfirmed. Return to standing after floor and seated observations
  bounds the next row; floor/salam labels alone cannot advance a row. Matching never moves
  backwards. Same-pose fragments are grouped
  using peak frame confidence/image/time; low-confidence candidate postures can separate episodes
  but do not confirm stations. Unmatched movements remain in temporal review sections.
  Only sitting between the last right salam preceding terminal left salam is filtered;
  earlier false directional labels do not erase subsequent floor/sitting evidence.
  Opt-in `PRAYER_RAKAH_TRANSITION_ANCHORS` uses a witnessed standing/ruku/standing triplet
  after floor observations to anchor subsequent rows in partial recordings. Missing floor
    stations remain unconfirmed; forward normalized mode supersedes this alignment heuristic.
- `jobs.py`: lifespan-owned bounded queue/fixed workers, in-memory IDs/tokens, temporary JPEGs,
  progress, cancellation, one-hour default retention and crashed-run lease cleanup.
- `api.py`: create / frames / complete / poll / report / evidence / delete under
  `/api/v1/prayer-analyses`, plus public `/config`. Every job operation requires its bearer token.
- `security.py`: body cap before JSON parse, no-store job responses, loopback/token admin boundary.
  JPEG dimensions/format/bytes, unique IDs and strictly increasing time/index validated atomically.
- Flutter `lib/video/` owns selection, extraction, HTTP/state/polling; `video_analysis_screen.dart`
  renders reports and authenticated image bytes. No local classification/progression in this mode.
- Android 8.1+ native document picker and persistent forward MediaExtractor/MediaCodec decoder;
  selected frames use GPU scaling, closest timestamps and rotation. Retriever remains metadata/
  sticky compatibility fallback (including HDR). Retry/size changes reset the decoder. Web uses
  local-file seek/canvas; other platforms reject extraction. No entire video upload. Synthetic
  native geometry/lifecycle/speed verified on Samsung M52; other devices/real-video accuracy pending.
- Single uvicorn instance. Jobs cannot survive restart; fresh run storage is isolated. Successful
  jobs retain only representative frames. No static image serving, LLM calls or TTS.

## Live camera analysis (2026-10-04)

- `analysis/live.py` adds consented `/prayer-analyses/live` creation, `/{id}/live` WS,
  `/{id}/live/complete` finalization. Existing private status/report/evidence/delete routes are shared.
- A dedicated single-thread executor per live session owns model creation/prediction/close;
  ready is sent only after model load. Buffered uploads use a short storage lock while
  a separate ordered task consumes disk references; release waits for active inference/finalization.
  At most `analysis_workers` live sessions run; recorded workers remain independently bounded.
- Initial WS message carries the bearer token, never URL parameters. Binary header+JPEG packets
  have strict limits and increasing timestamps/indexes; buffered ACK follows disk save,
  adaptive ACK follows inference. Identical retries
  do not duplicate storage or observations. Single-socket ownership survives disconnect.
- `JobManager.build_report` shares temporal/sequence/evidence handling between recorded and live
  observations. Leading/trailing blind periods join interior gaps as uncertainty; no online
  religious verdict or automatic prayer end is added. Model switches keep their existing defaults.
- Flutter `lib/live/` offers buffered (default UX) and adaptive modes. Buffered capture saves
  each sampled JPEG to native temp files/Web IndexedDB until storage ACK, with no eviction.
  Adaptive gates capture before encoding while a previous sample is outstanding. Both preserve
  original times and reconnect identical packets. Buffered finish returns 202 and polls status
  until all stored images are analyzed; both share `AnalysisResults`. Frame/storage limits stop
  capture explicitly; local failures retain saved data. No app-restart resume is added.
  Android converts stride-aware YUV to normalized JPEG natively; Web uses consented getUserMedia/canvas.
  No new dependency. Android keep-screen flag / best-effort web wake lock are lifecycle-bound.
- Foreground-only: backgrounding finalizes the available portion; cancel deletes capability-owned data.
  iOS/desktop native capture unsupported. HTTPS/WSS and WebSocket-capable gateway required externally.
  Existing temporary retention, single-process/restart and frame/duration limits apply.
- `analysis_live_buffer_bytes` defaults to 480MB/session; conservative client reservations
  prevent unbounded queues. Frame logs expose storage/processing latency and backlog, without images/tokens.
- Suspected observations retain optional candidate pose, exact representative-frame confidence/time,
  and private evidence, including low-confidence/short runs and ambiguous or unexpected events.
  Flutter displays these separately as possible movements; confirmation and alignment thresholds
  are unchanged. No-body/gap events have no invented candidate or image. Evidence shares the
  existing bearer ownership, retention and deletion lifecycle.
  Review events carry temporal rakah/next-station placement metadata. Flutter inserts collapsed
  review sections at those positions inside each rakah; events without temporal anchors stay
  in a separate collapsed section. Placement does not confirm a station or rakah.
- HTTPS, stronger authentication, creation rate limits and restricted CORS required externally.
  Admin with a configured token needs an authenticated gateway/header; no default proxy exposure.
- Details: `docs/VIDEO_ANALYSIS.md`, `docs/REAL_MODEL_INTEGRATION.md`.

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

## Mosque Companion demo (2026-10-04)

- `app/mosque/` adds the isolated `/api/v1/mosque-demo` API. Enabled only by `MOSQUE_DEMO_ENABLED=true`; no production accounts or external notifications.
- SQLite persists per-capability demo sessions. `BEGIN IMMEDIATE` serializes seat holds; session tokens are hashed at rest. Expiry/cancellation exclude inactive reservations, so capacity is released once without counter increments.
- Adult fictional personas, stored assistance approval, demo family delegation, fixed Asia/Riyadh Friday clock, synthetic rectilinear route provider, deterministic eligibility/scoring, bilateral confirmation, independent return, and actor-scoped projections are implemented.
- Flutter `lib/mosque/` uses existing HTTP, Navigator, theme and SharedPreferences. Demo persona switching retains session state; foreground GPS on Web/Android is optional and never saves a home automatically. No live-location sharing.
- Precise origins/notes/public meeting coordinates are omitted for invited providers until bilateral confirmation. Public trips never return provider origins. No coordinates are logged or sent to an LLM.
- Map display/route geometry and times are explicitly synthetic. Source-verified centers are independent from unverified proposed meeting points; entrance/dropoff remain null.
- Replaceable `Clock`, `MosqueProvider`, `RouteProvider`, `Notifications` and Flutter `LocationService`; matching configuration is centralized in `MatchConfig`. Existing prayer AI is not used by this feature.
- Production authentication, real routing/entrances, approved helper identity and distributed operation remain pending. See `docs/MOSQUE_COMPANION.md`.
