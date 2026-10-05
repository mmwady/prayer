# Architecture Decisions

## 2026-10-05: all prayer training local; backend only for Mosque Companion

Accepted by user: replaces default server video/live/reference/guidance paths with
local adapters, while retaining UI and compatibility implementations. The raw Python
model/temporal/sequence semantics remain authoritative; JS/Dart/native ports require
parity. Full individual decisions, classifier disagreement and religious uncertainty
are retained. Web offline updates are atomic and explicitly activated. History quotas
raise warnings without silently deleting saved sessions. Native Android packages the
same Heavy/ONNX assets; ML Kit geometry is not substituted for the166-feature input.
This supersedes default server transport decisions below, which remain historical.

## Live camera - stream JPEG observations through the backend report engine

Status: Accepted (2026-10-04, user approved live-camera implementation).

Decision: Add a dedicated consented camera WebSocket rather than transmitting a
video/audio file. Reuse the current model, temporal/sequence assessment and private
reports. Prepare the model before camera capture. User-selected buffered mode ACKs
after validated disk save and analyzes an ordered disk queue; adaptive mode ACKs
after inference and gates sampling before JPEG conversion. Pending client JPEGs
use temporary files/IndexedDB until ACK; replay stays idempotent with original times.

Reason: The existing analysis pipeline already consumes sampled JPEGs. Bounded
transport extends it without introducing a separate video server or local classification.

Consequences: Foreground Android/Web only initially; explicit end, visible storage/frame
limits and uncertain gaps, no captured-frame eviction or silent mock fallback. Buffered
finish is asynchronous with progress polling. Existing retention and single-process
restart limitations apply; physical camera/prayer accuracy needs separate acceptance.

Active decisions first, then the retired sports-era records kept for context.

## ADR-001 - Legacy training sends structured facts only

Status: Amended for recorded-video mode by ADR-017; preserved for legacy local training

Decision:
The legacy local-training client never sends camera frames, video, keypoints or identity anywhere. The only
uplink is a compact structured JSON body describing prayer session state.

Reason:
Pixels must never leave the device; a handful of enum/int fields is all the model needs to
phrase one Arabic sentence.

Consequences:
All inference stays on-device, and the backend's view of a session is limited to what the
client chooses to describe.

Do not change unless:
A resumable, privacy-reviewed media uplink architecture is intentionally introduced.

## ADR-005 - Provider-agnostic LLM via an OpenAI-compatible endpoint

Status: Accepted

Decision:
Use `openai.AsyncOpenAI` against a configurable `DEEPSEEK_BASE_URL`.

Reason:
DeepSeek and other providers expose the Chat Completions format, so switching providers is
an environment change with no code change.

Consequences:
Provider-specific features are unavailable and the client class stays deliberately narrow
(`complete` only). The default model is `deepseek-flash`; `deepseek-chat` is retired and fails
at request time.

Do not change unless:
A provider requires a non-OpenAI protocol.

## ADR-011 - Configuration is environment-driven through one settings object

Status: Accepted

Decision:
All backend knobs live in `Settings` (pydantic-settings, `.env`-backed) behind a cached
`get_settings()`.

Reason:
Twelve-factor parity across dev and container, fail-fast validation at startup, and one place
to change for a provider swap.

Consequences:
Tests must call `get_settings.cache_clear()` to observe patched values, and modules must not
read `os.environ` directly. Env var names must match field names exactly — the previous
`QWEN_*` template was silently ignored for exactly this reason.

Do not change unless:
Multi-tenant per-request configuration is required.

## ADR-012 - Preserved local-training progression is deterministic

Status: Accepted for preserved local training; recorded video follows ADR-017

Decision:
Reuse the existing detector/keypoint/overlay contracts and Provider pattern; use one locally
configured prayer station engine with static versioned feedback. The engine owns progression
and never waits on the network.

Reason:
Physical sequence recognition needs reliable local state and must not depend on provider
availability or generate religious assessments.

Consequences:
Legacy training sessions do not upload video. Summaries are local and temporary. Simulation remains
labelled; geometry accuracy requires device acceptance evidence.

## ADR-013 - Arabic guidance is advisory, memoised and fail-safe

Status: Accepted

Decision:
Add `POST /api/v1/prayer-guidance` backed by DeepSeek `deepseek-flash`. The route always
answers HTTP 200 with `{text, model, degraded}`; every failure path (missing key, timeout,
provider error, empty reply, disabled kill switch) returns bundled static Arabic text with
`model: "static"`. Requests fire only on discrete session transitions and are deduped by
`(event, station, rakah)`. Results are memoised in-process, bounded to 256 entries.

Reason:
An Arabic cue improves the learning experience, but a network dependency must never block,
slow or alter deterministic station progression.

Consequences:
Guidance is best-effort and can be absent entirely; the UI must render nothing when there is
no text. Guidance is disabled for synthetic simulation so labelled practice data can never
look like real coaching. Cost is bounded by memoisation and `DEEPSEEK_MAX_TOKENS`.

Do not change unless:
Guidance becomes part of progression, which would break ADR-012.

## ADR-014 - Thinking mode is disabled for short guidance

Status: Accepted

Decision:
Send `extra_body={"thinking": {"type": "disabled"}}` by default (`DEEPSEEK_THINKING=false`).

Reason:
`deepseek-flash` enables thinking at effort=high by default. Reasoning tokens are billed as
output, consume the `max_tokens` budget, and can leave `content` empty — which for a
one-sentence cue looks like a silent failure. Thinking mode also ignores `temperature`.

Consequences:
`temperature` is meaningful only while thinking is off. Enabling thinking requires raising
`DEEPSEEK_MAX_TOKENS` and accepting higher latency and cost.

Do not change unless:
Guidance needs multi-step reasoning, which the product does not.

## ADR-015 - One secrets file, loaded by both dev and Docker

Status: Accepted

Decision:
`backend/.env` holds the application settings. `docker-compose.yml` loads it via
`env_file: ./backend/.env`; the root `.env` holds compose-level `PORT` only.

Reason:
Previously the root `.env` (loaded by compose) documented `QWEN_*` names that `Settings`
silently ignored, so the container ran with `DEEPSEEK_API_KEY="changeme"` and the code
default. Two files with one meaning removes the drift.

Consequences:
Running uvicorn from `backend/` and running the container read identical configuration. The
root `.env` must never hold `DEEPSEEK_*` again, or the two sources can diverge.

Do not change unless:
A secrets manager replaces file-based configuration.

## ADR-016 - The sports stack is deleted, not disabled

Status: Accepted

Decision:
Remove the sports product entirely from both stacks rather than keeping it dormant behind
navigation.

Reason:
Dormant modules still impose dependency weight, maintenance surface, documentation debt and a
real risk of accidental reuse of sports prompts or summaries in a religious context.

Consequences:
The WebSocket wire protocol, LangGraph graph, LLM coaching prompts, TTS providers, template
and rule APIs, admin template dashboard, Flutter workout UI, form analyzer, rep counters,
streaming audio and the bilingual dictionary are gone. `just_audio` and `web_socket_channel`
were dropped from `pubspec.yaml`; `langgraph`, `langchain-core`, `edge-tts` and the explicit
`websockets` pin were dropped from the backend dependencies. Git history retains the code.

Do not change unless:
A new product line genuinely needs that infrastructure, in which case it should be rebuilt
against the current contracts rather than restored wholesale.

## Retired Records

| ADR | Subject | Why retired |
|---|---|---|
| ADR-002 | Binary downstream frames with a 1-byte kind prefix | No WebSocket wire protocol exists |
| ADR-003 | LangGraph owns state, WebSocket owns streaming | Graph and endpoint deleted |
| ADR-004 | TTS providers consume an async text iterator | All TTS providers deleted |
| ADR-006 | In-memory single-process session state | Session registry deleted; no sessions |
| ADR-007 | TTS providers cached per language | All TTS providers deleted |
| ADR-008 | On-device form analysis configured by the backend | FormAnalyzer and rule APIs deleted |
| ADR-009 | Short templates switch to a phase-based counter | Rep counters deleted |
| ADR-010 | Template generation is synchronous and blocking | Generator and dashboard deleted |

## ADR-017 - Recorded-video reports are owned by the backend

Status: Accepted, 2026-10-03; explicitly supersedes the global no-image-upload/local-only policy.

Decision: After explicit consent Flutter uploads bounded sampled JPEG frames and timestamps;
backend replaceable extractor/classifier → temporal processing → conservative sequence alignment
owns all recorded-video decisions. The old local trainer is separate and retained.

Reason: Deliver a demonstrable offline-recorded pipeline now, independent of two unavailable models.
Mock is deterministic scenario data, conspicuously labelled, opt-in only; real never falls back.

Consequences: Temporary private media requires per-job bearer ownership, retention/deletion,
transport limits, HTTPS/authentication before external deployment. No religious judgments/identity.
Single-process managed local workers suffice for the hackathon; in-memory jobs do not survive restart.
Station assignment confirms only unique mandatory matches across optimal sequence alignments.

## Mosque Companion - isolate a persistent demonstration from production

Status: Accepted (2026-10-04).

Decision: Use the existing FastAPI backend with per-session SQLite JSON state and `BEGIN IMMEDIATE` for demo reservation mutations. Enable only by `MOSQUE_DEMO_ENABLED=true`. Random bearer capability authorizes an isolated fictional dataset; persona switching exists solely inside that dataset. Production account operations are unavailable.

Reason: The committee needs persisted shared state across personas and verifiable atomic capacity without adding an unrelated authentication/database platform or contacting real people. The current app has no suitable account system or street-routing integration.

Consequences: Public trip responses omit provider origins; invited providers see approximate requester scope until bilateral confirmation. Routing/timing/approval/family delegation remain explicitly synthetic. Production requires a separate authenticated identity/approval/real-routing boundary; disabling the demo cannot silently connect it to real accounts. Prayer analysis/guidance remain independent.
