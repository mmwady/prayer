from __future__ import annotations

import json
import math
import threading
import time
from pathlib import Path
from types import SimpleNamespace

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
        self.mirror_sujood_recovery = False
        self.ruku_geometry_gate = False
        self.root = Path(bundle_dir)
        self.meta = json.loads((self.root / "model_metadata.json").read_text())
        preprocessing = np.load(self.root / "preprocessing.npz")
        self.mean = preprocessing["mean"]
        self.std = preprocessing["std"]
        self.models = {
            key: [torch.jit.load(str(self.root / path), map_location='cpu').eval() for path in paths]
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
        visible = [(getattr(p, "visibility", 0.0) or 0.0) >= 0.5
                   and math.isfinite(p.x) and math.isfinite(p.y)
                   and 0 <= p.x <= 1 and 0 <= p.y <= 1 for p in landmarks]
        if not any(visible):
            return annotated
        width, height = annotated.size
        scale = 3
        annotated = annotated.resize((width * scale, height * scale), Image.Resampling.LANCZOS)
        draw = ImageDraw.Draw(annotated)
        width, height = annotated.size
        points = [(int(p.x * width), int(p.y * height)) if visible[i] else (0, 0)
                  for i, p in enumerate(landmarks)]
        stroke = max(4, round(min(width, height) * .006))
        for start, end in POSE_CONNECTIONS:
            if visible[start] and visible[end]:
                draw.line((points[start], points[end]), fill=(15, 58, 48), width=stroke + 2 * scale)
                draw.line((points[start], points[end]), fill=(43, 229, 163), width=stroke)
        radius = max(6, round(min(width, height) * .009))
        for index, point in enumerate(points):
            if visible[index]:
                x, y = point
                r = max(4, round(radius * .65)) if index <= 10 else radius
                draw.ellipse(
                    (x - r, y - r, x + r, y + r),
                    fill=(255, 190, 59),
                    outline=(15, 58, 48),
                    width=scale,
                )
        return annotated.resize(image.size, Image.Resampling.LANCZOS)

    @staticmethod
    def evidence_landmarks(original, landmarks, method):
        """Undo detection rotation and letterboxing before drawing on original pixels."""
        if not landmarks:
            return None
        thumb = original.copy()
        thumb.thumbnail((384, 512), Image.Resampling.LANCZOS)
        left, top = (384 - thumb.width) // 2, (512 - thumb.height) // 2
        angle = {'rotate_minus_5': -5, 'rotate_plus_5': 5}.get(method, 0)
        radians = math.radians(angle)
        cosine, sine = math.cos(radians), math.sin(radians)
        points = []
        for p in landmarks:
            x, y = p.x * 384 - 192, p.y * 512 - 256
            x, y = cosine * x - sine * y + 192, sine * x + cosine * y + 256
            points.append(SimpleNamespace(x=(x-left)/thumb.width, y=(y-top)/thumb.height,
                                          visibility=getattr(p, 'visibility', 0.0)))
        return points

    def analyze(self, image_source):
        started = time.perf_counter()
        with self._lock:
            original = (image_source.copy() if isinstance(image_source, Image.Image)
                        else Image.fromarray(image_source) if isinstance(image_source, np.ndarray)
                        else Image.open(image_source))
            original = ImageOps.exif_transpose(original).convert('RGB')
            feature, method, visibility, landmarks, prepared = self._feature(original)
            annotated = self.draw_landmarks(original, self.evidence_landmarks(original, landmarks, method))
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
                # A low camera/view angle can confuse bowing with prostration.
                # Recover only when visible torso/head geometry independently
                # supports head-down posture and a mirrored model pass agrees.
                hip_y = (landmarks[23].y + landmarks[24].y) / 2
                shoulder_y = (landmarks[11].y + landmarks[12].y) / 2
                head_down = (all(landmarks[i].visibility >= .8 for i in (0, 11, 12, 23, 24))
                             and shoulder_y > hip_y + .04
                             and landmarks[0].y > hip_y + .12)
                if self.mirror_sujood_recovery and head_down and result['predicted_action'] in ('4_Ruku', '5_Sujud'):
                    flipped = ImageOps.mirror(self._prepare(original))
                    recovered, _, recovered_visibility, _, _ = self._feature(flipped)
                    if recovered is not None:
                        alternate = self._classify(recovered, started, 'mirror_head_down',
                                                   recovered_visibility)
                        if (alternate['predicted_action'] == '5_Sujud'
                                and alternate['confidence'] >= .65):
                            result = alternate
                if self.ruku_geometry_gate and result['predicted_action'] == '4_Ruku':
                    straight_leg = False
                    for ids in ((23, 25, 27), (24, 26, 28)):
                        if not all(landmarks[i].visibility >= .5 for i in ids):
                            continue
                        a, b, c = [np.array([landmarks[i].x * 384,
                                            landmarks[i].y * 512]) for i in ids]
                        u, v = a - b, c - b
                        denominator = np.linalg.norm(u) * np.linalg.norm(v)
                        if denominator > 1e-4:
                            angle = np.degrees(np.arccos(np.clip(u.dot(v) / denominator, -1, 1)))
                            straight_leg |= angle >= 160
                    if not straight_leg:
                        result = {**result, 'predicted_action': 'unknown', 'confidence': 0,
                                  'warning': 'Bowing lacks visible straight-leg evidence.'}
        return result, annotated

    def predict(self, image_path):
        result, _ = self.analyze(image_path)
        return result

    def predict_json(self, image_path):
        return json.dumps(self.predict(image_path), ensure_ascii=False, indent=2)

    def close(self):
        self.detector.close()
