"""DeepSeek client used to generate Arabic prayer guidance.

Why the OpenAI SDK?
-------------------
The DeepSeek API speaks the OpenAI Chat Completions wire format, so
`openai.AsyncOpenAI` covers it — and any compatible endpoint (vLLM, Ollama,
Together) — with only a base-URL and model-name change.

Thinking mode
-------------
`deepseek-flash` has thinking enabled by default at effort=high. Its
chain-of-thought is billed as output and, with a small `max_tokens`, can
consume the entire budget and leave `content` empty. A prayer cue is one short
sentence, so thinking is disabled by default (`Settings.deepseek_thinking`).
Note that thinking mode ignores `temperature`; the parameter is only
meaningful in non-thinking mode.
"""

from __future__ import annotations

from collections.abc import Iterable
from typing import Any

from openai import AsyncOpenAI

from ..config import get_settings

# Placeholder values that mean "no real credential was supplied".
_UNCONFIGURED_KEYS = {"", "changeme"}


class LLMNotConfigured(RuntimeError):
    """Raised when the client has no usable API key.

    Callers treat this as a soft failure and fall back to static content, so
    the absence of a key degrades the feature instead of breaking the route.
    """


class DeepSeekClient:
    """Thin async wrapper around `openai.AsyncOpenAI`.

    Deliberately narrow: the only public method is `complete`, which returns
    the model's reply text. The graph/prompt layer and the route stay ignorant
    of provider specifics.
    """

    def __init__(self) -> None:
        settings = get_settings()
        # `AsyncOpenAI` reuses a single HTTPX connection pool; cheap to
        # instantiate once per process.
        self._client = AsyncOpenAI(
            base_url=settings.deepseek_base_url,
            api_key=settings.deepseek_api_key,
            timeout=settings.deepseek_timeout_s,
        )
        self._api_key = settings.deepseek_api_key
        self._model = settings.deepseek_model
        self._max_tokens = settings.deepseek_max_tokens
        self._temperature = settings.deepseek_temperature
        self._thinking = settings.deepseek_thinking

    @property
    def model(self) -> str:
        """The configured model name, reported back to clients."""

        return self._model

    def is_configured(self) -> bool:
        """True when a real-looking credential is present."""

        return self._api_key.strip().lower() not in _UNCONFIGURED_KEYS

    async def complete(self, messages: Iterable[dict[str, Any]]) -> str:
        """Return the model's reply text for an OpenAI-format chat history.

        `messages` is a list of `{"role": ..., "content": ...}` dicts. The
        return value is stripped; an empty string means the model produced no
        usable content and the caller should fall back to static text.
        """

        if not self.is_configured():
            raise LLMNotConfigured(
                "DEEPSEEK_API_KEY is not set; prayer guidance falls back to static text."
            )

        response = await self._client.chat.completions.create(
            model=self._model,
            messages=list(messages),
            max_tokens=self._max_tokens,
            temperature=self._temperature,
            # `thinking` is a DeepSeek extension, so it must travel in
            # `extra_body` rather than as a named SDK argument.
            extra_body={
                "thinking": {"type": "enabled" if self._thinking else "disabled"}
            },
        )

        # A response can legitimately carry no choices (e.g. some providers
        # append a usage-only frame). Guard against it.
        if not response.choices:
            return ""

        return (response.choices[0].message.content or "").strip()


# Module-level singleton — reuse the connection pool across requests.
# Constructed lazily so tests can patch settings before the real client exists.
_client: DeepSeekClient | None = None


def get_deepseek_client() -> DeepSeekClient:
    """Return a process-wide `DeepSeekClient`."""

    global _client
    if _client is None:
        _client = DeepSeekClient()
    return _client


def reset_deepseek_client() -> None:
    """Drop the cached client so the next call rebuilds it from current settings."""

    global _client
    _client = None
