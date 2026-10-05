import math
from types import SimpleNamespace

import pytest
from PIL import Image

from app.analysis.prayer_action_predictor import PrayerActionPredictor
from app.analysis.inference import InferencePipeline


@pytest.mark.parametrize('method,angle', [('standard', 0), ('rotate_minus_5', -5), ('rotate_plus_5', 5)])
def test_landmarks_return_to_original_after_letterbox_and_rotation(method, angle):
    original = Image.new('RGB', (1280, 720))
    # Original (0.25, 0.75) -> 384x216 thumbnail with top padding 148.
    x, y = 96 - 192, 162 + 148 - 256
    a = math.radians(angle)
    rotated_x = math.cos(a) * x + math.sin(a) * y + 192
    rotated_y = -math.sin(a) * x + math.cos(a) * y + 256
    points = PrayerActionPredictor.evidence_landmarks(original,
        [SimpleNamespace(x=rotated_x/384, y=rotated_y/512, visibility=.9)], method)
    assert points[0].x == pytest.approx(.25)
    assert points[0].y == pytest.approx(.75)


def test_no_body_and_unreliable_points_leave_original_untouched():
    image = Image.new('RGB', (640, 480), 'white')
    assert PrayerActionPredictor.draw_landmarks(image, None).tobytes() == image.tobytes()
    points = [SimpleNamespace(x=.5, y=.5, visibility=.1) for _ in range(33)]
    assert PrayerActionPredictor.draw_landmarks(image, points).tobytes() == image.tobytes()
    points[0] = SimpleNamespace(x=float('nan'), y=.5, visibility=.9)
    assert PrayerActionPredictor.draw_landmarks(image, points).tobytes() == image.tobytes()


def test_pipeline_persists_annotated_evidence_without_changing_prediction(tmp_path):
    calls = []
    def analyze(source):
        calls.append(source.read())
        return (dict(predicted_action='5_Sujud', confidence=.9, pose_detected=True,
                     normalization_valid=True), Image.new('RGB', (640, 480), 'green'))
    pipeline = InferencePipeline.__new__(InferencePipeline)
    pipeline.predictor = SimpleNamespace(analyze=analyze, meta={'model_version': 'test'})
    pipeline.seated_probability_projection = False
    pipeline.confidence_threshold = .65
    pipeline.pose_map = {'5_Sujud': 'sujood'}
    target = tmp_path / 'frame.jpg'
    result = pipeline.predict(b'original', 'f1', 0, 0, evidence_path=target)
    assert calls == [b'original']
    assert result.pose == 'sujood' and result.confidence == .9
    with Image.open(target) as saved:
        assert saved.size == (640, 480)
        assert saved.getpixel((320, 240))[1] > 100
