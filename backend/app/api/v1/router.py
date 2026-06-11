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
    """Read all JSON template files into a filename-keyed dictionary.

    Example:
        pushup.json            -> templates["pushup"]
        pushup_side_left.json  -> templates["pushup_side_left"]
    """

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


@v1_router.get("/templates")
async def get_all_templates():
    """
    Serve all exercise templates to the mobile app.

    This keeps backward compatibility with the original Flutter loader:
    {
      "version": 1,
      "templates": {
        "pushup": [...],
        "pushup_side_left": {...},
        "pushup_side_right": {...},
        "pushup_45deg": {...}
      }
    }
    """

    return JSONResponse(
        content={
            "version": 2,
            "templates": _read_templates(),
        }
    )


@v1_router.get("/templates/{exercise}")
async def get_exercise_templates(exercise: str):
    """Return all templates for one exercise grouped together.

    This is useful for clients that want only push-up templates instead of the
    full template catalog.
    """

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
            "variant_count": len(grouped),
        }
    )
