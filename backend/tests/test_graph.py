"""Unit tests for the LangGraph nodes.

We exercise `classify_event`, `build_prompt`, and `update_state` without
touching the real LLM — the cooldown logic, prompt assembly, and state
bookkeeping are where the actual business rules live, and they're pure.
"""

from __future__ import annotations

import pytest

from app.graph.nodes import build_prompt, classify_event, update_state
from app.graph.state import CoachingState, fresh_state
from app.schemas import PerfectSet, PoseEvent


# ─── classify_event: cooldown behavior ─────────────────────────────────────
@pytest.mark.asyncio
async def test_classify_first_error_coaches() -> None:
    """First time an error id is seen, we must coach."""

    state: CoachingState = fresh_state()
    state["event"] = PoseEvent(
        exercise="squat", error="curved_back",
        faulty_joints=["spine_mid"], rep_count=1, t=100.0,
    )
    patch = await classify_event(state)
    assert patch["should_coach"] is True


@pytest.mark.asyncio
async def test_classify_within_cooldown_skips() -> None:
    """Same error id within cooldown window is suppressed."""

    state: CoachingState = fresh_state()
    state["last_coached_at"] = {"curved_back": 100.0}
    state["event"] = PoseEvent(
        exercise="squat", error="curved_back",
        faulty_joints=[], rep_count=2, t=101.0,  # 1s later < default 4s cooldown
    )
    patch = await classify_event(state)
    assert patch["should_coach"] is False


@pytest.mark.asyncio
async def test_classify_perfect_set_always_coaches() -> None:
    """Perfect-set events bypass cooldown — celebrate every time."""

    state: CoachingState = fresh_state()
    state["event"] = PerfectSet(exercise="squat", reps=10)
    patch = await classify_event(state)
    assert patch["should_coach"] is True


# ─── build_prompt: message shape ───────────────────────────────────────────
@pytest.mark.asyncio
async def test_build_prompt_structure() -> None:
    """Prompt must be a valid OpenAI-format message list."""

    state: CoachingState = fresh_state()
    state["should_coach"] = True
    state["event"] = PoseEvent(
        exercise="squat", error="curved_back",
        faulty_joints=["spine_mid"], rep_count=3, t=10.0,
    )
    patch = await build_prompt(state)
    msgs = patch["prompt_messages"]
    assert msgs[0]["role"] == "system"
    assert msgs[1]["role"] == "user"
    assert "squat" in msgs[1]["content"]
    assert "back" in msgs[1]["content"].lower()


@pytest.mark.asyncio
async def test_build_prompt_short_circuits_when_not_coaching() -> None:
    """If `should_coach` is false, we return an empty patch."""

    state: CoachingState = fresh_state()
    state["should_coach"] = False
    state["event"] = PoseEvent(
        exercise="squat", error="curved_back",
        faulty_joints=[], rep_count=1, t=1.0,
    )
    patch = await build_prompt(state)
    assert patch == {}


# ─── update_state: accumulates session history ─────────────────────────────
@pytest.mark.asyncio
async def test_update_state_appends_error_and_advances_cooldown() -> None:
    state: CoachingState = fresh_state()
    state["should_coach"] = True
    state["event"] = PoseEvent(
        exercise="squat", error="curved_back",
        faulty_joints=[], rep_count=5, t=42.0,
    )
    patch = await update_state(state)
    assert patch["error_history"] == ["curved_back"]
    assert patch["last_coached_at"] == {"curved_back": 42.0}
    assert patch["rep_count"] == 5
    # First event seeds the session clock.
    assert patch["session_started"] == 42.0


@pytest.mark.asyncio
async def test_update_state_does_not_bump_cooldown_when_skipped() -> None:
    """If we didn't actually coach, don't reset the cooldown timer."""

    state: CoachingState = fresh_state()
    state["last_coached_at"] = {"curved_back": 10.0}
    state["should_coach"] = False
    state["event"] = PoseEvent(
        exercise="squat", error="curved_back",
        faulty_joints=[], rep_count=6, t=11.0,
    )
    patch = await update_state(state)
    # The error is still recorded in history (observation), but the
    # cooldown isn't reset because we stayed silent.
    assert patch["error_history"] == ["curved_back"]
    assert patch["last_coached_at"]["curved_back"] == 10.0


@pytest.mark.asyncio
async def test_update_state_counts_perfect_reps() -> None:
    state: CoachingState = fresh_state()
    state["event"] = PerfectSet(exercise="squat", reps=8)
    patch = await update_state(state)
    assert patch["perfect_reps"] == 8
    assert patch["exercise"] == "squat"
