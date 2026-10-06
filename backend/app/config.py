"""Runtime configuration for the Iqtadi prayer backend.

All knobs are environment-driven via `pydantic-settings`. Rationale:

* 12-factor — the same image runs in dev/staging/prod with only env differences.
* Type-safe — Pydantic validates values at startup; a missing/malformed var
  fails fast with a clear error instead of exploding mid-request.
* Single source of truth — every module imports `get_settings()` rather than
  reading `os.environ` directly.
"""

from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict
from .analysis.domain import DEFAULT_POSE_MAP


class Settings(BaseSettings):
    """Strongly typed runtime configuration.

    Fields mirror the variables documented in `.env.example`. The
    `model_config` tells Pydantic to read a `.env` file if present (useful
    outside Docker) and ignore unknown keys so an over-documented `.env`
    doesn't crash the app.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # ── Server ────────────────────────────────────────────────────────────
    host: str = "0.0.0.0"
    port: int = 8000
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR"] = "INFO"
    mosque_demo_enabled: bool = False
    mosque_demo_db: str = "data/mosque_companion.sqlite3"
    account_db: str = "data/accounts.sqlite3"
    account_public_url: str = "http://127.0.0.1:8000"
    account_mail_mode: Literal["smtp", "resend", "development"] = "smtp"
    account_mail_outbox: str = "data/account_mail_outbox"
    account_mail_from: str = "Iqtadi <no-reply@example.com>"
    account_resend_api_key: str = ""
    account_smtp_host: str = ""
    account_smtp_port: int = 587
    account_smtp_user: str = ""
    account_smtp_password: str = ""
    account_allowed_origins: list[str] = []
    account_secure_cookies: bool = True
    mosque_hold_minutes: int = Field(default=5, ge=1, le=30)
    mosque_invitation_minutes: int = Field(default=10, ge=1, le=60)
    mosque_invitation_batch: int = Field(default=3, ge=1, le=10)

    # ── Prayer guidance LLM (DeepSeek via OpenAI-compatible endpoint) ─────
    # The official API accepts exactly two model names: `deepseek-flash` and
    # `deepseek-v4-pro`. The retired alias `deepseek-chat` fails at request
    # time, so it must never be used as a default here.
    deepseek_base_url: str = Field(
        default="https://api.deepseek.com",
        description="OpenAI-compatible endpoint for DeepSeek.",
    )
    deepseek_api_key: str = Field(default="changeme", description="Bearer token.")
    deepseek_model: str = Field(default="deepseek-flash")
    # One short Arabic sentence is the target; the cap also bounds cost.
    deepseek_max_tokens: int = 160
    # Sampling only applies in non-thinking mode (see `deepseek_thinking`).
    deepseek_temperature: float = 0.5
    deepseek_timeout_s: float = 20.0
    # `deepseek-flash` enables thinking by default at effort=high. Reasoning
    # tokens would consume the whole `max_tokens` budget and can return an
    # empty `content` for a one-sentence cue, so guidance disables it unless
    # this is explicitly flipped on.
    deepseek_thinking: bool = False
    # Kill switch: when false the guidance route serves static Arabic text and
    # never calls the network.
    prayer_guidance_enabled: bool = True

    # Single-instance recorded-video MVP. Mock scenarios require explicit opt-in.
    inference_provider: Literal["mock", "real"] = "mock"
    prayer_model_bundle_dir: str = "models/prayer_action"
    # Experimental postprocessing: opt in independently; raw model is the default.
    prayer_mirror_sujood_recovery: bool = False
    prayer_ruku_geometry_gate: bool = False
    prayer_seated_probability_projection: bool = False
    prayer_sequence_normalization: bool = False
    prayer_rakah_transition_anchors: bool = False
    analysis_allow_mock: bool = False
    frame_sample_fps: float = Field(default=4, gt=0, le=10)
    analysis_max_frame_bytes: int = Field(default=200_000, gt=0)
    analysis_max_dimension: int = Field(default=960, gt=0)
    analysis_batch_frames: int = Field(default=8, ge=1, le=32)
    analysis_max_frames: int = Field(default=2400, ge=1, le=5000)
    analysis_max_duration_ms: int = Field(default=1_200_000, gt=0)
    analysis_max_request_bytes: int = Field(default=2_500_000, gt=0)
    analysis_max_jobs: int = Field(default=8, ge=1, le=32)
    analysis_workers: int = Field(default=1, ge=1, le=4)
    analysis_retention_seconds: int = Field(default=3600, ge=1)
    analysis_storage_dir: str = "data/prayer_analyses"
    analysis_live_buffer_bytes: int = Field(default=480_000_000, gt=0)
    temporal_confidence: float = Field(default=0.65, ge=0, le=1)
    temporal_min_observations: int = Field(default=1, ge=1)
    temporal_min_duration_ms: int = Field(default=0, ge=0)
    temporal_max_gap_ms: int = Field(default=1000, gt=0)
    analysis_pose_map: dict[str, str] = Field(default_factory=lambda: dict(DEFAULT_POSE_MAP))
    # With no key admin is loopback-only; reverse proxies MUST configure a key.
    prayer_admin_token: str = ""


@lru_cache
def get_settings() -> Settings:
    """Return a process-wide singleton `Settings`.

    Cached with `lru_cache` so every import site sees the same instance and
    env parsing happens exactly once per process. Tests can call
    `get_settings.cache_clear()` to pick up patched env vars.
    """

    return Settings()
