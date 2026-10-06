# Project Index

**اقتدِ (Iqtadi)** — Arabic-first on-device recorded-video/live-camera/image prayer analysis.
All six existing prayer cards use local inference, temporal/sequence assessment, reports,
evidence/history/export, references and static cues. Optional account monitoring sends
only final scalar results; Mosque Companion also uses a backend.
Legacy backend tooling and explicitly injected HTTP test clients remain for compatibility.
Web shares the same-origin Heavy MediaPipe/ONNX worker; Android bundles the same models in
a serial native CPU channel. See `docs/LOCAL_TRAINING.md` and measured acceptance.

The original sports/fitness coaching stack (WebSocket coaching, LangGraph, TTS, templates,
form analyzer, rep counter) has been **deleted**, not merely disconnected.

## Tech Stack

| Layer | Stack |
|---|---|
| Backend | Python >= 3.11, FastAPI, uvicorn[standard], Pydantic v2 + pydantic-settings, OpenAI-compatible async client (DeepSeek `deepseek-flash`) |
| Reference tooling | OpenCV + MediaPipe (`app/admin/prayer_references.py`, lazily imported) |
| Recorded video | On-device Android native retriever / web canvas; local temporal and sequence reports; retained Python tooling |
| Frontend (edge) | Flutter / Dart >= 3.4, provider, camera, Heavy MediaPipe Tasks + ONNX Runtime 1.23.2 (Web/native Android); retained ML Kit geometry trainer |
| Deployment | Local `docker-compose.yml`; VPS Web/Nginx + Docker backend + stable OVH HTTPS in `deploy/vps/`; see `docs/VPS_DEPLOYMENT.md` |

## Primary Entry Points

- Recorded analysis: `mobile/coaching/lib/local/`, `mobile/coaching/lib/video/`,
  `mobile/coaching/lib/screens/video_analysis_screen.dart`
- Live camera: `mobile/coaching/lib/local/`, `mobile/coaching/lib/live/`,
  `mobile/coaching/lib/screens/live_analysis_screen.dart`; see `docs/LIVE_CAMERA.md`.
- Backend app factory: `backend/app/main.py`
- Local prayer guidance: `LocalPrayerGuidanceSource` in `mobile/coaching/lib/services/prayer_guidance_client.dart`
- LLM client: `backend/app/llm/deepseek_client.py`
- Local reference management: `mobile/coaching/lib/prayer/local_prayer_reference_repository.dart`; legacy operator extraction: `backend/app/admin/prayer_references.py`
- Flutter bootstrap: `mobile/coaching/lib/main.dart`
- Browser inference: `mobile/coaching/browser/`, conditional `lib/browser/recognizer_screen.dart`; see `docs/BROWSER_DEPLOYMENT.md`.
- Prayer session brain: `mobile/coaching/lib/state/prayer_controller.dart`
- Prayer definitions/sequence: `mobile/coaching/lib/prayer/`
- Retained compatibility HTTP guidance class: `PrayerGuidanceClient` in `mobile/coaching/lib/services/prayer_guidance_client.dart`

## Conventions

- All backend config flows through `get_settings()` (`backend/app/config.py`); never read
  `os.environ` directly.
- Env var names must match `Settings` field names exactly — there is no prefix. `DEEPSEEK_*`,
  not `QWEN_*`.
- Backend data directories resolve relative to the process CWD, which must be `backend/`.
- Raw Python definitions/temporal/sequence rules remain the source of truth; matching JS/Dart local ports own runtime reports.
- `backend/.env` is the single place for secrets; the root `.env` holds compose-level `PORT` only.
- Only `deepseek-flash` and `deepseek-v4-pro` are valid DeepSeek model names; `deepseek-chat`
  is retired and fails at request time.
- Dart guidance vocabularies mirror the backend literals by hand; changing one requires
  changing the other.
- Flutter platform-specific code must go through conditional exports, never unconditional
  `dart:html` / `dart:io` imports.

## Memory Files

- `CURRENT_STATE.md` — where the project stands now
- `PROJECT_MAP.md` — important files and responsibilities
- `ARCHITECTURE.md` — runtime architecture, data flow, invariants
- `FEATURE_MAP.md` — feature to implementation mapping
- `DECISIONS.md` — architectural decision records
- `DEBUG_GUIDE.md` — setup, diagnostics, recurring issues
- `CHANGELOG.md` — meaningful project changes

Local frame extraction uses native Android/web decoding; inference uses the packaged Heavy MediaPipe and three ONNX models. Python remains the parity source of truth.


## Mosque Companion demo

- Backend: `app/mosque/` → SQLite demo sessions behind explicit opt-in; Flutter: `mobile/coaching/lib/mosque/`, home card.
- Run/limitations: `docs/MOSQUE_COMPANION.md`; no production identities or real street routing are claimed.

Deployment agents: use `docs/VPS_DEPLOYMENT.md` for direct SSH release steps and server/browser logs; direct deployment is preferred over waiting for GitHub Actions.
