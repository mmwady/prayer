# Iqtadi backend

Self-contained FastAPI backend with local prayer-action inference.
The deployment bundle is included in `models/prayer_action/` (metadata, normalization,
MediaPipe task and three TorchScript weights). No UI folder is required at runtime.

Run all commands from this directory:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Set application configuration in `.env` (keep secrets out of source control):

```dotenv
INFERENCE_PROVIDER=real
ANALYSIS_ALLOW_MOCK=false
PRAYER_MODEL_BUNDLE_DIR=models/prayer_action
```

Verify weights locally with `python tools/smoke_prayer_model.py`.
Build a standalone image from this directory with `docker build -t iqtadi-backend .`.
Pass environment settings when starting the image; Docker includes model weights.
Real-video accuracy evaluation and production authentication/HTTPS remain pending.

On Windows, `start_backend.bat` selects this directory and its Python explicitly.
After moving a virtual environment, reactivate it and use `python -m uvicorn`;
existing terminal PATH values and old executable launchers can still select the old project.


## Optional experimental postprocessing

All four corrections are OFF by default and OFF in the local `.env`.
Set any option to `true` independently in `backend/.env`, then restart the backend:

```dotenv
PRAYER_MIRROR_SUJOOD_RECOVERY=false
PRAYER_RUKU_GEOMETRY_GATE=false
PRAYER_SEATED_PROBABILITY_PROJECTION=false
PRAYER_SEQUENCE_NORMALIZATION=false
```

The first three govern mirrored Sujud recovery, the straight-knee Ruku gate and seated probability aggregation.
The fourth governs trimming, transitional takbir filtering, same-posture consolidation and tolerance of uncertain transition samples.
With all disabled, original model labels/confidence are preserved (apart from the existing canonical label mapping),
and strict conservative alignment handles the report. Recorded demo still includes final sitting and salam as requested.
The earlier successful supplied-video evaluation used all corrections enabled; it does not describe the new default raw mode.
The public `/api/v1/prayer-analyses/config` exposes active switches under `experimental_postprocessing`.
82 tests verify defaults, disabled behavior and opt-in behavior. No general video-accuracy claim.
