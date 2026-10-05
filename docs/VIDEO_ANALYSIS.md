# Recorded-video MVP

## Flow and ownership

Flutter prayer catalog → local video picker → explicit upload consent → bounded
JPEG frame batches → FastAPI managed job → independently replaceable keypoint and
pose adapters → temporal events → backend sequence alignment → schema-1.0 Arabic
report → authenticated representative images.

The old local training screen remains accessible through `التجربة المحلية السابقة`.
It is independent and is not called by the new recorded-video flow.

Android 8.1+ uses the system document picker and a persistent `MediaExtractor` /
`MediaCodec` decoder on one executor thread. It reads forward once, selects the
closest sampled frames, and scales only selected frames through a GPU surface.
`MediaMetadataRetriever` remains the metadata reader and compatibility fallback
for unsupported decoders and HDR tone mapping. Web uses a local file/object URL, video seeking and canvas JPEG
encoding. iOS/desktop explicitly report unsupported extraction. No new Flutter
dependency was added. Sampling timestamps are requested positions relative to the
video start, not decode-order numbers. Decoders may return a nearby frame, so they
are not exact presentation-timestamp guarantees.

Device checks, measured extraction timings and reproduction instructions are in
[`ANDROID_VIDEO_EXTRACTION.md`](ANDROID_VIDEO_EXTRACTION.md).

## HTTP contract

Base path: `/api/v1/prayer-analyses`. No token in query strings. Creation returns
a random `access_token` once; all job operations use `Authorization: Bearer <token>`.
Wrong/missing tokens and unknown jobs return the same 404.

| Method | Suffix | Response |
|---|---|---|
| GET | `/config` | Public extraction limits, provider and mock availability |
| POST | empty | 201: `job_id`, `access_token`, status/progress |
| POST | `/{id}/frames` | Accepted batch and uploaded frame count |
| POST | `/{id}/complete` | 202: queues the job; repeated completion is safe |
| GET | `/{id}` | status, uploaded/processed frames, explicit error code |
| GET | `/{id}/report` | schema-1.0 report, or 409 while unavailable |
| GET | `/{id}/evidence/{evidence_id}` | private JPEG bytes, `Cache-Control: no-store` |
| DELETE | `/{id}` | 204: cancel, remove ownership and clean temporary files |

Creation JSON:

```json
{"prayer":"fajr","duration_ms":26000,"sample_fps":2,"upload_consent":true,"scenario":"normal"}
```

`upload_consent` must be true. Scenario must be explicitly selected for mock;
real mode rejects mock scenarios. `normal_fajr`/`normal_dhuhr` must match prayer.

Batch JSON:

```json
{"batch_id":"batch_0","frames":[{"frame_id":"frame_0","timestamp_ms":0,"sequence_index":0,"jpeg_base64":"<JPEG base64>"}]}
```

IDs contain only letters/digits/underscore/hyphen, max 64 characters. Frame IDs
must be unique. Timestamps and sequence indexes must strictly increase, including
across batches. Timestamp must be within declared duration. Repeating the same
batch ID and identical body before finalization is a no-op; different content is
409. An invalid batch commits no images. After finalization all uploads return 409.
Responses serialize typed Pydantic models; see `contracts.py` for exact fields.

Statuses: `CREATED`, `UPLOADING`, `QUEUED`, `PROCESSING`, `COMPLETED`, `FAILED`,
`CANCELLED`. A cancelled/deleted job immediately becomes inaccessible. If a worker
is active, it stops between frames and then removes its files.

## Limits and configuration

All values are typed settings in `backend/app/config.py`, read from `backend/.env`.

| Setting | Default |
|---|---|
| `INFERENCE_PROVIDER` | `mock` |
| `ANALYSIS_ALLOW_MOCK` | `false` (explicit development opt-in required) |
| `FRAME_SAMPLE_FPS` | 2 |
| `ANALYSIS_BATCH_FRAMES` | 8 |
| `ANALYSIS_MAX_FRAME_BYTES` | 200000 (original and normalized JPEG) |
| `ANALYSIS_MAX_DIMENSION` | 960 pixels per side |
| `ANALYSIS_MAX_REQUEST_BYTES` | 2500000 before JSON parsing |
| `ANALYSIS_MAX_FRAMES` | 2400 per job |
| `ANALYSIS_MAX_DURATION_MS` | 1200000 (20 minutes) |
| `ANALYSIS_MAX_JOBS` | 8 including uploaded/completed jobs |
| `ANALYSIS_WORKERS` | 1 |
| `ANALYSIS_RETENTION_SECONDS` | 3600 from job creation |
| `ANALYSIS_STORAGE_DIR` | `data/prayer_analyses` |
| `TEMPORAL_CONFIDENCE` | .65 |
| `TEMPORAL_MIN_OBSERVATIONS` | 2 |
| `TEMPORAL_MIN_DURATION_MS` | 500 |
| `TEMPORAL_MAX_GAP_MS` | 1000 |
| `PRAYER_ADMIN_TOKEN` | empty: admin loopback only |

JPEG is validated, EXIF-transposed and stripped of metadata before storage.
Success retains only frames supporting confirmed stations. No imagery is served
from static directories. Failed/uploading jobs expire too. Approximate maximum
uploaded storage with defaults is 8 × 2400 × 200000 bytes, plus small metadata;
capacity is bounded but a deployment should budget disk appropriately.

FastAPI lifespan owns a bounded queue, fixed workers and retention task. Shutdown
signals cancellation, drains workers and removes the current run directory.
There is no Redis/Celery/database. Job state/tokens are lost on restart. Crashed
run directories are cleaned after their lease expires (max of retention and 60
seconds), on startup or a retention sweep. Fresh runs never delete another live
app's run directory. Use one uvicorn process; multi-process routing is unsupported.

## Temporal and sequence behavior

- Predictions are ordered by timestamp; duplicated/conflicting index order fails.
- A stable event needs at least two confident same-pose observations spanning
  500ms by default. Isolated spikes, missing detections and low confidence become
  uncertain events; they cannot confirm a station.
- Gaps over 1000ms produce explicit uncertain events and split stable runs.
- Consecutive same poses are merged; low-confidence gaps are preserved, not bridged.
- Evidence prefers a high-confidence interior frame, avoiding transitions where possible.
- Backend prayer counts/configuration mirror the existing catalog: Fajr 2,
  Dhuhr/Asr/Isha 4, Maghrib 3, Demo 1. Six core stations; intermediate sitting
  after rakah 2 for 3/4-rakah prayers, final sitting for all except Demo.
- Global longest-subsequence alignment considers **all** optimal assignments.
  A station is `DETECTED` only if a single event/station assignment is mandatory
  across all those alignments. Otherwise it is `UNCONFIRMED` with no evidence.
- This intentionally under-confirms ambiguous partial recordings; it never forces
  an event into a rakah or labels missing detection as a skipped religious duty.
- Unassigned events are reported as ambiguous or out-of-sequence/repeated. These
  alternatives cannot always be distinguished by physical posture alone.
- Every expected station appears in the report. `observed_rakahs` counts rakahs
  with every station confirmed; it is not a count of guessed performed rakahs.
- Overall result is `OBSERVED_COMPLETE` only if all rakahs are confirmed and no
  uncertain/unassigned events remain. Otherwise `REVIEW_REQUIRED`.
- Technical metrics remain separate. No validity score or religious judgment.

## Repeatable mock demonstrations

From `backend/` (Python 3.11 recommended for the existing optional MediaPipe pin):

```powershell
.venv\Scripts\python.exe tools/create_mock_demo.py
$env:INFERENCE_PROVIDER='mock'
$env:ANALYSIS_ALLOW_MOCK='true'
$env:PRAYER_GUIDANCE_ENABLED='false'
.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

The generator needs existing OpenCV/NumPy plus FFmpeg on PATH. It produces a
26-second **H.264 synthetic video**, `docs/demo/fajr_synthetic.mp4`, with no person
and no prayer-recognition claim. Video files are ignored by Git.

In another terminal:

```powershell
cd mobile/coaching
flutter run -d chrome --dart-define=BACKEND_URL=http://127.0.0.1:8000
```

1. Select `صلاة الفجر`, pick the generated file, retain `تسلسل كامل — محاكاة`,
   check the upload-consent checkbox and start. 52 real JPEG frames are extracted
   from the video and uploaded. The synthetic script produces 13 confirmed stations,
   two confirmed rakahs and representative images.
2. Return, choose Fajr and the same file, then `ثقة منخفضة` or `ركوع غير مؤكد`.
   Confirm upload and start. The report requires review, leaves unsupported
   stations unconfirmed and does not invent evidence for them.

Each scripted pose occupies 2 seconds of video time. A normal scenario needs at
least 12s for Demo, 26s Fajr, 40s Maghrib, 52s Dhuhr/Asr/Isha. A longer recording
produces uncertain trailing observations; a shorter one remains incomplete.
Scripts do not inspect arbitrary images. Uploaded images in a mock report are
only illustrative frames linked to scripted events, prominently labelled in UI.

For Android emulator: `BACKEND_URL=http://10.0.2.2:8000`; bind backend to the
appropriate local interface for physical-device testing and use its LAN address.

## Verification and production limits

```powershell
cd backend
.venv\Scripts\python.exe -m pytest -q
cd ../mobile/coaching
flutter analyze --no-pub
flutter test --no-pub
flutter build web --no-pub
flutter build apk --debug --no-pub
```

Flutter tests use deterministic fixtures/mock HTTP and never paid DeepSeek, camera or real
model weights. Native decoding/orientation was separately checked on Samsung M52
with synthetic local videos; actual ML accuracy and other devices need separate
acceptance. Decode timestamps are approximate as documented by
[Android's retriever API](https://developer.android.com/reference/android/media/MediaMetadataRetriever).
No resumable durable jobs, video playback preview, live mode, audio or LLM report
generation are implemented. A browser must support the selected video codec.
If a host's WebGL driver fails compiling CanvasKit shaders (white screen with
shader errors), append `?software=1` to the app URL to use the optional CPU renderer.
This changes rendering only, not frame extraction or analysis.
On this host the fallback displayed report text/layout but evidence images remained
blank in the embedded browser, despite valid stored JPEGs. The earlier default-renderer
run displayed evidence successfully. Chrome home rendering passed; its extension
blocked local file upload because file URL access was disabled. These host/browser
limitations still require acceptance on the intended presentation device.

Before external deployment use HTTPS, production authentication, rate-limit job
creation and restrict CORS. Per-job bearer tokens are a prototype ownership
boundary, not user accounts. With `PRAYER_ADMIN_TOKEN` set, every `/admin*` route
requires that bearer header; the legacy admin page must be behind an authenticated
gateway supplying it. Without a token only loopback admin is allowed; do not expose
that default behind a loopback reverse proxy.

Model integration: [REAL_MODEL_INTEGRATION.md](REAL_MODEL_INTEGRATION.md).

## Implementation file manifest

Created:

- `backend/app/analysis/__init__.py`, `contracts.py`, `domain.py`, `inference.py`,
  `temporal.py`, `sequence.py`, `jobs.py`, `api.py`, `security.py`.
- `backend/tests/test_video_analysis.py`, `backend/tools/create_mock_demo.py`.
- `mobile/coaching/lib/video/analysis_client.dart`, `analysis_controller.dart`,
  `analysis_report.dart`, `video_source.dart`, `video_source_provider.dart`,
  `video_source_native.dart`, `video_source_web.dart`.
- `mobile/coaching/lib/screens/video_analysis_screen.dart`.
- `mobile/coaching/test/video_analysis_test.dart`.
- `mobile/coaching/web/recorded_video.js`, `flutter_bootstrap.js`.
- `docs/VIDEO_ANALYSIS.md`, `REAL_MODEL_INTEGRATION.md`, `LEGACY_LOCAL_TRAINING.md`.
- Generated synthetic `docs/demo/fajr_synthetic.mp4` (ignored) and test screenshots.

Modified for this task (pre-existing working-tree changes were preserved):

- `backend/app/main.py`, `config.py`, `backend/pyproject.toml`, `requirements.txt`.
- `mobile/coaching/lib/screens/home_screen.dart`, `lib/config/env.dart`.
- `mobile/coaching/android/app/src/main/kotlin/com/example/coaching/MainActivity.kt`.
- `mobile/coaching/web/index.html`, `test/widget_test.dart`.
- `README.md`, `.env.example`, `.gitignore`, all eight `.copilotarch/*.md` files.

No existing feature or source file was deleted by this migration.
