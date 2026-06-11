from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from fastapi import APIRouter
from fastapi.responses import JSONResponse

v1_router = APIRouter(prefix="/api/v1", tags=["api_v1"])

# Uvicorn is started from the backend root in this project, so this resolves to:
# backend/data/templates and backend/data/exercise_rules
DATA_DIR = Path("data")
TEMPLATES_DIR = DATA_DIR / "templates"
EXERCISE_RULES_DIR = DATA_DIR / "exercise_rules"


def _read_json_dir(directory: Path) -> dict[str, Any]:
    payloads: dict[str, Any] = {}

    if not directory.exists():
        return payloads

    for json_filename in sorted(os.listdir(directory)):
        if not json_filename.endswith(".json"):
            continue

        name = json_filename.replace(".json", "")
        path = directory / json_filename

        try:
            with open(path, "r", encoding="utf-8") as f:
                payloads[name] = json.load(f)
        except Exception as exc:  # pragma: no cover - best-effort loading
            print(f"Error reading {path}: {exc}")

    return payloads


def _read_templates() -> dict[str, Any]:
    """Read all JSON template files into a filename-keyed dictionary."""
    return _read_json_dir(TEMPLATES_DIR)


def _read_exercise_rules() -> dict[str, Any]:
    """Read all exercise rule files into a filename-keyed dictionary."""
    return _read_json_dir(EXERCISE_RULES_DIR)


def _extract_frame_points(frame: Any) -> list[dict[str, Any]] | None:
    """Normalize either old raw frames or richer metadata frames."""

    if isinstance(frame, list):
        return frame

    if isinstance(frame, dict):
        points = frame.get("keypoints") or frame.get("points")
        if isinstance(points, list):
            return points

    return None


def _flatten_frames(template: Any) -> list[list[dict[str, Any]]]:
    """Convert a template payload into Flutter-compatible frame lists."""

    if isinstance(template, list):
        frames = template
    elif isinstance(template, dict) and isinstance(template.get("frames"), list):
        frames = template["frames"]
    else:
        return []

    flattened: list[list[dict[str, Any]]] = []
    for frame in frames:
        points = _extract_frame_points(frame)
        if points and len(points) >= 5:
            flattened.append(points)

    return flattened


def _with_mobile_compatibility_templates(templates: dict[str, Any]) -> dict[str, Any]:
    """Expose multi-view push-up templates under the existing `pushup` key."""

    compatible = dict(templates)

    pushup_variant_frames: list[list[dict[str, Any]]] = []
    for name, data in sorted(templates.items()):
        if name.startswith("pushup_"):
            pushup_variant_frames.extend(_flatten_frames(data))

    if pushup_variant_frames:
        compatible["pushup"] = pushup_variant_frames

    return compatible


@v1_router.get("/templates")
async def get_all_templates():
    """Serve all exercise templates to the mobile app."""

    return JSONResponse(
        content={
            "version": 2,
            "templates": _with_mobile_compatibility_templates(_read_templates()),
        }
    )


@v1_router.get("/templates/{exercise}")
async def get_exercise_templates(exercise: str):
    """Return all raw templates for one exercise grouped together."""

    normalized = exercise.lower().replace("-", "_")
    templates = _read_templates()
    grouped = {
        name: data
        for name, data in templates.items()
        if name == normalized or name.startswith(f"{normalized}_")
    }

    return JSONResponse(
        content={
            "version": 2,
            "exercise": normalized,
            "templates": grouped,
            "mobile_compatible_frames": _flatten_frames(grouped.get(normalized))
            + [
                frame
                for name, data in sorted(grouped.items())
                if name.startswith(f"{normalized}_")
                for frame in _flatten_frames(data)
            ],
            "variant_count": len(grouped),
        }
    )


@v1_router.get("/exercise-rules")
async def get_all_exercise_rules():
    """Serve all exercise rules to clients that can apply config-driven checks."""

    return JSONResponse(
        content={
            "version": 1,
            "exercise_rules": _read_exercise_rules(),
        }
    )


@v1_router.get("/exercise-rules/{exercise}")
async def get_exercise_rules(exercise: str):
    """Serve rules for one exercise, for example pushup."""

    normalized = exercise.lower().replace("-", "_")
    rules = _read_exercise_rules().get(normalized, {})

    return JSONResponse(
        content={
            "version": 1,
            "exercise": normalized,
            "rules": rules,
        }
    )
