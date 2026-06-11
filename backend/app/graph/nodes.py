"""LangGraph node functions.

Each node is a **pure(-ish) async function** that takes the current state and
returns a partial state update. That shape lets LangGraph compose them into
a compiled `StateGraph` and also makes them trivially unit-testable —
every test is just `await classify_event(state)` with a handcrafted state.

The five nodes correspond to one logical tick of the pipeline:

    classify_event → build_prompt → call_llm → emit_audio → update_state

Note: `call_llm` and `emit_audio` in a pure LangGraph graph would return
accumulated text / audio. But we want token-level streaming to the
WebSocket. The compromise here:

  * `call_llm` runs the LLM and collects the *full* text (used by
    `update_state` for history).
  * Actual streaming-to-client happens in `websocket/endpoint.py` BEFORE
    the graph runs, using `stream_coaching()` below — a helper that reuses
    the same prompt logic but yields to the wire.

This split keeps the graph the system-of-record for *state*, and lets the
websocket layer own *streaming* where latency actually matters.
"""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator

from ..config import get_settings
from ..llm.deepseek_client import get_deepseek_client
from ..schemas import PerfectSet, PoseEvent
from ..tts.base import TTSProvider
from .state import CoachingState

_log = logging.getLogger(__name__)


# ─── System prompt ─────────────────────────────────────────────────────────
# Deliberately short and directive. The model is tiny (7B) and running under
# tight max_tokens; verbose personas waste budget.
def _get_system_prompt(lang: str) -> str:
    language_name = "Arabic" if lang == "ar" else "English"
    return (
        "You are a supportive, high-energy personal fitness coach speaking live "
        "to a user mid-workout. Reply with ONE short sentence (≤ 14 words) that "
        f"corrects their form and encourages them. Reply in {language_name}. "
        "Do not greet, do not explain, do not add emojis. Speak in the second person."
    )


# Map of machine-readable error ids → human phrasing for the prompt.
# With dynamic matching in form_analyzer.dart, generic deviations can also be
# described using faulty_joints.
_ERROR_PHRASES: dict[str, str] = {
    "curved_back": "their back is rounding forward",
    "knee_over_toe": "their knees are traveling past their toes",
    "knee_supported_pushup": "they are resting their knees on the floor during a full push-up",
}


# ─── Node 1: decide whether this event warrants coaching ──────────────────
async def classify_event(state: CoachingState) -> CoachingState:
    """Apply the cooldown rule and set `should_coach`."""

    event = state["event"]
    settings = get_settings()
    patch: CoachingState = {}

    if isinstance(event, PoseEvent):
        last = state.get("last_coached_at", {}).get(event.error, 0.0)
        if event.t - last >= settings.coaching_cooldown_s:
            patch["should_coach"] = True
        else:
            patch["should_coach"] = False
    elif isinstance(event, PerfectSet):
        patch["should_coach"] = True
    else:
        patch["should_coach"] = False

    return patch


# ─── Node 2: build the LLM prompt messages ────────────────────────────────
async def build_prompt(state: CoachingState) -> CoachingState:
    """Assemble an OpenAI-format chat history for the LLM."""

    if not state.get("should_coach"):
        return {}

    event = state["event"]
    language = state.get("language", "en")
    messages: list[dict[str, str]] = [{"role": "system", "content": _get_system_prompt(language)}]

    if isinstance(event, PoseEvent):
        if event.error in _ERROR_PHRASES:
            phrase = _ERROR_PHRASES[event.error]
        elif event.faulty_joints:
            joints_str = ", ".join(j.replace("_", " ") for j in event.faulty_joints)
            phrase = f"their {joints_str} shifted out of position compared to the perfect form template"
        else:
            phrase = event.error.replace("_", " ")

        recent = state.get("error_history", [])[-3:]
        repeat_clause = (
            f" They have already had this issue {recent.count(event.error)} time(s) this session."
            if event.error in recent
            else ""
        )
        messages.append({
            "role": "user",
            "content": (
                f"The user is doing a {event.exercise}. "
                f"Form fault: {phrase}.{repeat_clause} "
                f"Give them a one-sentence correction."
            ),
        })
    elif isinstance(event, PerfectSet):
        messages.append({
            "role": "user",
            "content": (
                f"The user just completed a PERFECT set of {event.reps} "
                f"{event.exercise}s with flawless form. "
                f"Give them one enthusiastic sentence of praise."
            ),
        })

    return {"prompt_messages": messages}


# ─── Node 3: call the LLM (non-streaming collection for state bookkeeping) ─
async def call_llm(state: CoachingState) -> CoachingState:
    """Run the LLM to get the full coaching reply."""

    if not state.get("should_coach"):
        return {}

    pieces: list[str] = []
    async for delta in get_deepseek_client().astream(state["prompt_messages"]):
        pieces.append(delta)
    return {}


# ─── Node 4: update the long-lived session state ──────────────────────────
async def update_state(state: CoachingState) -> CoachingState:
    """Record this event's side-effects on the session state."""

    event = state["event"]
    patch: CoachingState = {}

    if isinstance(event, PoseEvent):
        history = list(state.get("error_history", []))
        history.append(event.error)
        patch["error_history"] = history

        cooldowns = dict(state.get("last_coached_at", {}))
        if state.get("should_coach"):
            cooldowns[event.error] = event.t
        patch["last_coached_at"] = cooldowns

        patch["exercise"] = event.exercise
        patch["rep_count"] = event.rep_count

        if "session_started" not in state:
            patch["session_started"] = event.t

    elif isinstance(event, PerfectSet):
        patch["perfect_reps"] = state.get("perfect_reps", 0) + event.reps
        patch["exercise"] = event.exercise

    return patch


# ─── Streaming helper used by the WebSocket layer ─────────────────────────
async def stream_coaching(
    state: CoachingState,
    tts: TTSProvider,
) -> AsyncIterator[tuple[str, bytes | str]]:
    """Run the LLM + TTS streams, yielding `(kind, payload)` tuples."""

    if not state.get("should_coach"):
        return

    messages = state.get("prompt_messages") or []
    if not messages:
        _log.warning("stream_coaching called without prompt_messages — skipping.")
        return

    llm_stream = get_deepseek_client().astream(messages)
    caption_buf: list[str] = []

    async def tee() -> AsyncIterator[str]:
        async for delta in llm_stream:
            caption_buf.append(delta)
            yield delta

    async for audio in tts.stream(tee()):
        yield ("audio", audio)

    full_text = "".join(caption_buf).strip()
    if full_text:
        yield ("caption", full_text)
