"""TTS adapter package.

Public surface: `get_tts()` from `factory.py` — returns an abstract
`TTSProvider` (`base.py`). Concrete providers (`edge_tts_provider.py`,
`elevenlabs_provider.py`) are implementation details.
"""
