"""Local-only account acceptance server; production uses app.main:app.

Run from backend/ with ACCOUNT_* settings and a separate demo SQLite file.
Email verification remains mandatory in every mail mode. Configure Resend or
SMTP for real delivery; development mode writes an explicitly local outbox.
"""

import mimetypes
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles

from app.accounts.api import router
from app.accounts.boundary import AccountBoundary
from app.accounts.community import router as account_spaces_router
from app.config import get_settings

s = get_settings()
# Windows may register .mjs as text/plain; ONNX Runtime imports require JS MIME.
mimetypes.add_type("text/javascript", ".mjs")
mimetypes.add_type("application/wasm", ".wasm")
app = FastAPI()
app.add_middleware(AccountBoundary)
app.add_middleware(
    CORSMiddleware,
    allow_origins=s.account_allowed_origins,
    allow_credentials=True,
    allow_headers=["*"],
    allow_methods=["*"],
)


@app.middleware("http")
async def canonical_https(request: Request, call_next):
    """Move direct LAN browsers to the configured HTTPS camera origin."""

    public = s.account_public_url.rstrip("/")
    forwarded = request.headers.get("x-forwarded-proto", "").casefold()
    if public.startswith("https://") and request.url.scheme != "https" and forwarded != "https":
        suffix = request.url.path
        if request.url.query:
            suffix += "?" + request.url.query
        return RedirectResponse(public + suffix, status_code=307)
    return await call_next(request)


app.include_router(router)
app.include_router(account_spaces_router)
app.mount(
    "/",
    StaticFiles(
        directory=Path(__file__).resolve().parents[2] / "mobile/coaching/build/web", html=True
    ),
)
