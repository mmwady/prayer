"""FastAPI application entrypoint.

Kept intentionally thin — the app factory does three things:

  1. Configure logging.
  2. Mount the `/ws/coach` WebSocket.
  3. Expose `/healthz` for the Docker healthcheck.

Everything else lives in feature modules. This keeps `main.py` stable
(rarely edited) and the actual interesting changes in testable packages.
"""

from __future__ import annotations

from fastapi import FastAPI, WebSocket
from fastapi.middleware.cors import CORSMiddleware

from .config import get_settings
from .logging_config import configure_logging
from .websocket.connection_manager import manager
from .websocket.endpoint import coach_endpoint
from .admin.router import admin_router
from .api.v1.router import v1_router


def create_app() -> FastAPI:
    """Application factory — lets tests construct isolated app instances."""

    configure_logging()
    settings = get_settings()

    app = FastAPI(
        title="AI Fitness Coaching Backend",
        version="0.1.0",
        # OpenAPI docs enabled in dev for poking; in prod you'd gate this.
        docs_url="/docs" if settings.log_level == "DEBUG" else None,
    )

    # Allow Flutter Web (served from localhost on any port during dev) to call
    # this API. The browser enforces same-origin policy, so without this every
    # fetch from the Flutter app returns "Failed to fetch" with no other details.
    # In production, replace "*" with your actual deployed frontend origin.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],       # Tighten to your domain in production
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.get("/healthz")
    async def healthz() -> dict[str, object]:
        """Cheap liveness probe consumed by Docker / load balancers.

        Reports the live session count — useful during a rolling deploy to
        decide whether it's safe to drain this instance.
        """

        return {"status": "ok", "active_sessions": manager.active_count}

    @app.websocket("/ws/coach")
    async def ws_coach(websocket: WebSocket, lang: str = "en") -> None:
        """Thin delegation to the real handler so routing stays readable."""

        await coach_endpoint(websocket, lang)

    # Register Admin and App API Routers
    app.include_router(admin_router)
    app.include_router(v1_router)

    return app


# Uvicorn looks for `app` by default (`app.main:app` in the Dockerfile).
app = create_app()
