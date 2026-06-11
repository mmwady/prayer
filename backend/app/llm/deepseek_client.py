"""Streaming DeepSeek client.

Why the OpenAI SDK?
-------------------
DeepSeek, local vLLM, Ollama, and Together AI all expose
the **OpenAI Chat Completions** wire format. Using `openai.AsyncOpenAI` means
swapping providers is a base-URL + model-name change — no client rewrites.

Why streaming?
--------------
Latency. The TTS layer downstream consumes text *as it arrives* — we don't
wait for the full reply before starting speech synthesis. That's how we turn
a ~2s LLM response into a perceived <500ms coaching cue.
"""

from __future__ import annotations

from collections.abc import AsyncIterator, Iterable
from typing import Any

from openai import AsyncOpenAI

from ..config import get_settings


class DeepSeekClient:
    """Thin async wrapper around `openai.AsyncOpenAI`.

    Deliberately narrow: the only public method is `astream`, which yields
    text deltas. We don't expose the raw Chat Completions API because the
    graph layer should stay ignorant of provider specifics.
    """

    def __init__(self) -> None:
        settings = get_settings()
        # `AsyncOpenAI` reuses a single HTTPX connection pool; cheap to
        # instantiate once per process. We accept defaults for retries/timeouts
        # since upstream graph logic has its own cooldown/back-pressure.
        self._client = AsyncOpenAI(
            base_url=settings.deepseek_base_url,
            api_key=settings.deepseek_api_key,
        )
        self._model = settings.deepseek_model
        self._max_tokens = settings.deepseek_max_tokens
        self._temperature = settings.deepseek_temperature

    async def astream(
        self,
        messages: Iterable[dict[str, Any]],
    ) -> AsyncIterator[str]:
        """Yield token deltas for a given chat history.

        `messages` is any OpenAI-format list of `{"role": ..., "content": ...}`
        dicts. The function is an async generator so the caller can iterate it
        straight into the TTS pipeline with `async for`.

        Why not a generator function that returns `AsyncIterator[str]` more
        explicitly? The `async def` + `yield` form is the idiomatic async
        generator pattern in Python 3.11+ and is directly consumable by
        `asyncio.as_completed` / `async for` loops.
        """

        # `stream=True` flips the SDK into server-sent-events mode. Each
        # chunk is a partial `ChatCompletionChunk` with a `.choices[0].delta`
        # field whose `.content` may be None, "", or a fragment of text.
        response = await self._client.chat.completions.create(
            model=self._model,
            messages=list(messages),
            stream=True,
            max_tokens=self._max_tokens,
            temperature=self._temperature,
        )

        async for chunk in response:
            # A chunk can legitimately have no `choices` (e.g. the final
            # usage-only frame some providers append). Guard against it.
            if not chunk.choices:
                continue
            delta = chunk.choices[0].delta
            # `delta.content` is the newly generated text fragment. Empty
            # fragments (role-only first chunk, tool-call events) are skipped
            # so downstream TTS doesn't get spurious empty pulses.
            if delta and delta.content:
                yield delta.content


# Module-level singleton — reuse the connection pool across WebSocket
# sessions. Constructed lazily so that tests can patch env vars before the
# real client is built.
_client: DeepSeekClient | None = None


def get_deepseek_client() -> DeepSeekClient:
    """Return a process-wide `DeepSeekClient`."""

    global _client
    if _client is None:
        _client = DeepSeekClient()
    return _client
