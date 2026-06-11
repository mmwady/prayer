"""Abstract TTS provider contract.

The single-most important design choice here is that `stream()` accepts an
**async iterator of text**, not a finished string.

Why?
----
The coaching pipeline is: DeepSeek (streaming) → TTS (streaming) → WebSocket.
If TTS required a completed utterance, the total time-to-first-audio would
be `LLM_total + TTS_total`. By accepting a text iterator, we let each
provider decide its own buffering policy (sentence-level for Edge-TTS,
token-level for ElevenLabs) and overlap generation with synthesis.

The contract:

* Input:  async iterator of text fragments (may arrive mid-word).
* Output: async iterator of audio bytes — format is provider-defined but
          must be self-framing (MP3 or Opus-in-Ogg), because the client
          decoder reassembles chunks without out-of-band metadata.
"""

from __future__ import annotations

import abc
from collections.abc import AsyncIterator


class TTSProvider(abc.ABC):
    """Base class every concrete TTS backend implements."""

    # Content type of the bytes emitted by `stream()`. The WebSocket layer
    # may send this as part of the first caption frame so the client knows
    # which decoder to wire up. Defaults to MP3 because both shipped
    # implementations emit MP3 in the default config.
    content_type: str = "audio/mpeg"

    @abc.abstractmethod
    async def stream(
        self,
        text_chunks: AsyncIterator[str],
    ) -> AsyncIterator[bytes]:
        """Consume partial text and yield audio bytes as they become available.

        Implementations SHOULD:
          • Accumulate input until a natural synthesis unit is ready
            (sentence for cloud TTS, phrase for low-latency providers).
          • Yield bytes in small chunks — a few KB is ideal for smooth
            playback on mobile, where large chunks cause audible gaps.
          • Finish cleanly when `text_chunks` is exhausted, flushing any
            trailing buffered text.
        """

        raise NotImplementedError
        # `yield` is unreachable but makes this function an async generator,
        # which is what type-checkers expect for AsyncIterator returns.
        yield b""  # pragma: no cover
