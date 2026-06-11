"""ElevenLabs streaming TTS provider.

ElevenLabs exposes a bidirectional WebSocket — you push text fragments and
receive base64-encoded MP3 frames back in near real-time. This maps perfectly
to our per-token streaming model: unlike Edge-TTS, we do *not* need to buffer
by sentence, because ElevenLabs accepts partials and produces audio
continuously.

Protocol recap (docs: https://elevenlabs.io/docs/api-reference/websockets):
  1. Open WS → send an "init" message with `voice_settings` + API key.
  2. Stream `{"text": "...", "try_trigger_generation": true}` messages.
  3. Receive `{"audio": "<base64>", "isFinal": bool}` events.
  4. Send `{"text": ""}` to flush and close.
"""

from __future__ import annotations

import asyncio
import base64
import contextlib
import json
import logging
from collections.abc import AsyncIterator

import websockets

from ..config import get_settings
from .base import TTSProvider

_log = logging.getLogger(__name__)

_WS_URL_TEMPLATE = (
    "wss://api.elevenlabs.io/v1/text-to-speech/{voice_id}/stream-input"
    "?model_id={model}&output_format=mp3_44100_128"
)


class ElevenLabsTTS(TTSProvider):
    """Low-latency ElevenLabs streaming TTS."""

    content_type = "audio/mpeg"

    def __init__(self) -> None:
        s = get_settings()
        if not s.elevenlabs_api_key:
            raise RuntimeError(
                "TTS_PROVIDER=elevenlabs but ELEVENLABS_API_KEY is empty."
            )
        self._voice = s.tts_voice
        self._model = s.elevenlabs_model
        self._api_key = s.elevenlabs_api_key

    async def stream(
        self,
        text_chunks: AsyncIterator[str],
    ) -> AsyncIterator[bytes]:
        """Fan text into the ElevenLabs WS, fan audio back out.

        We run two concurrent tasks:
          • `_pump_text` reads from the caller's iterator and pushes to WS.
          • the main coroutine reads WS frames and yields audio bytes.

        Coupling them through a single WebSocket means audio starts coming
        back before the caller has finished sending text.
        """

        url = _WS_URL_TEMPLATE.format(voice_id=self._voice, model=self._model)
        # The API key is accepted either as a header (preferred for WS).
        async with websockets.connect(
            url,
            additional_headers={"xi-api-key": self._api_key},
            max_size=None,  # audio frames can be large; don't cap.
        ) as ws:
            # ── 1. Send the initial config message. ───────────────────────
            # `voice_settings` are mandatory on the first frame. The special
            # `text=" "` is documented as the "open session" sentinel.
            await ws.send(json.dumps({
                "text": " ",
                "voice_settings": {"stability": 0.5, "similarity_boost": 0.8},
                # The flush interval tells ElevenLabs how aggressively to
                # generate — lower values = lower latency at the cost of
                # prosody. 120ms is a good coaching-app sweet spot.
                "generation_config": {"chunk_length_schedule": [50]},
            }))

            pump = asyncio.create_task(self._pump_text(ws, text_chunks))
            try:
                async for raw in ws:
                    # ElevenLabs always sends JSON text frames, even though
                    # the audio inside is base64-encoded bytes.
                    msg = json.loads(raw)
                    audio_b64 = msg.get("audio")
                    if audio_b64:
                        yield base64.b64decode(audio_b64)
                    if msg.get("isFinal"):
                        break
            finally:
                # Make absolutely sure the pump task is cancelled even if the
                # caller stops iterating early (e.g. client disconnected).
                pump.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await pump

    @staticmethod
    async def _pump_text(ws, text_chunks: AsyncIterator[str]) -> None:
        """Forward each text fragment as its own WS message, then flush."""

        try:
            async for fragment in text_chunks:
                if not fragment:
                    continue
                await ws.send(json.dumps({
                    "text": fragment,
                    # Tells ElevenLabs to start synthesis asap rather than
                    # wait for more text — this is what makes it feel live.
                    "try_trigger_generation": True,
                }))
        finally:
            # Empty text signals "no more input, finish what you've got".
            try:
                await ws.send(json.dumps({"text": ""}))
            except Exception:  # pragma: no cover — WS may already be closed.
                _log.debug("ElevenLabs flush send failed; connection likely closed.")


