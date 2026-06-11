"""Structured logging setup.

Kept deliberately small. In production you'd pipe these records to a
log aggregator (Loki, CloudWatch, …); here we just ensure:

* Consistent format across uvicorn + application loggers (no duplicate
  handlers, no mismatched timestamps).
* Log level is env-driven via `Settings.log_level`.
"""

from __future__ import annotations

import logging
import sys

from .config import get_settings

_CONFIGURED = False


def configure_logging() -> None:
    """Idempotent root-logger setup.

    We intentionally call `logging.basicConfig` only once per process — a
    second call is a no-op, but we also guard with a module-level flag to
    avoid duplicate handler attachment under reload.
    """

    global _CONFIGURED
    if _CONFIGURED:
        return

    settings = get_settings()

    logging.basicConfig(
        level=settings.log_level,
        stream=sys.stdout,
        # ISO-ish timestamp first so logs sort lexicographically by time.
        format="%(asctime)s %(levelname)-8s %(name)s: %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )
    # Quiet the extremely chatty access log at INFO; WebSocket traffic flips
    # the default HTTP log to noise. uvicorn keeps its own `uvicorn.error`
    # channel for real problems.
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)

    _CONFIGURED = True
