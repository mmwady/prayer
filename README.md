# Real-Time AI Fitness Coaching

A hybrid **Edge + Cloud** fitness coaching system that delivers real-time form
corrections via voice cues and an AR skeleton overlay — with **zero video streaming**
to the cloud. The camera feed never leaves the device; only lightweight JSON
pose-error telemetry is sent upstream.

- **Edge (Flutter)** — on-device pose detection, dynamic template-based form analysis,
  AR stick-figure overlay, WebSocket client, and streaming audio playback.
- **Cloud (FastAPI)** — receives JSON pose-error events, runs a LangGraph state
  machine, streams a DeepSeek LLM reply into a pluggable TTS engine, and streams
  audio chunks back over the same WebSocket.

Only telemetry (`{"exercise": "squat", "error": "curved_back", "rep_count": 5}`) goes up;
only audio + captions come down. This is what makes the system feel "zero-latency."

---

## Features

### 🤖 Real-Time Voice Coaching
- On-device **MediaPipe Pose** (or Google ML Kit) detects 33 body keypoints at
  30+ FPS — no cloud calls, no video upload.
- **Dynamic template matching** compares your live skeleton against a
  pre-recorded "perfect-form" template for the chosen exercise. Deviations are
  detected automatically instead of relying on hardcoded heuristics.
- Fault events are sent over WebSocket to the backend, where a **LangGraph state
  machine** decides if coaching is needed (respecting a cooldown to avoid nagging).
- **DeepSeek** (or any OpenAI-compatible LLM) generates concise, encouraging
  corrections in real time.

### 🔊 Pluggable Text-to-Speech
- Two providers, zero code changes to swap:
  - **Edge-TTS** (default) — free, no API key, uses Microsoft Edge voices.
  - **ElevenLabs** — premium low-latency streaming TTS (set `ELEVENLABS_API_KEY`).
- Sentence-level buffering for Edge-TTS; token-level streaming for ElevenLabs.
- Audio chunks play **as they arrive** — no waiting for the full reply.

### 🎯 AR Skeleton Overlay
- A **stick-figure** is painted over the live camera feed.
- Faulty joints glow **red with a breathing pulse animation** to draw the user's
  eye to the problem area mid-workout.
- Joints return to green once the correction is made.

### 📊 Session Summaries
- At the end of each set, a `0x03` summary frame is delivered with:
  - Total reps and perfect reps.
  - Breakdown of errors by type (e.g., "curved_back": 3).
  - Session duration.
- The summary can feed a post-workout dashboard.

### 🌐 Bilingual Support (English / Arabic)
- Language selector on the home screen.
- Separate Edge-TTS voices for English (`en-US-GuyNeural`) and Arabic
  (`ar-SA-HamedNeural`).
- LLM prompt instructs the model to reply in the chosen language.
- RTL text direction handled automatically in the UI.

### 🧩 Admin Dashboard & Template Management
- Upload reference videos via the `/admin` web dashboard.
- The backend processes videos through **MediaPipe + OpenCV** to extract
  per-frame skeleton templates stored as JSON.
- Templates are served to the mobile app via `GET /api/v1/templates` — the
  Flutter analyzer uses them for dynamic form comparison.

### 🔌 Provider-Agnostic Architecture
- **LLM**: Swap DeepSeek for vLLM, Ollama, Together AI, or any OpenAI-compatible
  endpoint by changing `DEEPSEEK_BASE_URL`.
- **TTS**: Toggle between `edge` and `elevenlabs` with a single env var.
- **Pose Detection**: Stub, Mobile (ML Kit), and Web (MediaPipe via JS) providers
  are swappable by importing a different `PoseDetector` implementation.

---

## Architecture

```
┌──────────────────────────────────────┐       ┌─────────────────────────────────────────┐
│  Flutter Mobile App (Edge)           │  WS   │  FastAPI Backend (Cloud)                │
│                                      │◄─────►│                                         │
│  ┌──────────┐    ┌───────────────┐   │  JSON │  ┌──────────────┐                        │
│  │ Camera   │───►│ PoseDetector  │   │  pose │  │  /ws/coach   │                        │
│  │ Stream   │    │ (MediaPipe /  │   │  event│  │  endpoint    │                        │
│  │          │    │  ML Kit /     │   │       │  │      │       │                        │
│  │          │    │  Stub)        │   │       │  │      ▼       │                        │
│  │          │    └──────┬────────┘   │       │  │  LangGraph   │                        │
│  │          │           │            │       │  │  StateMachine│                        │
│  │          │           ▼            │       │  │  ┌──────┐    │                        │
│  │          │    ┌───────────────┐   │       │  │  │classi│    │                        │
│  │          │    │ FormAnalyzer  │───┼───────┼──┼─►│fy    │    │                        │
│  │          │    │ (Template     │   │       │  │  │event │    │                        │
│  │          │    │  Matching)    │   │       │  │  └──┬───┘    │                        │
│  │          │    └──────┬────────┘   │       │  │     ▼        │                        │
│  │          │           │            │       │  │  ┌──────┐    │                        │
│  │          │           ▼            │       │  │  │build │    │                        │
│  │          │    ┌───────────────┐   │       │  │  │prompt│    │                        │
│  │          │    │ RepCounter    │   │       │  │  └──┬───┘    │                        │
│  │          │    │ (DTW-based)   │   │       │  │     ▼        │                        │
│  │          │    └───────────────┘   │       │  │  ┌─────────┐ │  ┌─────────────────┐  │
│  │          │                       │       │  │  │update   │ │  │  DeepSeek LLM   │  │
│  │          │    ┌───────────────┐   │  audio│  │  │state    │ │  │  (OpenAI-compat)│  │
│  │          │◄───┤ Audio Player  │◄──┼───────┼──┼──┤         │─┼─►│                 │  │
│  │          │    │ (just_audio   │   │  chunks│  │  └─────────┘ │  └────────┬────────┘  │
│  │          │    │  streaming)   │   │       │  │               │           │           │
│  │          │    └───────────────┘   │       │  │               │           ▼           │
│  │          │                       │       │  │               │  ┌─────────────────┐  │
│  │          │    ┌───────────────┐   │       │  │               │  │  TTS Provider   │  │
│  │          │    │ AR Overlay    │   │       │  │               │  │  (Edge /        │  │
│  │          │    │ (Stick-Figure │   │       │  │               │  │   ElevenLabs)   │  │
│  │          │    │  + Pulse)     │   │       │  │               │  └─────────────────┘  │
│  │          │    └───────────────┘   │       │  └─────────────────────────────────────────┘
│  └──────────┘                       │
│                                      │
│  Admin / Template Pipeline:          │
│  ┌──────────┐    ┌───────────────┐   │
│  │ Upload   │───►│ MediaPipe     │   │
│  │ Reference │    │ Skeleton      │   │
│  │ Video    │    │ Extraction    │   │
│  └──────────┘    └───────┬───────┘   │
│                          │           │
│                          ▼           │
│                   ┌───────────────┐  │
│                   │ JSON Template │  │
│                   │ (served via   │  │
│                   │  REST API)    │  │
│                   └───────────────┘  │
└──────────────────────────────────────┘
```

---

## Pipeline Deep Dive

### Frontend (Flutter) Pipeline

```
Camera Stream
     │
     ▼
┌─────────────────────────────────────────────────┐
│ 1. Pose Detection Layer                         │
│    ├─ Mobile: google_mlkit_pose_detection       │
│    ├─ Web:    MediaPipe via JS interop          │
│    └─ Dev:    StubPoseDetector (fakes data)     │
│    Output: 33 keypoints @ 30fps (normalized)    │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│ 2. Form Analysis Layer                          │
│    ├─ Fetches exercise template from backend    │
│    │  (GET /api/v1/templates)                   │
│    ├─ Finds closest matching template frame     │
│    │  using squared-distance minimization       │
│    ├─ Compares user joints against template     │
│    │  to detect angular deviations              │
│    └─ Output: PoseEvent if deviation > threshold│
└──────────────────────┬──────────────────────────┘
                       │
          ┌────────────┴────────────┐
          ▼                         ▼
┌──────────────────┐   ┌──────────────────────────┐
│ 3a. Rep Counter  │   │ 3b. WebSocket Client     │
│    (DTW-based)   │   │    ├─ Sends PoseEvent    │
│    ├─ Skeleton   │   │    │  as JSON text frame │
│    │  sequence   │   │    ├─ Sends PerfectSet   │
│    │  matching   │   │    │  on clean sets      │
│    └─ Rep count  │   │    ├─ Sends SessionEnd   │
│       tracking   │   │    │  on finish          │
└──────────────────┘   │    └─ Reconnects with    │
                       │       exponential backoff│
                       └───────────┬──────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │ 4. Downstream Processing     │
                    │    ├─ Binary frames arrive   │
                    │    │  0x01 = Caption (JSON)  │
                    │    │  0x02 = Audio (MP3)     │
                    │    │  0x03 = Summary (JSON)  │
                    │    ├─ Audio → StreamingMp3   │
                    │    │   Source (just_audio)   │
                    │    │   plays progressively   │
                    │    └─ Caption → UI display   │
                    └──────────────────────────────┘
```

| Layer | File(s) | Responsibility |
|-------|---------|---------------|
| **Pose Detection** | `pose_detector.dart`, `mobile_pose_detector.dart`, `pose_detector_provider_*.dart`, `web_video_pose_detector.dart` | Abstract interface + platform-specific implementations. Camera → keypoints. |
| **Form Analysis** | `form_analyzer.dart` | Compares live skeleton against exercise template; emits `PoseEvent` on deviation. |
| **Rep Counting** | `rep_counter.dart` | DTW-based sequence matching to count repetitions from keypoint data. |
| **WebSocket** | `ws_client.dart` | Persistent WS connection with auto-reconnect, send buffering, and binary frame decoding. |
| **Audio** | `audio_player.dart` | Custom `StreamAudioSource` for progressive MP3 playback — starts after first chunk. |
| **AR Overlay** | `ar_overlay.dart` | `CustomPainter` stick-figure with red pulse animation on faulty joints. |
| **State** | `workout_controller.dart` | Central `ChangeNotifier` — wires detector, WS, audio, and form analyzer together. |

### Backend (FastAPI) Pipeline

```
WebSocket Connection (/ws/coach)
     │
     ▼
┌─────────────────────────────────────────────────┐
│ 1. Connection Manager                           │
│    ├─ Accepts WS upgrade                        │
│    ├─ Creates Session (UUID + fresh state)      │
│    └─ Tracks active session count               │
└──────────────────────┬──────────────────────────┘
                       │
              JSON text frame arrives
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│ 2. Frame Parsing (schemas.py)                   │
│    ├─ Pydantic discriminated union on "type"    │
│    ├─ PoseEvent   → form fault                  │
│    ├─ PerfectSet  → zero-fault set              │
│    └─ SessionEnd  → end of workout              │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│ 3. LangGraph State Machine (per session)        │
│                                                  │
│    ┌──────────────┐                              │
│    │  START       │                              │
│    └──────┬───────┘                              │
│           ▼                                      │
│    ┌──────────────┐                              │
│    │ classify_    │  ← applies cooldown rule     │
│    │ event        │    (4s default per error)    │
│    └──────┬───────┘                              │
│           ▼                                      │
│    ┌──────────────┐                              │
│    │ build_prompt │  ← assembles LLM messages    │
│    └──────┬───────┘    (system + user context)   │
│           ▼                                      │
│    ┌──────────────┐                              │
│    │ update_state │  ← records error history,    │
│    └──────┬───────┘    rep count, timestamps     │
│           ▼                                      │
│    ┌──────────────┐                              │
│    │  END         │                              │
│    └──────────────┘                              │
│                                                  │
│    Output: CoachingState patch + should_coach    │
└──────────────────────┬──────────────────────────┘
                       │
          ┌────────────┴────────────┐
          ▼ (if should_coach)       ▼ (else → wait for next frame)
┌──────────────────────────────────────────────┐
│ 4. Streaming Pipeline                        │
│                                              │
│    ┌──────────────────────┐                   │
│    │ DeepSeek Client      │  Streaming LLM   │
│    │ (openai.AsyncOpenAI) │  token-by-token  │
│    │ astream(messages) ───┼──► text deltas   │
│    └──────────┬───────────┘                   │
│               ▼                               │
│    ┌──────────────────────┐                   │
│    │ TTS Provider         │  Text→Audio       │
│    │ ├─ EdgeTTS: buffers  │  streaming        │
│    │ │  by sentence,      │                   │
│    │ │  then synthesizes  │                   │
│    │ └─ ElevenLabs: token-│                   │
│    │    level bidirectional WS                │
│    └──────────┬───────────┘                   │
│               ▼                               │
│    ┌──────────────────────┐                   │
│    │ Binary Frame Encoder │  0x01 caption     │
│    │ (0x01 / 0x02 / 0x03) │  0x02 audio       │
│    └──────────┬───────────┘  0x03 summary     │
│               ▼                               │
│         WebSocket client                      │
└──────────────────────────────────────────────┘
```

| Layer | Module | Responsibility |
|-------|--------|---------------|
| **WebSocket** | `websocket/endpoint.py`, `connection_manager.py` | Accept connections, parse upstream frames, route to graph, send downstream binary frames. |
| **State Machine** | `graph/builder.py`, `graph/nodes.py`, `graph/state.py` | LangGraph pipeline: classify → build prompt → update state. Stateless graph, per-session state. |
| **LLM Client** | `llm/deepseek_client.py` | Async streaming DeepSeek via OpenAI SDK. Yields text deltas token by token. |
| **TTS** | `tts/base.py`, `tts/edge_tts_provider.py`, `tts/elevenlabs_provider.py`, `tts/factory.py` | Pluggable Text-to-Speech. Edge-TTS: free, sentence-buffered. ElevenLabs: token-streaming. |
| **Schemas** | `schemas.py` | Single source of truth for the client/server wire contract (Pydantic models). |
| **Session** | `session/summary.py` | Builds end-of-session summary from graph state (rep count, error histogram, duration). |
| **Admin** | `admin/router.py` | Video upload → MediaPipe skeleton extraction → JSON template generation. |
| **API** | `api/v1/router.py` | REST endpoints: `GET /api/v1/templates` serves exercise templates to the mobile app. |

---

## Project Layout

```
├── backend/                          # FastAPI cloud backend
│   ├── Dockerfile                    # Production container image
│   ├── pyproject.toml                # Python dependencies (PEP 621)
│   ├── requirements.txt              # Lockfile (pip freeze)
│   ├── commands.txt                  # Dev helper commands
│   └── app/
│       ├── main.py                   # App factory, CORS, healthz, WS mount
│       ├── config.py                 # pydantic-settings (env-driven)
│       ├── logging_config.py         # Structured logging setup
│       ├── schemas.py                # Wire-format Pydantic models (contract)
│       ├── admin/
│       │   ├── router.py             # Admin dashboard + video upload API
│       │   └── index.html            # Admin dashboard HTML/JS
│       ├── api/
│       │   └── v1/
│       │       └── router.py         # REST API (template serving)
│       ├── graph/
│       │   ├── builder.py            # LangGraph compilation
│       │   ├── nodes.py              # Graph node functions
│       │   └── state.py              # CoachingState TypedDict
│       ├── llm/
│       │   └── deepseek_client.py    # Async OpenAI-compatible LLM client
│       ├── session/
│       │   └── summary.py            # End-of-session summary builder
│       ├── tts/
│       │   ├── base.py               # Abstract TTSProvider
│       │   ├── edge_tts_provider.py  # Free Microsoft Edge TTS
│       │   ├── elevenlabs_provider.py# Premium ElevenLabs TTS
│       │   └── factory.py            # Provider selector (cached)
│       └── websocket/
│           ├── connection_manager.py # Live session registry
│           └── endpoint.py           # /ws/coach handler
│
├── mobile/
│   └── coaching/                     # Flutter mobile app
│       ├── pubspec.yaml              # Flutter dependencies
│       └── lib/
│           ├── main.dart             # App bootstrap + dark theme
│           ├── config/
│           │   ├── env.dart          # Environment configuration
│           │   └── translations.dart # i18n strings (EN/AR)
│           ├── models/
│           │   ├── keypoint.dart     # Keypoint + JointTag enums
│           │   ├── pose_event.dart   # PoseEvent + PerfectSet models
│           │   └── coaching_reply.dart# Downstream frame decoder
│           ├── screens/
│           │   ├── home_screen.dart  # Exercise picker + language selector
│           │   └── workout_screen.dart# Immersive workout view
│           ├── services/
│           │   ├── pose_detector.dart            # Abstract interface
│           │   ├── pose_detector_provider.dart   # Platform selection
│           │   ├── pose_detector_provider_stub.dart   # Dev stub
│           │   ├── pose_detector_provider_mobile.dart # ML Kit
│           │   ├── pose_detector_provider_web.dart    # Web provider
│           │   ├── mobile_pose_detector.dart    # ML Kit implementation
│           │   ├── web_video_pose_detector.dart # Web video file input
│           │   ├── form_analyzer.dart           # Template matching
│           │   ├── rep_counter.dart             # DTW rep counting
│           │   ├── ws_client.dart               # WebSocket client
│           │   └── audio_player.dart            # Streaming MP3 player
│           ├── state/
│           │   ├── workout_controller.dart      # Central session state
│           │   └── locale_provider.dart         # Language state
│           └── widgets/
│               ├── ar_overlay.dart              # Stick-figure painter + pulse
│               └── rep_counter.dart             # Rep count HUD
│
├── data/
│   ├── templates/                   # Generated exercise templates (JSON)
│   └── videos/                      # Uploaded reference videos
│
├── templates/
│   └── generate_template.py         # MediaPipe video → skeleton template
│
├── tests/
│   ├── test_graph.py                # LangGraph node unit tests
│   └── test_ws_contract.py          # Schema round-trip tests
│
└── docker-compose.yml               # One-command backend deployment
```

---

## How to Run

### Prerequisites

- **Docker** (for the backend)
- **Flutter SDK** ≥ 3.19 (for the mobile app)
- **Python** ≥ 3.11 (for local backend dev)
- A **DeepSeek** API key (or any OpenAI-compatible LLM endpoint)

### 1. Backend (Docker — Recommended)

```bash
# 1. Clone and navigate to the project root
cd coaching

# 2. Create environment config
cp .env.example .env

# 3. Edit .env with your API keys
#    DEEPSEEK_API_KEY=sk-your-key-here
#    DEEPSEEK_BASE_URL=https://api.deepseek.com/v1   # or vLLM/Ollama endpoint

# 4. Start the backend
docker compose up backend
```

The server starts on **`http://localhost:8000`**. Confirm with:

```bash
curl http://localhost:8000/healthz
# → {"status":"ok","active_sessions":0}
```

### 1b. Backend (Local — Without Docker)

```bash
cd backend

# Create and activate a virtual environment
python -m venv .venv
.venv\Scripts\activate    # Windows
# source .venv/bin/activate  # macOS/Linux

# Install dependencies
pip install -e .

# Copy and edit environment
cp .env.example .env
# Edit .env with your API keys

# Run the server
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload --ws websockets
```

### 2. Smoke-Test the WebSocket

```bash
# Install websocat (one-time):
#   Windows: choco install websocat
#   macOS:   brew install websocat
#   Linux:   cargo install websocat

websocat ws://localhost:8000/ws/coach
```

Then paste a pose event:

```json
{"type":"pose_event","exercise":"squat","error":"curved_back","faulty_joints":["spine_mid"],"rep_count":5,"t":1713532100.23}
```

You should receive:
1. A `0x01` binary frame — caption JSON (e.g., `{"text": "Keep your back straight!"}`)
2. A stream of `0x02` binary frames — MP3 audio chunks
3. Send `{"type":"session_end"}` to receive a `0x03` summary frame

### 3. Mobile App (Flutter)

```bash
cd mobile/coaching

# Install dependencies
flutter pub get

# Run on emulator or device
flutter run
```

> **Note:** The app defaults to `StubPoseDetector` which fakes a squat with
> periodic faults. This works on any emulator without a real camera.
>
> For real pose detection on a physical device, edit `pose_detector_provider.dart`
> to use `MobilePoseDetector` (requires `google_mlkit_pose_detection`).

#### Connecting to the Backend

By default the app connects to `ws://10.0.2.2:8000/ws/coach` (Android emulator
alias for the host machine). Configure this in `lib/config/env.dart`.

### 4. Admin Dashboard & Template Generation

1. Start the backend (see step 1).
2. Open **`http://localhost:8000/admin`** in a browser.
3. Upload an MP4 video of correct exercise form.
4. The backend extracts skeletons frame-by-frame via MediaPipe and saves a JSON
   template to `data/templates/`.
5. The mobile app fetches templates from `GET /api/v1/templates` automatically
   on session start.

### 5. Running Tests

```bash
cd backend

# Run graph node tests
pytest tests/test_graph.py -v

# Run schema contract tests
pytest tests/test_ws_contract.py -v

# Run all tests
pytest -v
```

---

## Runtime Configuration

All behavior is environment-driven via a `.env` file. Key variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `DEEPSEEK_BASE_URL` | `https://api.deepseek.com/v1` | OpenAI-compatible LLM endpoint |
| `DEEPSEEK_API_KEY` | `changeme` | Bearer token for the LLM |
| `DEEPSEEK_MODEL` | `deepseek-chat` | Model name to use |
| `DEEPSEEK_MAX_TOKENS` | `60` | Max tokens per coaching reply |
| `TTS_PROVIDER` | `edge` | TTS engine: `edge` (free) or `elevenlabs` |
| `TTS_VOICE` | `en-US-GuyNeural` | English TTS voice |
| `TTS_VOICE_AR` | `ar-SA-HamedNeural` | Arabic TTS voice |
| `ELEVENLABS_API_KEY` | `""` | Required if `TTS_PROVIDER=elevenlabs` |
| `COACHING_COOLDOWN_S` | `4.0` | Min seconds between same-error corrections |
| `LOG_LEVEL` | `INFO` | Logging verbosity |
| `PORT` | `8000` | Server port |

**Provider swaps require zero code changes** — just change the env var and restart.

---

## Wire Protocol (Client ↔ Server)

### Upstream (Client → Server) — JSON text frames

| Type | Fields | Description |
|------|--------|-------------|
| `pose_event` | `exercise`, `error`, `faulty_joints[]`, `rep_count`, `t` | Form fault detected |
| `perfect_set` | `exercise`, `reps` | Set completed with zero faults |
| `session_end` | — | End the workout session |

### Downstream (Server → Client) — Binary frames with 1-byte prefix

| Prefix | Type | Payload |
|--------|------|---------|
| `0x01` | Caption | JSON `{"text": "..."}` |
| `0x02` | Audio | Raw MP3 bytes |
| `0x03` | Summary | JSON `{"total_reps":..., "perfect_reps":..., "errors":{...}, "duration_s":...}` |
