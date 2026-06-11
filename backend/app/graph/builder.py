"""Compile the coaching `StateGraph`.

The graph is a straight linear pipeline today — we still use LangGraph
(rather than plain function composition) because:

  • It gives us a declarative topology that's easy to extend later
    (e.g. branching a `safety_check` node, or looping on multi-rep
    aggregated events).
  • LangGraph's state-update merging is doing real work: each node returns
    a *partial* `CoachingState`, and the framework merges patches without
    us having to write boilerplate merge code.
  • Future upgrades (checkpointing per session for pause/resume,
    concurrency with `MessagesState`) drop in without rewrites.

Usage
-----
    graph = build_graph()
    # Per-event tick: merge current session state + event, then invoke.
    new_state = await graph.ainvoke({**current_state, "event": event})
"""

from __future__ import annotations

from langgraph.graph import END, START, StateGraph

from .nodes import build_prompt, classify_event, update_state
from .state import CoachingState


def build_graph():
    """Assemble and compile the coaching state graph.

    The graph owns *state management only* — it does NOT call the LLM.
    LLM execution happens in `stream_coaching()` (nodes.py), called by the
    WebSocket layer AFTER the graph runs. Keeping them separate means:
      • The graph is fast and side-effect-free (testable without LLM mocks).
      • The streaming path can pipe tokens → TTS → WebSocket incrementally,
        rather than collecting the full reply first.

    Topology::

          START
            │
            ▼
        classify_event   ← sets should_coach, respects cooldown
            │
            ▼
        build_prompt     ← assembles prompt_messages (no-op if should_coach=False)
            │
            ▼
        update_state     ← records error history, cooldown timestamps, rep count
            │
            ▼
           END
    """

    builder = StateGraph(CoachingState)

    builder.add_node("classify_event", classify_event)
    builder.add_node("build_prompt", build_prompt)
    builder.add_node("update_state", update_state)

    builder.add_edge(START, "classify_event")
    builder.add_edge("classify_event", "build_prompt")
    builder.add_edge("build_prompt", "update_state")
    builder.add_edge("update_state", END)

    # `compile()` returns an executable graph; cheap to do once at import
    # time and reuse across sessions since the graph itself is stateless.
    return builder.compile()
