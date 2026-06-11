from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from fastapi import APIRouter
from fastapi.responses import JSONResponse

v1_router = APIRouter(prefix="/api/v1", tags=["api_v1"])

# Uvicorn is started from the backend root in this project, so this resolves to:
# backend/data/templates
DATA_DIR = Path("data")
TEMPLATES_DIR = DATA_DIR / "templates"


def _read_templates() -> dict[str, Any]:
    """Read all JSON template files into a filename-keyed dictionary."""

    combined_templates: dict[str, Any] = {}

    if not TEMPLATES_DIR.exists():
        return combined_templates

    for json_filename in sorted(os.listdir(TEMPLATES_DIR)):
        if not json_filename.endswith(".json"):
            continue

        template_name = json_filename.replace(".json", "")
        json_path = TEMPLATES_DIR / json_filename

        try:
            with open(json_path, "r", encoding="utf-8") as f:
                combined_templates[template_name] = json.load(f)
        except Exception as exc:  # pragma: no cover - best-effort template loading
            print(f"Error reading template {json_filename}: {exc}")

    return combined_templates


def _extract_frame_points(frame: Any) -> list[dict[str, Any]] | None:
    """Normalize either old raw frames or richer metadata frames.

    Old generated template frame:
        [{"id": "leftShoulder", "x": ..., ...}, ...]

    New demo template frame:
        {"phase": "top", "keypoints": [{...}, ...]}
    """

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
    """Expose multi-view push-up templates under the existing `pushup` key.

    The current Flutter controller already expects `templates[exercise]` to be a
    plain list of frames. This compatibility layer lets the mobile app benefit
    from multiple push-up views without requiring a Flutter-side migration first.
    """

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
    """
    Serve all exercise templates to the mobile app.

    Backward-compatible response:
    {
      "version": 2,
      "templates": {
        "pushup": [[...], ...],
        "pushup_side_left": {"frames": [...]},
        "pushup_side_right": {"frames": [...]}
      }
    }
    """

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
