"""Local-only account acceptance server; production uses app.main:app.

Run from backend/ with ACCOUNT_* settings and a separate demo SQLite file.
No email/authentication bypass is added; development mail is a local .eml outbox.
"""

from pathlib import Path
import mimetypes
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from app.accounts.api import router
from app.accounts.boundary import AccountBoundary
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
app.include_router(router)
app.mount(
    "/",
    StaticFiles(
        directory=Path(__file__).resolve().parents[2] / "mobile/coaching/build/web", html=True
    ),
)
