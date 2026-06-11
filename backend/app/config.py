"""Runtime configuration.

All knobs are environment-driven via `pydantic-settings`. Rationale:

* 12-factor — the same image runs in dev/staging/prod with only env differences.
* Type-safe — Pydantic validates values at startup; a missing/malformed var
  fails fast with a clear error instead of exploding mid-request.
* Single source of truth — every module imports `get_settings()` rather than
  reading `os.environ` directly, which keeps provider swaps (DeepSeek endpoint,
  TTS backend) a one-line change.
"""

from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


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

    # ── LLM (DeepSeek via OpenAI-compatible endpoint) ─────────────────────
    # Using the OpenAI client means we're provider-agnostic. Changing
    # DEEPSEEK_BASE_URL points the same code at DeepSeek, vLLM, Ollama, etc.
    deepseek_base_url: str = Field(
        default="https://api.deepseek.com/v1",
        description="OpenAI-compatible endpoint for DeepSeek.",
    )
    deepseek_api_key: str = Field(default="changeme", description="Bearer token.")
    deepseek_model: str = Field(default="deepseek-chat")
    # Coaching replies are intentionally short — a full sentence or two.
    # Capping max_tokens lowers latency AND cost.
    deepseek_max_tokens: int = 60
    deepseek_temperature: float = 0.5

    # ── TTS ───────────────────────────────────────────────────────────────
    # `edge` is the zero-config default; `elevenlabs` is the premium option.
    tts_provider: Literal["edge", "elevenlabs"] = "edge"
    tts_voice: str = "en-US-GuyNeural"
    # Arabic-specific voice. Edge-TTS voices are locale-bound; passing an
    # English voice with Arabic text returns no audio (NoAudioReceived error).
    tts_voice_ar: str = "ar-SA-HamedNeural"
    elevenlabs_api_key: str = ""
    elevenlabs_model: str = "eleven_turbo_v2_5"

    # ── Coaching behavior ─────────────────────────────────────────────────
    # Minimum seconds between two consecutive corrections for the SAME error
    # within one session. Prevents the coach nagging every frame while a
    # fault persists across a rep.
    coaching_cooldown_s: float = 4.0


@lru_cache
def get_settings() -> Settings:
    """Return a process-wide singleton `Settings`.

    Cached with `lru_cache` so every import site sees the same instance and
    env parsing happens exactly once per process. Tests can call
    `get_settings.cache_clear()` to pick up patched env vars.
    """

    return Settings()
