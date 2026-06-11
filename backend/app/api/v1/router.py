from fastapi import APIRouter
from fastapi.responses import JSONResponse
import os
import json
from pathlib import Path

v1_router = APIRouter(
    prefix="/api/v1",
    tags=["api_v1"]
)

# Paths relative to backend root
DATA_DIR = Path("data")
TEMPLATES_DIR = DATA_DIR / "templates"

@v1_router.get("/templates")
async def get_all_templates():
    """
    Dynamically reads all individual JSON files in the /templates folder 
    and serves them as a single combined JSON payload for the Mobile App.
    Format: {"version": 1, "templates": {"squat": [...], "pushup": [...]}}
    """
    combined_templates = {}

    if TEMPLATES_DIR.exists():
        for json_filename in os.listdir(TEMPLATES_DIR):
            if json_filename.endswith(".json"):
                exercise_name = json_filename.replace(".json", "")
                json_path = TEMPLATES_DIR / json_filename
                
                try:
                    with open(json_path, "r", encoding="utf-8") as f:
                        data = json.load(f)
                        combined_templates[exercise_name] = data
                except Exception as e:
                    # Log the error but continue parsing other templates
                    print(f"Error reading template {json_filename}: {str(e)}")

    return JSONResponse(content={
        "version": 1,
        "templates": combined_templates
    })
