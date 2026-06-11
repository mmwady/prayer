"""Tracks active WebSocket sessions and their per-session graph state.

Why centralize this?
--------------------
* Observability: `/healthz` and ops dashboards can peek at
  `ConnectionManager.active_count` without threading through handlers.
* Broadcast hooks: future features (group workouts, "coach cam") will want
  to enumerate live sessions.
* Deterministic cleanup: a single place to `.close()` all sessions during
  shutdown.
"""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass, field

from fastapi import WebSocket

from ..graph.state import CoachingState, fresh_state

_log = logging.getLogger(__name__)


@dataclass
class Session:
    """Everything we track per live WebSocket.

    Deliberately flat — the graph itself is stateless and shared; only the
    `CoachingState` dict is per-session.
    """

    id: str
    ws: WebSocket
    state: CoachingState = field(default_factory=fresh_state)


class ConnectionManager:
    """Simple in-memory registry of live sessions.

    Single-process only — fine for our scale. Horizontal scaling would add
    a Redis pub/sub layer for cross-instance presence; not needed today.
    """

    def __init__(self) -> None:
        self._sessions: dict[str, Session] = {}

    async def connect(self, ws: WebSocket) -> Session:
        """Accept the upgrade and register a new `Session`."""

        await ws.accept()
        session = Session(id=uuid.uuid4().hex, ws=ws)
        self._sessions[session.id] = session
        _log.info("ws connect id=%s active=%d", session.id, len(self._sessions))
        return session

    def disconnect(self, session: Session) -> None:
        """Forget a session. Idempotent."""

        self._sessions.pop(session.id, None)
        _log.info("ws disconnect id=%s active=%d", session.id, len(self._sessions))

    @property
    def active_count(self) -> int:
        return len(self._sessions)


# Process-wide manager. Importing this module is cheap.
manager = ConnectionManager()
