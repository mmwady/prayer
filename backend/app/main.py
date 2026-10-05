"""FastAPI application entrypoint for the Iqtadi prayer backend.

The app factory does three things:

  1. Configure logging.
  2. Mount the prayer reference routes (authoring + active reference delivery).
  3. Expose `/healthz` for the Docker healthcheck.

Recorded-video jobs own inference, temporal processing, sequence analysis and
temporary evidence. Reference preparation and optional legacy guidance remain
separate. Consented camera sessions stream JPEGs over a dedicated WebSocket;
their final reports share the recorded-video analysis engine.
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .admin.prayer_references import router as prayer_reference_router
from .config import get_settings
from .logging_config import configure_logging
from .prayer.guidance import router as prayer_guidance_router
from .analysis.api import router as analysis_router
from .analysis.jobs import JobManager
from .analysis.live import LiveManager, router as live_router
from .analysis.security import AnalysisBoundary
from .mosque.api import router as mosque_router
from .accounts.api import router as accounts_router
from .accounts.boundary import AccountBoundary


def create_app() -> FastAPI:
    """Application factory — lets tests construct isolated app instances."""

    configure_logging()
    settings = get_settings()

    @asynccontextmanager
    async def lifespan(application):
        jobs = JobManager(settings)
        application.state.analysis_manager = jobs
        await jobs.start()
        live = LiveManager(jobs)
        application.state.live_manager = live
        await live.start()
        try:
            yield
        finally:
            await live.close()
            await jobs.close()

    app = FastAPI(
        title="Iqtadi Prayer Backend",
        version="0.2.0",
        # OpenAPI docs enabled in dev for poking; in prod you'd gate this.
        docs_url="/docs" if settings.log_level == "DEBUG" else None,
        lifespan=lifespan,
    )

    # Allow Flutter Web (served from localhost on any port during dev) to call
    # this API. The browser enforces same-origin policy, so without this every
    # fetch from the Flutter app returns "Failed to fetch" with no other details.
    # In production, replace "*" with your actual deployed frontend origin.
    app.add_middleware(AnalysisBoundary, settings=settings)
    app.add_middleware(AccountBoundary)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.account_allowed_origins or ["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.get("/healthz")
    async def healthz() -> dict[str, object]:
        """Cheap liveness probe consumed by Docker / load balancers."""

        return {
            "status": "ok",
            "guidance_enabled": settings.prayer_guidance_enabled,
        }

    app.include_router(prayer_reference_router)
    app.include_router(prayer_guidance_router)
    app.include_router(analysis_router)
    app.include_router(live_router)
    app.include_router(mosque_router)
    app.include_router(accounts_router)

    return app


# Uvicorn looks for `app` by default (`app.main:app` in the Dockerfile).
app = create_app()
