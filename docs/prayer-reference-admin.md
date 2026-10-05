# Prayer reference authoring

Start the backend from `backend/` using its virtual environment:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Open `http://127.0.0.1:8000/admin/prayer`. There is no general admin dashboard any more;
this editor is the only HTML page the backend serves.

1. Upload a full-rakah MP4, provide a reference name and camera view.
2. Inspect extracted images and the skeleton; orange points have low confidence.
3. Select each station and mark its first frame, last frame and representative image.
4. Leave transition frames between segments; exclude occluded or incorrect detections.
5. Save a draft, reopen it later, then activate after reviewing all six stations.

The six ordered stations are standing, ruku, standing after ruku, first sujood,
sitting between prostrations, second sujood. Each activated station needs at least
three usable, non-excluded frames and a usable representative image. This screen
authors one core rakah; tashahhud and taslim require separate future reference types.

Data lives in `backend/data/prayer_references/`: source MP4, numbered JPEGs,
timestamped keypoints, draft annotations and an atomic `active.json` snapshot.
Generated media/reference data is excluded from Git. Uploads are limited to 200 MB
and 18000 decoded frames. Processing runs in a worker thread and is serialized
within the existing single-process backend. The HTTP request remains open until
processing finishes; there is no durable background-job system.

`GET /api/v1/prayer-reference` serves the activated snapshot, returning 404 until
activation. Draft edits do not change it. Activation replaces the active reference.
The payload includes the camera view, version/revision, station order, representative
frame index, normalized joint samples, joint angles and observed coordinate/angle
ranges. Coordinates are relative to the visible-side hip, scaled by torso length;
camera perspective is not removed. Observed ranges describe the supplied recording,
not clinically or religiously validated acceptance thresholds.

The Flutter camera flow downloads the activated schema-2 reference before opening
training. Configure its backend address on the source screen (on Android emulator
use http://10.0.2.2:8000; on a physical phone use the computer LAN address and bind
the backend to that interface). The upload page stays on the backend; live camera
frames are processed on device and never uploaded by this flow.

Before starting, an overlay displays the standing reference skeleton and tracked
body in the same aspect-corrected, mirrored viewport. Guidance checks visibility,
framing, distance, centering, standing posture and approximate view. Readiness
needs at least eight frames and 1.5 seconds of continuous stability; stale or invalid
tracking cancels it. An explicit Start button begins station counting. An optional
ruku/sujood coverage check helps verify floor framing, then asks for standing again.
Reference samples gate the local classifier and deterministic station engine.

Schema 2 records MediaPipe estimated world x/y/z, normalized 3D joint samples and
3D angles, plus the original image aspect ratio and representative 2D joints.
Activation requires usable 3D evidence and a standing image showing head, torso
and both legs. Old references must be re-uploaded. Native ML Kit z is experimental
image-space depth; it is tagged separately and never compared to MediaPipe world
coordinates. Calibration and native reference matching currently use projected 2D
geometry. Approximate view signatures are not measurements in degrees. The initial
matching tolerance requires calibration against real prayer recordings and body
proportions; unit tests cannot establish camera accuracy. This reference-authoring feature
makes no LLM or paid provider calls of its own; the separate guidance route is the only
component that contacts a model.
MediaPipe may download its public model asset on first use if it is not cached.

This page has no authentication. Run it locally; external deployment needs access controls.

Validation: backend tests exercise upload/annotation/activation APIs with synthetic
extraction, so real decoding quality is not covered by them. Real prayer videos must be
reviewed manually before activation.

Current validation (2026-10-02): 46 Flutter tests and 23 backend tests pass. The guidance
route is covered with a fake LLM client, so no key, network or cost is involved. No
Android/iOS device was connected for acceptance testing, and real prayer-video accuracy
remains unverified.
