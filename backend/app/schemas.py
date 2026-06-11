"""Wire-format schemas for the `/ws/coach` WebSocket.

This module is the **single source of truth for the client/server contract**.
The Flutter side mirrors every field (see `mobile/lib/models/`). Keeping the
schemas in one place means adding a new `error` kind, joint name, or telemetry
field is a two-file change (here + the Dart mirror) instead of ten.

Frame format summary:

* **Upstream (client → server)** — JSON text frames, one event per frame.
  Discriminated on `type`: `pose_event`, `perfect_set`, `session_end`.
* **Downstream (server → client)** — *binary* frames with a 1-byte prefix:
      0x01 ` json  ` — caption / meta       (e.g. `{"text": "Chest up!"}`)
      0x02 ` bytes ` — audio chunk           (MP3 or Opus; provider-dependent)
      0x03 ` json  ` — session summary       (final frame before close)
  Using binary framing with a kind-byte avoids the ambiguity of mixing text
  and binary WebSocket frames and preserves order — which matters because a
  caption should appear just before or alongside its audio.
"""

from __future__ import annotations

from enum import IntEnum
from typing import Annotated, Literal

from pydantic import BaseModel, Field


# ─── Downstream binary-frame kinds ──────────────────────────────────────────
class FrameKind(IntEnum):
    """1-byte tag prepended to every downstream binary frame."""

    CAPTION = 0x01  # UTF-8 JSON payload, e.g. {"text": "Keep your back straight"}
    AUDIO = 0x02    # Raw audio bytes (MP3 from edge-tts, MP3 from ElevenLabs)
    SUMMARY = 0x03  # UTF-8 JSON payload — a SessionSummary


# ─── Upstream events ────────────────────────────────────────────────────────
class PoseEvent(BaseModel):
    """A lightweight form-fault signal emitted by the Flutter form analyzer.

    The device NEVER streams pixels. Only this ~100-byte JSON payload goes
    upstream when a rule fires (e.g. knee travels past the toe in a squat).
    That's the whole trick behind the "zero-latency" feel — we replace video
    uplink with a structured domain event.
    """

    type: Literal["pose_event"] = "pose_event"
    exercise: str = Field(..., description="e.g. 'squat', 'pushup'.")
    # Short machine-readable fault id; the prompt template expands it into
    # natural language. Keeping it symbolic means the LLM prompt stays stable
    # even as client telemetry evolves.
    error: str = Field(..., description="Machine-readable fault id.")
    # Names of joints at fault — used by the AR overlay to color them red.
    # Server only forwards them back if the coach wants to reference a body
    # part explicitly; otherwise they're informational.
    faulty_joints: list[str] = Field(default_factory=list)
    rep_count: int = Field(..., ge=0)
    # Client-side unix timestamp (seconds). Used for cooldown math on the
    # server so we can rate-limit repeated corrections independently of the
    # server clock, which may drift from the phone.
    t: float


class PerfectSet(BaseModel):
    """Special payload sent when the client completes a set with zero faults.

    Used purely to trigger an enthusiastic coaching reply — no state change
    on the server beyond logging the streak.
    """

    type: Literal["perfect_set"] = "perfect_set"
    exercise: str
    reps: int = Field(..., gt=0)


class SessionEnd(BaseModel):
    """Signals the workout is over so the server can emit the summary frame."""

    type: Literal["session_end"] = "session_end"


# Discriminated union of all legal upstream events. Using `Annotated` +
# `Field(discriminator=...)` tells Pydantic to dispatch on the `type` field
# deterministically (no smart-coercion ambiguity). `TypeAdapter(ClientEvent)`
# on the server reads JSON and picks the right concrete model.
ClientEvent = Annotated[
    PoseEvent | PerfectSet | SessionEnd,
    Field(discriminator="type"),
]


# ─── Downstream payloads (JSON bodies inside binary frames) ─────────────────
class CoachingCaption(BaseModel):
    """Text caption that accompanies a TTS response.

    Sent AFTER the audio stream completes (we only know the final text once
    the LLM finishes emitting tokens). The Flutter UI keeps the most-recent
    caption on screen for a second or two — the audio is the primary channel,
    the caption is a low-distraction transcript for accessibility.
    """

    text: str


class SessionSummary(BaseModel):
    """End-of-session aggregate shipped to the client's dashboard.

    Fields chosen to be immediately graphable: total reps for volume,
    perfect-rep ratio for form quality, error histogram for targeted
    feedback, duration for pacing.
    """

    total_reps: int
    perfect_reps: int
    # Map of error id → occurrence count, e.g. {"curved_back": 3}.
    errors: dict[str, int]
    duration_s: float
