"""Coaching backend package.

Intentionally empty — all concrete symbols live in submodules so tests can
import narrow surfaces (e.g. `from app.graph.state import CoachingState`)
without triggering heavy import side-effects (LLM clients, TTS providers).
"""
