"""Build an end-of-session `SessionSummary` from the graph state.

Isolated into its own module so the WebSocket layer doesn't grow yet more
responsibilities, and so tests can hit a pure function without touching
networking.
"""

from __future__ import annotations

import time
from collections import Counter

from ..graph.state import CoachingState
from ..schemas import SessionSummary


def build_summary(state: CoachingState, end_time: float | None = None) -> SessionSummary:
    """Derive aggregate stats from a finished session's state.

    `end_time` defaults to `time.time()` — injectable for deterministic
    tests. Duration is computed against `session_started`, which was seeded
    from the first client event so it's phone-clock-relative.
    """

    end_time = end_time if end_time is not None else time.time()
    started = state.get("session_started", end_time)

    # `error_history` is a chronological list of error ids; `Counter` gives
    # us the histogram we ship to the dashboard in O(n).
    errors = Counter(state.get("error_history", []))

    total_errors = sum(errors.values())
    rep_count = state.get("rep_count", 0)
    perfect = state.get("perfect_reps", 0)

    # `total_reps` is the max of rep_count and perfect_reps so a session that
    # was *only* perfect sets (never sending pose_events) still reports reps.
    total_reps = max(rep_count, perfect, total_errors)

    return SessionSummary(
        total_reps=total_reps,
        perfect_reps=perfect,
        errors=dict(errors),
        duration_s=max(0.0, end_time - started),
    )
