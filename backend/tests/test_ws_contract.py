"""Round-trip tests for the client/server WebSocket schema.

These are cheap guards that catch accidental contract drift — if someone
renames a field here, the Flutter side must change too. Running this test
on a Dart-side JSON fixture (via `cd mobile && flutter test`) would close
the loop, but that's future work.
"""

from __future__ import annotations

import json

import pytest
from pydantic import TypeAdapter, ValidationError

from app.schemas import (
    ClientEvent,
    CoachingCaption,
    PerfectSet,
    PoseEvent,
    SessionEnd,
    SessionSummary,
)


_ADAPTER: TypeAdapter[ClientEvent] = TypeAdapter(ClientEvent)


def test_pose_event_round_trip() -> None:
    raw = {
        "type": "pose_event",
        "exercise": "squat",
        "error": "curved_back",
        "faulty_joints": ["spine_mid"],
        "rep_count": 7,
        "t": 1713532100.23,
    }
    event = _ADAPTER.validate_python(raw)
    assert isinstance(event, PoseEvent)
    # Serializing back should produce the same payload (ignoring key order).
    assert json.loads(event.model_dump_json()) == raw


def test_perfect_set_round_trip() -> None:
    raw = {"type": "perfect_set", "exercise": "pushup", "reps": 12}
    event = _ADAPTER.validate_python(raw)
    assert isinstance(event, PerfectSet)
    assert event.reps == 12


def test_session_end_round_trip() -> None:
    raw = {"type": "session_end"}
    event = _ADAPTER.validate_python(raw)
    assert isinstance(event, SessionEnd)


def test_unknown_type_rejected() -> None:
    """Discriminator must reject unknown event types."""

    with pytest.raises(ValidationError):
        _ADAPTER.validate_python({"type": "totally_made_up"})


def test_pose_event_rep_count_non_negative() -> None:
    """`rep_count` can be 0 (first frame) but not negative."""

    _ADAPTER.validate_python({
        "type": "pose_event",
        "exercise": "squat",
        "error": "curved_back",
        "faulty_joints": [],
        "rep_count": 0,
        "t": 0.0,
    })
    with pytest.raises(ValidationError):
        _ADAPTER.validate_python({
            "type": "pose_event",
            "exercise": "squat",
            "error": "curved_back",
            "faulty_joints": [],
            "rep_count": -1,
            "t": 0.0,
        })


def test_caption_and_summary_serialize() -> None:
    """Downstream payloads serialize to stable JSON shapes."""

    assert json.loads(CoachingCaption(text="Chest up!").model_dump_json()) == {
        "text": "Chest up!",
    }
    summary = SessionSummary(
        total_reps=10,
        perfect_reps=7,
        errors={"curved_back": 3},
        duration_s=42.0,
    )
    data = json.loads(summary.model_dump_json())
    assert data == {
        "total_reps": 10,
        "perfect_reps": 7,
        "errors": {"curved_back": 3},
        "duration_s": 42.0,
    }
