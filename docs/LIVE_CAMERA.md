# Live prayer camera analysis

## Use

1. Choose a prayer on the home screen, then **تحليل مباشر بالكاميرا**.
2. Open the camera and position the phone so the whole body remains visible in
   standing, ruku and sujood. Preview alone sends no pictures to the backend.
3. Choose **التحليل الدقيق** (default) or **التحليل السريع**, explicitly consent,
   then press **ابدأ التحليل المباشر**. Wait for
   **التحليل المباشر يعمل** before starting the prayer; the backend first loads
   its model. Keep the app visible throughout the session.
4. Press **إنهاء الصلاة وإظهار التقرير**. Capture stops, pending frames are
   acknowledged, then the existing private report is generated.
5. **إلغاء الجلسة وحذف البيانات** stops capture and deletes the server job.
   The report also has a delete-and-return action. If deletion fails while
   offline, the app says so; server retention still expires the job.

No video/audio recording, LLM request, automatic prayer end, or religious
validity judgment is added. Uncertainty remains `UNCONFIRMED` / `REVIEW_REQUIRED`.

## Platforms and connection

- Android: existing Flutter `camera` plugin, sampled YUV image buffers, new
  `iqtadi/live_camera` native JPEG encoder; conversion runs on a background thread,
  honors plane row/pixel strides, normalizes portrait rotation and scales images.
  A front-camera preview is mirrored; transmitted images are not mirrored.
  `FLAG_KEEP_SCREEN_ON` is released when streaming ends. No extra dependencies.
- Web: `getUserMedia`, local preview, canvas JPEGs and browser WebSocket. Serve the
  Flutter app over HTTPS (localhost is allowed for local testing). Browser wake
  lock is best effort; the app explains when it is denied.
- iOS/desktop native capture is explicitly unsupported by this implementation.
- The app's existing backend settings apply to newly created clients. HTTPS
  backend URLs become `wss://`; local HTTP becomes `ws://`. Public/release use
  needs an HTTPS backend and a gateway that forwards WebSocket upgrades.
- Restart/redeploy the backend with the new code. `/api/v1/prayer-analyses/config`
  now returns `live_enabled: true`. The existing Cloudflare gateway permits the
  new paths; private operator routes remain blocked. Temporary tunnels stay
  temporary testing endpoints.

## Runtime

`lib/live/` owns camera, disk/IndexedDB pending storage, socket, consent/start/finish/cancel state.
`screens/live_analysis_screen.dart` reuses `AnalysisResults` and the existing theme.
`backend/app/analysis/live.py` owns live sessions; `jobs.py.build_report` is shared
with recorded analysis. The preserved local trainer is not used for inference.

Each live session has one dedicated inference thread: model creation, predictions
and disposal happen on that thread. Model readiness precedes camera capture.
Only one socket may own a session at a time. At most `analysis_workers` live
sessions are active; recorded worker limits continue to apply independently.

| Operation | Route |
|---|---|
| Create (consent, prayer, sample_fps, mode, optional explicit mock scenario) | `POST /api/v1/prayer-analyses/live` |
| Camera stream | `WS /api/v1/prayer-analyses/{id}/live` |
| Finish (optional `duration_ms`) | `POST /api/v1/prayer-analyses/{id}/live/complete` |
| Status, report, private evidence, deletion | Existing job routes |

The initial WS text message is `{"token":"<job capability>"}`; the token is never
in the URL. After authorization/model readiness the server sends `type: ready`.
Binary packets are `[4-byte big-endian header length][UTF-8 JSON header][JPEG]`.
The strict header contains `frame_id`, `sequence_index`, `timestamp_ms`.
Server `type: ack` includes `ack_stage`: buffered mode means validated and flushed
to disk (`stored`); adaptive mode means stored AND inferred (`processed`). An identical
retry is idempotent. Conflicting retries or invalid timestamps fail explicitly.
The final HTTP call also requires the job bearer token and is idempotent. Buffered
finish returns HTTP 202 immediately, closes further uploads, drains the ordered
queue and builds the shared report. The app polls private job status/progress until
COMPLETED; report retrieval remains gated until then. Adaptive finish retains HTTP 200.

No 30fps video uplink is needed: maximum/default sampling remains 4fps.

| Mode | Capture / delivery | Analysis |
|---|---|---|
| `buffered` / التحليل الدقيق | Fixed configured sampling; every sampled JPEG is saved locally before sending and retained until storage ACK. Backend saves disk references and does not hold the upload lock during inference. | Ordered single consumer continues after prayer end; no oldest-frame eviction. |
| `adaptive` / التحليل السريع | Camera skips sampling/encoding while a prior sampled frame is saving or awaiting inference ACK. Original timestamps are retained. | Adapts actual capture rate to processing/transport capacity, with no captured-frame eviction. |

Android local storage uses app temporary files; Web uses session-isolated IndexedDB
transactions. ACKed local JPEGs are removed; cancel deletes pending local/server
data. Expired abandoned local records are cleaned on the next session open (one
hour). Local write/quota failure stops capture explicitly; it never silently produces
a partial report. Failed/final delivery retains pending files for retry/cancel.
Finish retries delivery for about two minutes before exposing retry/cancel; backend
analysis itself is polled without that short deadline. Original capture times/indexes
are preserved; blind periods remain uncertain. “Precise” describes sampling coverage,
not a guarantee of pose recognition or religious validity.

Existing settings bound JPEG bytes/dimensions, duration, frame count, capacity,
temporary storage and retention. `ANALYSIS_LIVE_BUFFER_BYTES` defaults to 480MB
per live session, including processed images retained until report construction.
The client reserves `max_frame_bytes` per capture conservatively against this
ceiling and also bounds pending local bytes. Exhaustion stops capture; server
quota rejection is explicit (507), never eviction. With defaults, 2400 frames at 4fps allows about
10 minutes; the independent duration ceiling is 20 minutes. The app finalizes at
the first limit instead of silently continuing. Increase frame count, duration
AND the buffer-byte budget for longer precise sessions; test disk/CPU capacity first.

Backgrounding ends capture and attempts to finalize the received portion. Back
navigation is blocked during an active session; explicit cancel remains available.
Keep the app/tab open until sending finishes: local storage does not add automatic
resume after app termination or page reload. Sessions are single-process/in-memory
and cannot survive backend restart. Retention
defaults to one hour; successful reports keep only representative evidence images.

## Validation

Earlier verification 2026-10-04: 136 backend tests and 71 Flutter tests passed; analyzer reports
only the six existing informational findings outside the added flow. Android release
APK and release Web builds passed. Browser QA at 390px processed 82 synthetic-camera
frames, reconnected after a forced disconnect, rendered a mock report, deleted data
and returned to video selection without console errors. Artifacts retain synthetic labels.

- Backend live tests cover early inference, model readiness, auth/consent, exclusive
  sockets, reconnect/idempotent replay, malformed images/order/conflicts, capacity,
  frame limits, no mock fallback, gaps, private evidence, finish and deletion.
- Mode tests cover 60 stored frames while inference is blocked, idempotent retry,
  asynchronous finish, late delivery, explicit disk bounds and cancel during inference.
- Flutter tests cover consent, wire packet fidelity, lost ACKs, all 60 pending
  sampled frames, adaptive sampling gates, local storage lifetime/failure, progress
  polling, finish ordering, cancellation and the setup screen.
- `tools/verify_live_real.py` loads the actual bundled CPU ensemble and sends
  synthetic solid-black JPEGs; no-body must produce zero detected stations and
  `REVIEW_REQUIRED`. This does not establish real prayer accuracy.
- `tools/live_smoke_server.py` runs an isolated explicit mock backend for browser
  transport QA, with no `.env` changes or paid provider calls. Browser artifacts
  live in `output/playwright/live-*`; the browser camera is visibly synthetic.
- Android release compilation is verified. Physical Android camera color,
  orientation, long-session battery/network behavior and real prayer recognition
  still require device acceptance; no device was connected during this change.

Diagnostics log per-frame `storage_ms`, `processing_ms`, mode and queued count,
without tokens, JPEG bytes or pose payloads. A buffered ACK also returns
`buffered_frames` and the latest `processing_ms`. These separate inference
backlog from storage/transport delays; the UI no longer labels missed images as
“slow internet”. `tools/live_smoke_server.py --prediction-delay 0.7` intentionally
slows the explicit mock model for transport QA, never the production model.

Mode QA (2026-10-04): 141 backend / 75 Flutter tests passed. An intentionally held backend
inference received 60 frames with storage ACKs and subsequently processed every
frame once in order. At 390px in Edge, the real camera/canvas/IndexedDB/WebSocket
flow with a synthetic camera and a 700ms mock delay produced: precise 32 frames,
peak backlog 23, ~17s finish wait; fast 8 frames, no backlog, ~0.38s finish wait.
All ACKed frame indices were contiguous and matched the final processed count;
precise reconnect, private report/delete/return and IndexedDB byte fidelity/deletion
passed without browser errors. This verifies transport, not real pose-model accuracy.
