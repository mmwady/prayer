"""The `/ws/coach` WebSocket endpoint — the real-time core of the system.

Lifecycle (one connection):

  1. Client opens WS.
  2. On every upstream JSON frame → parse into a `ClientEvent`.
  3. Run the graph to update session state (fast — no LLM call in the
     live path; see `stream_coaching` instead).
  4. If `should_coach` flipped true, call `stream_coaching()` and relay
     audio frames (0x02) + caption frame (0x01) as they arrive.
  5. On `session_end` (or disconnect) → send SUMMARY (0x03) and close.

Why we sidestep `call_llm` in LangGraph for the live path
---------------------------------------------------------
The graph is optimized for *state correctness*. Audio streaming is
optimized for *latency*. Running the LLM inside the graph would force us
to collect the entire reply before a single byte reaches the client.
Instead we:

  • Run the graph without the LLM call (it no-ops when state already has
    `should_coach`), capturing the state patch.
  • Run `stream_coaching` beside it, piping tokens → TTS → WebSocket.

Both paths see the same prompt because both read from `state["prompt_messages"]`
that was set by `build_prompt`.
"""

from __future__ import annotations

import json
import logging
import time

from fastapi import WebSocket, WebSocketDisconnect
from pydantic import TypeAdapter, ValidationError

from ..graph.builder import build_graph
from ..graph.nodes import stream_coaching
from ..schemas import ClientEvent, CoachingCaption, FrameKind, SessionEnd
from ..session.summary import build_summary
from ..tts.factory import get_tts
from .connection_manager import Session, manager

_log = logging.getLogger(__name__)

# Compile the graph once at import time — it's stateless and safe to share.
_GRAPH = build_graph()

# `TypeAdapter` gives us a single discriminated-union parser for the
# `ClientEvent` union. Reusing it across frames avoids repeated Pydantic
# schema compilation.
_EVENT_ADAPTER: TypeAdapter[ClientEvent] = TypeAdapter(ClientEvent)


# ─── Frame helpers ─────────────────────────────────────────────────────────
def _frame(kind: FrameKind, payload: bytes) -> bytes:
    """Prepend a single-byte kind tag — this is our binary wire format."""

    return bytes([int(kind)]) + payload


async def _send_caption(ws: WebSocket, text: str) -> None:
    """Emit a 0x01 caption frame with JSON body."""

    body = CoachingCaption(text=text).model_dump_json().encode("utf-8")
    await ws.send_bytes(_frame(FrameKind.CAPTION, body))


async def _send_audio(ws: WebSocket, chunk: bytes) -> None:
    """Emit a 0x02 audio frame."""

    await ws.send_bytes(_frame(FrameKind.AUDIO, chunk))


async def _send_summary(ws: WebSocket, session: Session) -> None:
    """Emit the final 0x03 summary frame derived from session state."""

    summary = build_summary(session.state)
    body = summary.model_dump_json().encode("utf-8")
    await ws.send_bytes(_frame(FrameKind.SUMMARY, body))


# ─── Main handler ──────────────────────────────────────────────────────────
async def coach_endpoint(ws: WebSocket, lang: str = "en") -> None:
    """Handle one coaching WebSocket from open to close."""

    session = await manager.connect(ws)
    session.state["language"] = lang
    tts = get_tts(lang)

    try:
        while True:
            # We only accept text frames from the client — binary uplink is
            # reserved for a future "audio question" feature.
            raw = await ws.receive_text()

            # ── 1. Parse ────────────────────────────────────────────────
            try:
                data = json.loads(raw)
                event = _EVENT_ADAPTER.validate_python(data)
            except (json.JSONDecodeError, ValidationError) as exc:
                _log.warning("sid=%s bad frame: %s", session.id, exc)
                # We don't disconnect on a bad frame — clients may send
                # stray heartbeats we haven't modeled yet. Just skip.
                continue

            # ── 2. Run the graph to update state ────────────────────────
            # Pass the event into the graph by merging it into the current
            # session state; the returned state becomes the new truth.
            tick_state = dict(session.state)
            tick_state["event"] = event
            new_state = await _GRAPH.ainvoke(tick_state)
            # LangGraph returns a CoachingState-shaped dict. Persist it.
            session.state = new_state  # type: ignore[assignment]

            # ── 3. Stream coaching if warranted ─────────────────────────
            if new_state.get("should_coach"):
                await _stream_reply_to_client(ws, new_state, tts)

            # ── 4. Handle session_end by closing cleanly ────────────────
            if isinstance(event, SessionEnd):
                await _send_summary(ws, session)
                await ws.close()
                return

    except WebSocketDisconnect:
        # Client hung up. Still emit a summary? We can't — the socket is
        # already closed. But DO log duration for ops.
        _log.info(
            "sid=%s disconnected after %.1fs",
            session.id,
            time.time() - session.state.get("session_started", time.time()),
        )
    finally:
        manager.disconnect(session)


async def _stream_reply_to_client(ws, state, tts) -> None:
    """Run the LLM+TTS streaming pipeline and relay frames to the client.

    Errors (bad API key, network timeout, TTS failure) are caught here so a
    single failed coaching cue doesn't tear down the whole WebSocket session.
    The user simply won't hear that particular correction; the session
    continues and the next event may succeed (e.g. after a key rotation).
    """

    try:
        caption_text: str | None = None
        # `stream_coaching` yields ('audio', bytes) for each chunk and then
        # ('caption', str) once at the end. We forward each appropriately.
        async for kind, payload in stream_coaching(state, tts):
            if kind == "audio":
                await _send_audio(ws, payload)  # type: ignore[arg-type]
            elif kind == "caption":
                caption_text = payload  # type: ignore[assignment]
        if caption_text:
            await _send_caption(ws, caption_text)
    except Exception as exc:
        # Log with enough context to diagnose (API key issues show as 401,
        # network issues as connection errors, etc.) without crashing.
        _log.error("stream_reply failed — coaching cue skipped: %s: %s",
                   type(exc).__name__, exc)
