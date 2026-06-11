"""Edge-TTS provider — the zero-config default.

`edge-tts` talks to Microsoft's public Edge browser TTS endpoint. It's free,
requires no API key, and supports streaming MP3. Ideal for local dev and
low-cost deployments.

Buffering strategy
------------------
Edge-TTS works best when handed a complete utterance — it's a one-shot
WebSocket session per call, not token-level streaming. So we buffer incoming
text until a sentence boundary, then synthesize that sentence, then start the
next buffer. This gives us **per-sentence** pipelining, which is usually
enough because coaching replies are one or two short sentences.
"""

from __future__ import annotations

import logging
import re
from collections.abc import AsyncIterator

import edge_tts

from ..config import get_settings
from .base import TTSProvider

_log = logging.getLogger(__name__)

# Matches sentence-terminating punctuation plus trailing quote/paren. Anything
# ending in `.`, `!`, `?`, or newline counts. We also split on `;` since
# coaching replies sometimes chain two phrases.
_SENTENCE_END = re.compile(r"[.!?;\n]+[\"')]*\s*")


class EdgeTTS(TTSProvider):
    """Microsoft Edge voices via the public streaming endpoint."""

    content_type = "audio/mpeg"

    def __init__(self, voice: str | None = None) -> None:
        # If no voice is supplied fall back to the configured default so that
        # direct instantiation in tests still works without extra args.
        self._voice = voice or get_settings().tts_voice

    async def stream(
        self,
        text_chunks: AsyncIterator[str],
    ) -> AsyncIterator[bytes]:
        """Buffer text into sentences, synthesize each, stream MP3 out."""

        buffer = ""
        async for fragment in text_chunks:
            buffer += fragment
            # Drain every complete sentence currently in the buffer.
            async for mp3 in self._drain_sentences(buffer):
                yield mp3
            # Keep only the trailing partial sentence (if any) in the buffer.
            buffer = self._tail_after_last_sentence(buffer)

        # Flush the final fragment so we don't drop a sentence that lacked
        # terminal punctuation (e.g. DeepSeek cut off mid-clause at max_tokens).
        if buffer.strip():
            async for mp3 in self._synthesize(buffer):
                yield mp3

    # ── internals ────────────────────────────────────────────────────────

    async def _drain_sentences(self, buffer: str) -> AsyncIterator[bytes]:
        """Yield audio for every complete sentence found in `buffer`.

        We match all sentence-ends and synthesize the span from the last
        emitted index up to and including each terminator. This keeps
        prosody natural (full sentences) while still pipelining.
        """

        last = 0
        for match in _SENTENCE_END.finditer(buffer):
            sentence = buffer[last:match.end()].strip()
            last = match.end()
            if sentence:
                async for mp3 in self._synthesize(sentence):
                    yield mp3

    @staticmethod
    def _tail_after_last_sentence(buffer: str) -> str:
        """Return the portion of `buffer` after the final sentence terminator."""

        last_end = 0
        for match in _SENTENCE_END.finditer(buffer):
            last_end = match.end()
        return buffer[last_end:]

    async def _synthesize(self, text: str) -> AsyncIterator[bytes]:
        """Yield MP3 chunks for a single sentence via edge-tts."""

        _log.debug("edge-tts synth: %r", text)
        communicate = edge_tts.Communicate(text, self._voice)
        # `stream()` yields dicts with type='audio'|'WordBoundary'|'SentenceBoundary'.
        # We care only about the raw audio bytes.
        async for event in communicate.stream():
            if event.get("type") == "audio":
                data = event.get("data")
                if data:
                    yield data
