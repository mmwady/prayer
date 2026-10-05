"""Bundled end-to-end real predictor and explicitly scripted mock inference."""
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from typing import Protocol

from .contracts import Keypoint, KeypointResult, PosePrediction
from .domain import STATION_POSES, stations


class ModelNotConfigured(RuntimeError):
    pass


class KeypointExtractor(Protocol):
    def extract(self, image: bytes) -> KeypointResult: ...


class PoseClassifier(Protocol):
    def classify(self, keypoints: KeypointResult) -> PosePrediction: ...


class MockKeypointExtractor:
    def extract(self, image: bytes) -> KeypointResult:
        # Never pretends to locate a body in the supplied image.
        return KeypointResult(detected=False, keypoints=[
            Keypoint(id=i, confidence=0) for i in range(32)])


class MockPoseClassifier:
    def __init__(self, pose: str = 'unknown', confidence: float = 0):
        self.pose, self.confidence = pose, confidence

    def classify(self, keypoints: KeypointResult) -> PosePrediction:
        return PosePrediction(pose=self.pose, confidence=self.confidence, model_version='mock-v1')


class RealKeypointExtractor:
    def extract(self, image: bytes) -> KeypointResult:
        raise ModelNotConfigured('MODEL_NOT_CONFIGURED')


class RealPoseClassifier:
    def classify(self, keypoints: KeypointResult) -> PosePrediction:
        raise ModelNotConfigured('MODEL_NOT_CONFIGURED')


def script(prayer: str, scenario: str) -> list[tuple[str, float]]:
    items = [(STATION_POSES[s], .96) for r in stations(prayer) for s in r]
    ruku = next(i for i, (pose, _) in enumerate(items) if pose == 'ruku')
    sujood = next(i for i, (pose, _) in enumerate(items) if pose == 'sujood')
    if scenario in ('missing_ruku', 'uncertain_pose'):
        items[ruku] = ('unknown', 0) if scenario == 'missing_ruku' else ('ruku', .35)
    elif scenario == 'missing_sujood':
        items[sujood] = ('unknown', 0)
    elif scenario == 'repeated_movement':
        items[sujood:sujood] = [('ruku', .96), ('standing', .96)]
    elif scenario == 'wrong_sequence':
        items[ruku], items[sujood] = items[sujood], items[ruku]
    elif scenario == 'incomplete_prayer':
        items = items[:max(2, len(items) // 2)]
    return items


@dataclass(frozen=True)
class Observation:
    frame_id: str
    timestamp_ms: int
    sequence_index: int
    pose: str
    confidence: float
    detected: bool


class InferencePipeline:
    def __init__(self, provider: str, prayer: str, scenario: str, pose_map: dict[str, str],
                 bundle_dir: str | None = None, confidence_threshold: float | None = None, *,
                 mirror_sujood_recovery: bool = False, ruku_geometry_gate: bool = False,
                 seated_probability_projection: bool = False):
        self.provider, self.pose_map = provider, pose_map
        self.predictor = None
        self.seated_probability_projection = seated_probability_projection
        if provider == 'real':
            try:
                from ..config import get_settings
                self.confidence_threshold = (get_settings().temporal_confidence
                                             if confidence_threshold is None else confidence_threshold)
                root = Path(bundle_dir or get_settings().prayer_model_bundle_dir)
                if not (root / 'model_metadata.json').is_file():
                    raise ModelNotConfigured('MODEL_NOT_CONFIGURED')
                from .prayer_action_predictor import PrayerActionPredictor
                self.predictor = PrayerActionPredictor(root)
                self.predictor.mirror_sujood_recovery = mirror_sujood_recovery
                self.predictor.ruku_geometry_gate = ruku_geometry_gate
            except Exception as exc:
                raise ModelNotConfigured('MODEL_NOT_CONFIGURED') from exc
        self.extractor = MockKeypointExtractor() if provider == 'mock' else RealKeypointExtractor()
        self.classifier = MockPoseClassifier() if provider == 'mock' else RealPoseClassifier()
        self.items = script(prayer, scenario)
        self.model_version = 'mock-v1' if provider == 'mock' else 'unconfigured'

    def predict(self, image: bytes, frame_id: str, timestamp_ms: int, index: int,
                evidence_path: Path | None = None) -> Observation:
        if self.predictor is not None:
            if evidence_path is None:
                result = self.predictor.predict(BytesIO(image))
            else:
                result, annotated = self.predictor.analyze(BytesIO(image))
                annotated.save(evidence_path, format='JPEG', quality=95, subsampling=0)
            detected = bool(result['pose_detected'] and result['normalization_valid'])
            # Project mutually exclusive seated subclasses onto physical sitting.
            # No direction is inferred from their combined probability.
            probabilities = result.get('probabilities', {})
            threshold = self.confidence_threshold
            seated = sum(probabilities.get(label, 0) for label in
                         ('6_Jalsa', '7_Salam_Right', '8_Salam_Left'))
            if (self.seated_probability_projection and detected
                    and result['confidence'] < threshold and seated >= threshold):
                result = {**result, 'predicted_action': '6_Jalsa', 'confidence': seated}
            prediction = PosePrediction(
                pose=result['predicted_action'] if detected else 'unknown',
                confidence=result['confidence'] if detected else 0,
                model_version=self.predictor.meta['model_version'])
            self.model_version = prediction.model_version
            return Observation(frame_id, timestamp_ms, index,
                               self.pose_map.get(prediction.pose, 'unknown'),
                               prediction.confidence, detected)
        points = self.extractor.extract(image)
        if self.provider == 'mock':
            # Each scripted posture lasts 2 seconds of ORIGINAL video time.
            slot = timestamp_ms // 2000
            pose, confidence = self.items[slot] if slot < len(self.items) else ('unknown', 0)
            prediction = MockPoseClassifier(pose, confidence).classify(points)
            detected = pose != 'unknown'  # synthetic observation, never an image detection
        else:
            prediction = self.classifier.classify(points)
            detected = points.detected
        pose = self.pose_map.get(prediction.pose, 'unknown')
        self.model_version = prediction.model_version
        return Observation(frame_id, timestamp_ms, index, pose, prediction.confidence, detected)

    def close(self):
        if self.predictor is not None:
            self.predictor.close()
