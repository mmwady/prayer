from __future__ import annotations

import json
import threading
import time
from pathlib import Path

import mediapipe as mp
import numpy as np
import torch
from PIL import Image, ImageDraw, ImageEnhance, ImageOps


POSE_CONNECTIONS = (
    (0, 1), (1, 2), (2, 3), (3, 7), (0, 4), (4, 5), (5, 6), (6, 8),
    (9, 10), (11, 12), (11, 13), (13, 15), (15, 17), (15, 19), (15, 21),
    (17, 19), (12, 14), (14, 16), (16, 18), (16, 20), (16, 22), (18, 20),
    (11, 23), (12, 24), (23, 24), (23, 25), (24, 26), (25, 27), (26, 28),
    (27, 29), (28, 30), (29, 31), (30, 32), (27, 31), (28, 32),
)


class PrayerActionPredictor:
    def __init__(self, bundle_dir):
        self.root = Path(bundle_dir)
        self.meta = json.loads((self.root / "model_metadata.json").read_text())
        preprocessing = np.load(self.root / "preprocessing.npz")
        self.mean = preprocessing["mean"]
        self.std = preprocessing["std"]
        self.models = {
            key: [torch.jit.load(str(self.root / path)).eval() for path in paths]
            for key, paths in self.meta["components"].items()
        }
        base = mp.tasks.BaseOptions
        options = mp.tasks.vision.PoseLandmarkerOptions
        mode = mp.tasks.vision.RunningMode
        self.detector = mp.tasks.vision.PoseLandmarker.create_from_options(
            options(
                base_options=base(
                    model_asset_path=str(self.root / "pose_landmarker_heavy.task")
                ),
                running_mode=mode.IMAGE,
                min_pose_detection_confidence=0.2,
                min_pose_presence_confidence=0.2,
                min_tracking_confidence=0.2,
                num_poses=1,
            )
        )
        self._lock = threading.Lock()

    @staticmethod
    def _prepare(source):
        if isinstance(source, Image.Image):
            image = source.copy()
        elif isinstance(source, np.ndarray):
            image = Image.fromarray(np.asarray(source, dtype=np.uint8))
        else:
            image = Image.open(source)
        image = ImageOps.exif_transpose(image).convert("RGB")
        canvas = Image.new("RGB", (384, 512), (0, 0, 0))
        image.thumbnail((384, 512), Image.Resampling.LANCZOS)
        canvas.paste(image, ((384 - image.width) // 2, (512 - image.height) // 2))
        return canvas

    def _feature(self, source):
        image = self._prepare(source)
        candidates = [
            ("standard", image),
            ("autocontrast", ImageOps.autocontrast(image, cutoff=1)),
            ("contrast_1.15", ImageEnhance.Contrast(image).enhance(1.15)),
            ("rotate_minus_5", image.rotate(-5, Image.Resampling.BICUBIC)),
            ("rotate_plus_5", image.rotate(5, Image.Resampling.BICUBIC)),
        ]
        for method, candidate in candidates:
            mp_image = mp.Image(
                image_format=mp.ImageFormat.SRGB,
                data=np.ascontiguousarray(np.asarray(candidate)),
            )
            detection = self.detector.detect(mp_image)
            if not detection.pose_landmarks:
                continue
            landmarks = detection.pose_landmarks[0]
            xyz = np.array([[p.x, p.y, p.z] for p in landmarks], np.float32)
            visibility = np.array(
                [getattr(p, "visibility", 0.0) or 0.0 for p in landmarks], np.float32
            )
            presence = np.array(
                [getattr(p, "presence", 0.0) or 0.0 for p in landmarks], np.float32
            )
            hip = xyz[[23, 24]].mean(0)
            scale = max(
                np.linalg.norm(xyz[[11, 12], :2].mean(0) - hip[:2]),
                np.linalg.norm(xyz[11, :2] - xyz[12, :2]),
            )
            if np.isfinite(xyz).all() and scale > 1e-4:
                raw = np.r_[((xyz - hip) / scale).ravel(), visibility, presence, 1.0]
                raw = raw.astype(np.float32)
                feature = np.r_[(raw[:-1] - self.mean) / self.std, raw[-1]].astype(
                    np.float32
                )
                return feature, method, float(visibility.mean()), landmarks, candidate
        return None, "failed", None, None, image

    def _average(self, name, tensor):
        with torch.inference_mode():
            return np.mean(
                [torch.softmax(model(tensor), 1).numpy()[0] for model in self.models[name]],
                axis=0,
            )

    def _classify(self, feature, started, method, visibility):
        tensor = torch.tensor(feature[None], dtype=torch.float32)
        winner = self.meta["winner"]
        if winner == "exp4_probability_fusion":
            weights = self.meta["fusion_weights"]
            probabilities = (
                weights["full_weight"] * self._average("full", tensor)
                + weights["head_weight"] * self._average("head", tensor)
                + weights["arm_weight"] * self._average("arm", tensor)
            )
        elif winner in ("exp5_hierarchy_hard", "exp6_hierarchy_soft"):
            general = self._average("general", tensor)
            qiyam = self._average("qiyam", tensor)
            sitting = self._average("sitting", tensor)
            probabilities = np.zeros(8)
            probabilities[[0, 2]] = general[0] * qiyam
            probabilities[1] = general[1]
            probabilities[3] = general[2]
            probabilities[4] = general[3]
            probabilities[5:8] = general[4] * sitting
            if self.meta["hard_hierarchy"]:
                region = general.argmax()
                hard = np.zeros_like(probabilities)
                if region == 0:
                    hard[[0, 2]] = qiyam
                elif region == 1:
                    hard[1] = 1
                elif region == 2:
                    hard[3] = 1
                elif region == 3:
                    hard[4] = 1
                else:
                    hard[5:8] = sitting
                probabilities = hard
        else:
            probabilities = self._average("main", tensor)

        probabilities = probabilities / probabilities.sum()
        order = np.argsort(probabilities)[::-1]
        classes = self.meta["classes"]
        return {
            "predicted_action": classes[int(order[0])],
            "class_index": int(order[0]),
            "confidence": float(probabilities[order[0]]),
            "probabilities": {
                classes[index]: float(probabilities[index]) for index in range(8)
            },
            "top3": [
                {"action": classes[int(index)], "probability": float(probabilities[index])}
                for index in order[:3]
            ],
            "pose_detected": True,
            "normalization_valid": True,
            "recovery_method": method,
            "mean_visibility": visibility,
            "model_type": winner,
            "inference_ms": (time.perf_counter() - started) * 1000,
            "warning": None,
        }

    @staticmethod
    def draw_landmarks(image, landmarks):
        annotated = image.copy()
        if not landmarks:
            return annotated
        draw = ImageDraw.Draw(annotated)
        width, height = annotated.size
        points = [(int(p.x * width), int(p.y * height)) for p in landmarks]
        visible = [(getattr(p, "visibility", 0.0) or 0.0) >= 0.2 for p in landmarks]
        for start, end in POSE_CONNECTIONS:
            if visible[start] and visible[end]:
                draw.line((points[start], points[end]), fill=(43, 229, 163), width=4)
        radius = max(3, width // 110)
        for index, point in enumerate(points):
            if visible[index]:
                x, y = point
                draw.ellipse(
                    (x - radius, y - radius, x + radius, y + radius),
                    fill=(255, 190, 59),
                    outline=(15, 58, 48),
                    width=2,
                )
        return annotated

    def analyze(self, image_source):
        started = time.perf_counter()
        with self._lock:
            feature, method, visibility, landmarks, prepared = self._feature(image_source)
            annotated = self.draw_landmarks(prepared, landmarks)
            if feature is None:
                result = {
                    "predicted_action": None,
                    "confidence": 0.0,
                    "pose_detected": False,
                    "normalization_valid": False,
                    "recovery_method": "failed",
                    "inference_ms": (time.perf_counter() - started) * 1000,
                    "warning": "Pose detection and recovery failed.",
                }
            else:
                result = self._classify(feature, started, method, visibility)
        return result, annotated

    def predict(self, image_path):
        result, _ = self.analyze(image_path)
        return result

    def predict_json(self, image_path):
        return json.dumps(self.predict(image_path), ensure_ascii=False, indent=2)

    def close(self):
        self.detector.close()
