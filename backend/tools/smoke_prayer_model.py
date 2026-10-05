"""Run from backend/: python tools/smoke_prayer_model.py (local CPU only)."""
import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from PIL import Image
import numpy as np
from app.analysis.inference import InferencePipeline
from app.config import get_settings

settings = get_settings()
pipeline = InferencePipeline("real", "demo", "normal", settings.analysis_pose_map,
                             settings.prayer_model_bundle_dir)
try:
    predictor = pipeline.predictor
    assert predictor.mean.shape == (165,)
    assert predictor.std.shape == (165,)
    assert np.isfinite(predictor.std).all() and (predictor.std > 0).all()
    result = predictor._classify(np.zeros(166, dtype=np.float32), 0, "synthetic", 0)
    assert len(result["probabilities"]) == 8
    assert abs(sum(result["probabilities"].values()) - 1) < 1e-5
    payload = io.BytesIO()
    Image.new("RGB", (384, 512), "black").save(payload, format="JPEG")
    observation = pipeline.predict(payload.getvalue(), "blank", 0, 0)
    assert observation.pose == "unknown" and not observation.detected
    print({"model_version": pipeline.model_version, "ensemble_models": len(predictor.models["main"]),
           "classes": len(result["probabilities"]), "blank_pose": observation.pose})
finally:
    pipeline.close()
