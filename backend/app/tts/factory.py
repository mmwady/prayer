"""Select the active `TTSProvider` from configuration.

Keeping provider choice in one place means everywhere else in the codebase
just calls `get_tts()` and stays ignorant of which engine is in play. Swaps
are an env-var flip (no code change).
"""

from __future__ import annotations

from functools import lru_cache

from ..config import get_settings
from .base import TTSProvider
from .edge_tts_provider import EdgeTTS
from .elevenlabs_provider import ElevenLabsTTS


@lru_cache
def get_tts(lang: str = "en") -> TTSProvider:
    """Build (once per language) and return the configured TTS provider.

    The result is cached by `lang` so that each locale gets its own provider
    instance with the correct voice. Without this, an Arabic session would
    reuse the English-voice provider and receive no audio (NoAudioReceived).

    `lru_cache` is keyed on all args, so `get_tts("en")` and `get_tts("ar")`
    are two independent singletons — no per-request overhead after the first
    call for each language.
    """

    s = get_settings()
    provider = s.tts_provider
    if provider == "edge":
        voice = s.tts_voice_ar if lang == "ar" else s.tts_voice
        return EdgeTTS(voice=voice)
    if provider == "elevenlabs":
        # ElevenLabs voices are multilingual by model; the same voice_id
        # handles Arabic. If you ever want a different voice per locale,
        # add an `elevenlabs_voice_ar` setting analogous to `tts_voice_ar`.
        return ElevenLabsTTS()
    raise ValueError(f"Unknown TTS_PROVIDER={provider!r}")
