"""LangGraph state schema for a single coaching session.

A dedicated module because the `CoachingState` TypedDict is referenced by
every node and the builder — circular-import safety is easier when it lives
alone.

Design notes
------------
* One `CoachingState` instance exists **per WebSocket connection**. Session
  scope is the right granularity: we want the coach to remember that the
  user already curved their back twice this set, but we do *not* want state
  to leak across users.
* We store raw `ClientEvent`s rather than decoded domain objects so that
  downstream nodes can inspect any field without us having to predict usage.
* `should_coach` is computed per-event, but we cache `last_coached_at` by
  error id so the cooldown logic stays simple and testable.
"""

from __future__ import annotations

from typing import TypedDict

from ..schemas import ClientEvent


class CoachingState(TypedDict, total=False):
    """Mutable per-session state carried through the LangGraph run.

    `total=False` — every field is optional so the graph can partially
    update the state without having to echo back values it doesn't change.

    Fields:
      event            — the event being processed on this graph tick.
      exercise         — the exercise the user is currently doing.
      rep_count        — latest rep count reported by the client.
      perfect_reps     — count of reps that arrived clean (no pose_event).
      error_history    — chronological list of error ids seen in this session.
      last_coached_at  — map of error id → unix-time of last correction.
                         Drives the cooldown in `classify_event`.
      should_coach     — set by `classify_event`; gates downstream nodes.
      prompt_messages  — OpenAI-format chat history built by `build_prompt`.
      session_started  — client-side timestamp of first event.
      language         — preferred language for LLM coaching ('en' or 'ar').
    """

    event: ClientEvent
    exercise: str
    rep_count: int
    perfect_reps: int
    error_history: list[str]
    last_coached_at: dict[str, float]
    should_coach: bool
    prompt_messages: list[dict[str, str]]
    session_started: float
    language: str


def fresh_state() -> CoachingState:
    """Factory for a pristine state at connection-open.

    Kept as a function (not a constant) because TypedDict instances are
    plain dicts — a shared constant would leak mutations across sessions.
    """

    return CoachingState(
        rep_count=0,
        perfect_reps=0,
        error_history=[],
        last_coached_at={},
    )
