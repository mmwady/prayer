from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from fastapi.responses import HTMLResponse, FileResponse, JSONResponse
from pathlib import Path
import os
import json
import shutil

# Import the existing template generator
from templates.generate_template import TemplateGenerator

# Setup paths (relative to the directory from where uvicorn is launched, usually `backend/`)
DATA_DIR = Path("data")
VIDEOS_DIR = DATA_DIR / "videos"
TEMPLATES_DIR = DATA_DIR / "templates"

# Ensure data directories exist
os.makedirs(VIDEOS_DIR, exist_ok=True)
os.makedirs(TEMPLATES_DIR, exist_ok=True)

admin_router = APIRouter(
    prefix="/admin",
    tags=["admin"]
)

# Initialize the TemplateGenerator lazily to avoid MediaPipe import-time issues
_generator = None

def get_template_generator():
    global _generator
    if _generator is None:
        _generator = TemplateGenerator()
    return _generator

@admin_router.get("", response_class=HTMLResponse)
async def serve_dashboard():
    """
    Serves the Admin Dashboard HTML page.
    """
    # The HTML file will be placed in the same directory as this router
    html_path = Path(__file__).parent / "index.html"
    if not html_path.exists():
        raise HTTPException(status_code=404, detail="Dashboard UI not found.")
    
    with open(html_path, "r", encoding="utf-8") as f:
        return HTMLResponse(content=f.read())


@admin_router.post("/api/upload")
async def upload_video(
    file: UploadFile = File(...), 
    exercise_name: str = Form(...)
):
    """
    Handles video upload, saves the file to /videos/, and processes it
    to generate a JSON template saved to /templates/.
    This is intentionally synchronous/blocking because TemplateGenerator uses OpenCV/MediaPipe.
    """
    # Ensure a valid file extension
    if not file.filename.endswith(".mp4"):
        raise HTTPException(status_code=400, detail="Only .mp4 files are supported.")

    # Clean the exercise name to avoid path traversal or weird filenames
    clean_exercise_name = "".join([c for c in exercise_name if c.isalnum() or c in ("-", "_")]).lower()

    if not clean_exercise_name:
        raise HTTPException(status_code=400, detail="Invalid exercise name provided.")

    video_path = VIDEOS_DIR / f"{clean_exercise_name}.mp4"
    json_path = TEMPLATES_DIR / f"{clean_exercise_name}.json"

    # Save the uploaded video file
    try:
        with open(video_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to save video: {str(e)}")

    # Process the video using the TemplateGenerator
    try:
        # Note: This is blocking. To make it non-blocking we could use `anyio.to_thread.run_sync`
        # But for an internal tool, blocking is usually acceptable.
        generator = get_template_generator()
        generator.generate(str(video_path), str(json_path))
    except Exception as e:
        # Clean up the video file if generation fails
        if video_path.exists():
            os.remove(video_path)
        raise HTTPException(status_code=500, detail=f"Failed to generate template: {str(e)}")

    return JSONResponse(content={
        "status": "success", 
        "message": f"Template generated successfully for {clean_exercise_name}",
        "exercise": clean_exercise_name
    })


@admin_router.get("/api/templates")
async def list_templates():
    """
    Scans the /templates directory and lists all available exercise templates.
    """
    templates = []
    
    if TEMPLATES_DIR.exists():
        for json_file in os.listdir(TEMPLATES_DIR):
            if json_file.endswith(".json"):
                exercise_name = json_file.replace(".json", "")
                
                # Check if the associated video exists
                video_filename = f"{exercise_name}.mp4"
                video_exists = (VIDEOS_DIR / video_filename).exists()
                
                # We could potentially open the JSON and read frame count, but for
                # performance we just return the name and paths for now.
                templates.append({
                    "exercise": exercise_name,
                    "video_url": f"/admin/videos/{video_filename}" if video_exists else None,
                    "json_url": f"/admin/data/templates/{json_file}"
                })
                
    return JSONResponse(content={"templates": templates})


@admin_router.delete("/api/templates/{exercise_name}")
async def delete_template(exercise_name: str):
    """
    Deletes the template JSON and its associated video for a given exercise name.
    """
    # Clean the name to prevent path traversal
    clean_exercise_name = "".join([c for c in exercise_name if c.isalnum() or c in ("-", "_")]).lower()

    video_path = VIDEOS_DIR / f"{clean_exercise_name}.mp4"
    json_path = TEMPLATES_DIR / f"{clean_exercise_name}.json"
    
    deleted = False

    if video_path.exists():
        os.remove(video_path)
        deleted = True

    if json_path.exists():
        os.remove(json_path)
        deleted = True

    if not deleted:
        raise HTTPException(status_code=404, detail="Template not found.")

    return JSONResponse(content={"status": "success", "message": f"Deleted {clean_exercise_name}"})


@admin_router.get("/videos/{video_name}")
async def serve_video(video_name: str):
    """
    Serves the MP4 video directly for the HTML5 player.
    """
    # Clean string to prevent path traversal
    clean_video_name = "".join([c for c in video_name if c.isalnum() or c in ("-", "_", ".")])
    video_path = VIDEOS_DIR / clean_video_name
    
    if not video_path.exists():
        raise HTTPException(status_code=404, detail="Video not found.")
        
    return FileResponse(path=video_path, media_type="video/mp4")

@admin_router.get("/data/templates/{json_name}")
async def serve_template_json(json_name: str):
    """
    Serves the specific JSON file directly (useful for debugging).
    """
    clean_json_name = "".join([c for c in json_name if c.isalnum() or c in ("-", "_", ".")])
    json_path = TEMPLATES_DIR / clean_json_name
    
    if not json_path.exists():
        raise HTTPException(status_code=404, detail="JSON not found.")
        
    return FileResponse(path=json_path, media_type="application/json")
