# Debug Guide

## Iqtadi Setup and Verification

Backend (local, from source):

```powershell
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
copy ..\.env.example .env    # then set DEEPSEEK_API_KEY
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Backend (container), from the repository root — requires `backend/.env` to exist first:

```powershell
docker compose up --build
```

Flutter:

```powershell
cd mobile/coaching
flutter pub get
flutter run --dart-define=BACKEND_URL=http://127.0.0.1:8000
```

On a physical device use the host's LAN address, e.g.
`--dart-define=BACKEND_URL=http://192.168.1.10:8000`. On an Android emulator use `10.0.2.2`.

Select a prayer, load the activated reference, then use the camera (Android/iOS) or a local
side-view video (web). Without a backend you can still pick the labelled simulation, which
never calls the network and never claims to measure your movement.

## Tests

```powershell
cd backend
pytest -v
```

Backend tests are pure: the guidance tests replace the DeepSeek client with a fake, so no
network, key or cost is involved. `asyncio_mode = "auto"` is configured in `pyproject.toml`.

```powershell
cd mobile/coaching
flutter test
```

Flutter tests cover the sequence engine, classifier, calibration, controller lifecycle,
the guidance client and controller hook, and the Arabic UI. They are **not** real-camera
accuracy evidence. Per `Agents.md`, run `flutter analyze --no-pub` directly.
Parallel Flutter commands are allowed; serialize only if tool-lock contention is observed.

## Logs

- Format: `<iso timestamp> <LEVEL> <logger>: <message>` written to stdout.
- `uvicorn.access` is pinned to WARNING; real failures appear on `uvicorn.error`.
- Guidance fallbacks log at WARNING/ERROR: `Prayer guidance LLM is not configured`,
  `Prayer guidance generation failed`, `Prayer guidance model returned empty content`.

## Runtime Endpoints

- `GET /healthz` → `{"status": "ok", "guidance_enabled": true}`.
- `GET /docs` is available only when `LOG_LEVEL=DEBUG`.
- `GET /api/v1/prayer-guidance` → capability probe `{enabled, model, thinking}`.
- `GET /admin/prayer` → the Arabic reference editor (loopback-only, or configured admin bearer token).

## Common Issues

### Guidance always comes back as static text (`degraded: true`)
Work through these in order:
1. `DEEPSEEK_API_KEY` is empty or still `changeme`. `DeepSeekClient.is_configured()` rejects
   both and raises `LLMNotConfigured`; check the WARNING log line.
2. The reply was empty. `deepseek-flash` enables **thinking mode by default at effort=high**;
   the chain-of-thought consumes `max_tokens` and can leave `content` empty. Guidance disables
   thinking (`DEEPSEEK_THINKING=false`), so re-enabling it requires raising
   `DEEPSEEK_MAX_TOKENS` well above 160.
3. The provider rejected the request (401/402/429) or the call timed out. Every exception
   degrades to static text by design; the traceback is in the ERROR log line.
4. `PRAYER_GUIDANCE_ENABLED=false` is acting as a kill switch and never calls the network.

This is intended behaviour, not a crash: the route always returns HTTP 200 so the prayer
session is never blocked.

### `Model Not Exist` / invalid model error
The DeepSeek API accepts exactly two model names: `deepseek-flash` and `deepseek-v4-pro`.
The retired alias `deepseek-chat` fails at request time. Check `DEEPSEEK_MODEL`.

### Settings seem to have no effect
Pydantic resolves each `Settings` field to the uppercase env var of the same name — there is
no prefix — and `extra="ignore"` silently drops unknown keys. A variable named `QWEN_MODEL`
(or any other name that does not match a field) is ignored without warning. Use
`DEEPSEEK_MODEL`, `DEEPSEEK_API_KEY`, `DEEPSEEK_BASE_URL`, `DEEPSEEK_MAX_TOKENS`,
`DEEPSEEK_TEMPERATURE`, `DEEPSEEK_TIMEOUT_S`, `DEEPSEEK_THINKING`, `PRAYER_GUIDANCE_ENABLED`,
`HOST`, `PORT`, `LOG_LEVEL`.

### Container starts but guidance degrades
`docker-compose.yml` loads `env_file: ./backend/.env`. If that file is missing, the container
falls back to `DEEPSEEK_API_KEY="changeme"` and degrades every request. The Dockerfile copies
only `app/`, so an `.env` at the repository root is never read by the process.

### Flutter cannot reach the backend
- Android emulator: use `10.0.2.2`, not `127.0.0.1`.
- Physical device: pass `--dart-define=BACKEND_URL=http://LAN-IP:8000`.
- Flutter Web: `main.py` enables permissive CORS; a bare "Failed to fetch" is usually an
  origin/CORS problem or mixed content (an `http` URL from an `https` page).
- Guidance failures are silent by design. If the card says the static fallback was used, the
  request failed; check the backend log rather than the Flutter console.

### `GET /api/v1/prayer-reference` returns 404
No reference has been activated yet. Open `/admin/prayer`, upload an operator-supplied MP4,
label the six segments, then activate. Draft saves do not affect the served snapshot.

### Reference upload or extraction fails
Extraction needs `opencv-contrib-python` and `mediapipe` installed in the backend venv, and
runs in FastAPI's threadpool. Limits: 200 MB and 18000 decoded frames. The Docker image
installs these dependencies; a bare venv created without `requirements.txt` may not have them.

### Web pose detection does nothing

`web/mediapipe_wrapper.js` loads MediaPipe Pose from `cdn.jsdelivr.net`. Offline or blocked CDN
access leaves `window.estimatePose` pending. Check the browser console for the
"MediaPipe Pose Initialized" message.

### Live camera `openStore` is not a function

- A new Dart bundle can run against an older `iqtadiLive` JavaScript object after
  Hot Restart or cached asset loading. `index.html` versions the bridge URL with
  `?bridge=20261004-storage-1`; bump it when the interop contract changes.
- `WebFrameStore.open` checks `storageVersion` before invoking IndexedDB helpers.
  Restart the Flutter Web process and fully reload the page (Ctrl+Shift+R), not
  just Hot Restart. Browser QA verified storage byte fidelity and the legacy
  bridge guard without `NoSuchMethodError` or browser exceptions.

### Desktop shows no real inference
Only Android/iOS (ML Kit) and web-with-a-local-video are implemented. Every other `dart:io`
target falls back to `StubPoseDetector`, which the prayer screen rejects in favour of the
labelled simulation. This is expected, not a bug.

## Known Dependency Constraints

- Flutter requires SDK >= 3.3.0 and Flutter >= 3.19.0.
- MediaPipe JS is CDN-hosted and requires network access at runtime.
- MediaPipe Python is pinned to `0.10.11` and `numpy < 2`.

## Recorded-video diagnostics

- Follow `docs/VIDEO_ANALYSIS.md` for mock opt-in, consent and H.264 sample generation.
- MODEL_NOT_CONFIGURED in real mode is intentional until adapters/weights arrive; no mock fallback.
- 404 on a job/evidence means invalid ownership token, deletion, retention expiry or process restart.
- Duplicate batch content is idempotent before finalize; changed body under the same ID is 409.
- INVALID_TIMESTAMP_ORDER: times and indexes must strictly increase across all batches.
- Browser decode errors: check codec support; use H.264 rather than OpenCV's default mp4v for the demo.
- Retention uses isolated run directories/leases; never purge every run at startup (can delete live apps).
- Gradle's existing 8GB heap exhausted native memory on this host. Retry without editing global config:
  `gradlew.bat :app:assembleDebug --no-daemon --max-workers=2 "-Dorg.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=768m -XX:ReservedCodeCacheSize=128m" "-Pkotlin.compiler.execution.strategy=in-process"`.
- Restricted shell could not load Python's SSL DLL; use the authorized normal runtime for tests.
- Real ML accuracy and native orientation acceptance are separate from mock/API/widget tests.
- Blank report images without load errors: forcing CPU-only CanvasKit hides both asset and memory images on this runtime. `web/flutter_bootstrap.js` now uses normal renderer selection and ignores the old `?software=1` workaround. Isolated release-image comparison verified normal rendering displays both images while forced CPU leaves their spaces blank.

## Relocated Windows virtual environment

- `backend/.venv/Scripts/activate.bat` previously pointed to `D:\SofDev\coaching\backend\.venv` after project relocation. A (.venv) prompt did not guarantee the right environment.
- Use `backend/start_backend.bat` or the explicit `.venv/Scripts/python.exe -m uvicorn` command. Reactivate existing terminals after repairing activation scripts.
- Check process command lines and port 8000 listeners when local model smoke passes but HTTP jobs fail MODEL_NOT_CONFIGURED.
