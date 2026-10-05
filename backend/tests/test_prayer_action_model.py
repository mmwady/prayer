import sys
from types import SimpleNamespace

import pytest
from app.analysis.domain import DEFAULT_POSE_MAP, stations
from app.analysis.inference import InferencePipeline


@pytest.mark.parametrize("label,pose", [(label, pose) for label, pose in DEFAULT_POSE_MAP.items() if label[0].isdigit()])
def test_actual_model_labels_and_cleanup(monkeypatch, tmp_path, label, pose):
    (tmp_path / "model_metadata.json").write_text("{}")
    closed = []
    class Predictor:
        meta = {"model_version": "actual-version"}
        def __init__(self, root):
            pass
        def predict(self, source):
            assert source.read() == b"jpeg"
            return dict(predicted_action=label, confidence=.9,
                        pose_detected=True, normalization_valid=True)
        def close(self):
            closed.append(True)
    monkeypatch.setitem(sys.modules, "app.analysis.prayer_action_predictor",
                        SimpleNamespace(PrayerActionPredictor=Predictor))
    pipeline = InferencePipeline("real", "fajr", "normal", DEFAULT_POSE_MAP, str(tmp_path))
    observation = pipeline.predict(b"jpeg", "f1", 500, 1)
    assert observation.pose == pose
    assert observation.detected and observation.confidence == .9
    assert pipeline.model_version == "actual-version"
    pipeline.close()
    assert closed == [True]


def test_recorded_sequence_has_opening_and_terminal_actions():
    for prayer in ["fajr", "dhuhr", "asr", "maghrib", "isha"]:
        rows = stations(prayer)
        assert rows[0][0] == "takbir"
        assert rows[-1][-3:] == ["final_sitting", "salam_right", "salam_left"]
        assert sum(row.count("takbir") for row in rows) == 1


def test_no_body_never_confirms(monkeypatch, tmp_path):
    (tmp_path / "model_metadata.json").write_text("{}")
    class Predictor:
        meta = {"model_version": "actual-version"}
        def __init__(self, root):
            pass
        def predict(self, source):
            return dict(predicted_action=None, confidence=0,
                        pose_detected=False, normalization_valid=False)
        def close(self):
            pass
    monkeypatch.setitem(sys.modules, "app.analysis.prayer_action_predictor",
                        SimpleNamespace(PrayerActionPredictor=Predictor))
    pipeline = InferencePipeline("real", "fajr", "normal", DEFAULT_POSE_MAP, str(tmp_path))
    observation = pipeline.predict(b"jpeg", "f1", 0, 0)
    assert observation.pose == "unknown"
    assert observation.confidence == 0 and not observation.detected
    pipeline.close()


@pytest.mark.parametrize("prayer", ["demo", "fajr"])
def test_demo_has_terminal_sitting_and_salam(prayer):
    assert stations(prayer)[-1][-3:] == ["final_sitting", "salam_right", "salam_left"]


@pytest.mark.parametrize("enabled", [False, True])
def test_seated_subclass_probability_is_not_a_direction(monkeypatch, tmp_path, enabled):
    (tmp_path / "model_metadata.json").write_text("{}")
    class Predictor:
        meta = {"model_version": "actual-version"}
        def __init__(self, root): pass
        def predict(self, source):
            return dict(predicted_action="7_Salam_Right", confidence=.45,
                        pose_detected=True, normalization_valid=True,
                        probabilities={"6_Jalsa": .3, "7_Salam_Right": .45, "8_Salam_Left": .2})
        def close(self): pass
    monkeypatch.setitem(sys.modules, "app.analysis.prayer_action_predictor",
                        SimpleNamespace(PrayerActionPredictor=Predictor))
    pipeline = InferencePipeline("real", "demo", "normal", DEFAULT_POSE_MAP, str(tmp_path),
                                 seated_probability_projection=enabled)
    result = pipeline.predict(b"jpeg", "f1", 0, 0)
    assert result.pose == ("sitting" if enabled else "salam_right")
    assert result.confidence == pytest.approx(.95 if enabled else .45)
    pipeline.close()


def movement_events(poses):
    from app.analysis.contracts import MovementEvent
    return [MovementEvent(event_id=f"e{i}", pose=pose, start_ms=i*1000,
                          end_ms=i*1000+750, confidence=.9,
                          representative_frame_id=f"f{i}", observation_status="detected")
            for i, pose in enumerate(poses)]


def test_transition_gestures_and_preparation_do_not_make_complete_rakah_ambiguous():
    from app.analysis.sequence import analyze
    poses=["sujood", "standing", "takbir", "standing", "takbir", "standing",
           "takbir", "ruku", "takbir", "standing", "takbir", "sujood", "sitting",
           "sujood", "sitting", "salam_right", "sitting", "salam_left", "ruku"]
    report=analyze("fixture", "demo", movement_events(poses), "real", 4, 80, normalize_sequence=True)
    assert report.observed_rakahs == 1
    assert report.overall_result == "OBSERVED_COMPLETE"
    assert not report.unexpected_movements


def test_absent_sitting_is_not_invented_from_sequence():
    from app.analysis.sequence import analyze
    poses=["takbir", "standing", "ruku", "standing", "sujood", "sujood",
           "sitting", "salam_right", "salam_left"]
    report=analyze("fixture", "demo", movement_events(poses), "real", 4, 80, normalize_sequence=True)
    assert report.observed_rakahs == 0
    assert report.rakahs[0].stations[6].status == "UNCONFIRMED"


def test_forward_assignment_keeps_later_out_of_order_bowing_for_review():
    from app.analysis.sequence import analyze
    poses = ['takbir', 'standing', 'ruku', 'sitting', 'ruku', 'standing',
             'sujood', 'sitting', 'sujood', 'sitting', 'salam_right', 'salam_left']
    events = movement_events(poses)
    events[2] = events[2].model_copy(update={'confidence': .8})
    events[4] = events[4].model_copy(update={'confidence': .99})
    report = analyze('context', 'demo', events, 'real', 4, 48, normalize_sequence=True)
    bow = report.rakahs[0].stations[2]
    assert bow.status == 'DETECTED' and bow.event_id == 'e4' and bow.confidence == .99
    extra = next(e for e in report.unexpected_movements if e.pose == 'ruku')
    assert extra.review_rakah_number == 1
    assert extra.event_id == 'e2'


def test_normalization_merges_adjacent_frames_using_peak_event_id():
    from app.analysis.sequence import analyze
    events = movement_events(['takbir', 'standing', 'ruku', 'ruku', 'standing',
                              'sujood', 'sitting', 'sujood', 'sitting', 'salam_right', 'salam_left'])
    events[2] = events[2].model_copy(update={'confidence': .75})
    events[3] = events[3].model_copy(update={'confidence': .98})
    report = analyze('peak', 'demo', events, 'real', 4, 44, normalize_sequence=True)
    bow = report.rakahs[0].stations[2]
    assert bow.event_id == 'e3' and bow.confidence == .98


def test_completed_first_rakah_bounds_review_and_second_rakah_assignment():
    from app.analysis.sequence import analyze
    from app.analysis.inference import script
    poses = [p for p, _ in script('fajr', 'normal')]
    # Additional standing sample competes only inside the second rakah.
    poses.insert(8, 'standing')
    events = movement_events(poses)
    report = analyze('boundary', 'fajr', events, 'real', 4, 80, normalize_sequence=True)
    assert report.rakahs[0].result == 'OBSERVED_COMPLETE'
    assert report.rakahs[1].stations[0].status == 'DETECTED'
    boundary = events[6].end_ms
    assert all(e.review_rakah_number == 2 for e in report.events if e.start_ms > boundary)


def test_optional_transition_anchor_does_not_invent_missing_sujood():
    from app.analysis.sequence import analyze
    poses = ['takbir', 'standing', 'ruku', 'standing', 'sujood', 'sitting',
             'standing', 'ruku', 'standing', 'sujood', 'sitting', 'sujood',
             'sitting', 'salam_right', 'salam_left']
    report = analyze('partial', 'fajr', movement_events(poses), 'real', 4, 60,
                     normalize_sequence=True, transition_anchors=True)
    assert [s.status for s in report.rakahs[1].stations[:3]] == ['DETECTED'] * 3
    assert report.rakahs[0].stations[-1].status == 'UNCONFIRMED'


def test_confirmed_boundary_anchors_next_standing_even_when_bowing_is_missing():
    from app.analysis.sequence import analyze
    poses = ['takbir', 'standing', 'ruku', 'standing', 'sujood', 'sitting', 'sujood',
             'standing', 'sitting', 'standing', 'sujood', 'sitting', 'sujood',
             'sitting', 'salam_right', 'salam_left']
    report = analyze('missing-bow', 'fajr', movement_events(poses), 'real', 4, 64,
                     normalize_sequence=True)
    assert report.rakahs[0].result == 'OBSERVED_COMPLETE'
    assert report.rakahs[1].stations[0].event_id == 'e7'
    assert report.rakahs[1].stations[1].status == 'UNCONFIRMED'


@pytest.mark.parametrize('extra_cycle', [False, True])
def test_floor_sequence_independent_of_missing_bowing_and_duplicate_samples(extra_cycle):
    from app.analysis.sequence import analyze
    first = ['takbir', 'standing', 'ruku', 'standing', 'sujood', 'sitting', 'sujood']
    second = ['standing', 'sujood', 'takbir', 'sujood', 'sitting', 'takbir',
              'sitting', 'sujood', 'takbir', 'sujood']
    if extra_cycle:
        second += ['sitting', 'sujood']
    second += ['sitting', 'salam_right', 'salam_left']
    events = movement_events(first + second)
    report = analyze('floor', 'fajr', events, 'real', 4, 100, normalize_sequence=True)
    row = report.rakahs[1].stations
    assert row[1].status == 'UNCONFIRMED'
    if not extra_cycle:
        assert [s.status for s in row[3:6]] == ['DETECTED'] * 3
        assert row[3].event_id in ('e8', 'e10')
    else:
        assert [s.status for s in row[3:6]] == ['DETECTED'] * 3
        assert any(e.pose == 'sujood' for e in report.unexpected_movements)


def test_forward_skips_low_confidence_bowing_and_sitting_without_blocking_sujood():
    from app.analysis.sequence import analyze
    from app.analysis.temporal import process
    from app.analysis.inference import Observation
    poses = [('takbir', .99), ('standing', .99), ('ruku', .45),
             ('standing', .99), ('sujood', .99), ('sitting', .62),
             ('sujood', .96), ('sitting', .9), ('salam_right', .99), ('salam_left', .99)]
    events = process([Observation(str(i), i*500, i, p, c, True)
                      for i, (p, c) in enumerate(poses)])
    report = analyze('skip', 'demo', events, 'real', 2, 10, normalize_sequence=True)
    row = report.rakahs[0].stations
    assert row[2].status == 'UNCONFIRMED'
    assert row[3].event_id == 'evt_0003'
    assert row[4].event_id == 'evt_0004'
    assert row[5].status == 'UNCONFIRMED'
    assert row[6].event_id == 'evt_0006'
    assert row[7].event_id == 'evt_0007'


def test_false_early_sitting_and_salam_cannot_advance_the_rakah():
    from app.analysis.sequence import analyze
    poses = ['takbir', 'standing', 'ruku', 'standing', 'sitting', 'sujood',
             'salam_right', 'sujood', 'sitting', 'salam_right', 'sujood',
             'standing', 'standing', 'sujood', 'sitting', 'sujood',
             'sitting', 'salam_right', 'salam_left']
    events = movement_events(poses)
    events[5] = events[5].model_copy(update={'confidence': .8})
    events[7] = events[7].model_copy(update={'confidence': .99})
    report = analyze('false-early', 'fajr', events, 'real', 4, 76, normalize_sequence=True)
    first, second = report.rakahs
    assert first.result == 'OBSERVED_COMPLETE'
    assert first.stations[4].event_id == 'e7'
    assert second.stations[0].event_id in ('e11', 'e12')
    assert second.stations[-2].event_id == 'e17'
    assert any(e.event_id == 'e9' for e in report.unexpected_movements)


@pytest.mark.parametrize("enabled", [False, True])
@pytest.mark.parametrize("straight,visible", [(True, True), (False, True), (True, False)])
def test_bowing_requires_visible_straight_knee(monkeypatch, straight, visible, enabled):
    from app.analysis.prayer_action_predictor import PrayerActionPredictor
    import numpy as np
    from PIL import Image
    from types import SimpleNamespace
    predictor = PrayerActionPredictor.__new__(PrayerActionPredictor)
    lm = [SimpleNamespace(x=.5,y=.2,z=0,visibility=1.) for _ in range(33)]
    for hip, knee, ankle in [(23,25,27),(24,26,28)]:
        lm[hip].x=.5; lm[hip].y=.4
        lm[knee].x=.5; lm[knee].y=.6
        lm[ankle].x=.5 if straight else .7
        lm[ankle].y=.8 if straight else .4
        if not visible: lm[ankle].visibility=.1
    import threading
    predictor._lock = threading.Lock()
    predictor.mirror_sujood_recovery = False
    predictor.ruku_geometry_gate = enabled
    image = Image.new("RGB",(384,512))
    predictor._feature=lambda source:(np.zeros(166),"standard",1.,lm,image)
    predictor._classify=lambda *args:dict(predicted_action="4_Ruku",confidence=.99)
    predictor.draw_landmarks=lambda image,landmarks:image
    result,_=predictor.analyze(image)
    assert result["predicted_action"] == ("4_Ruku" if not enabled or (straight and visible) else "unknown")



def test_experimental_defaults_disabled():
    from app.config import Settings
    settings=Settings(_env_file=None)
    assert not settings.prayer_mirror_sujood_recovery
    assert not settings.prayer_ruku_geometry_gate
    assert not settings.prayer_seated_probability_projection
    assert not settings.prayer_sequence_normalization


def test_default_sequence_keeps_transition_ambiguity():
    from app.analysis.sequence import analyze
    poses=["takbir", "standing", "takbir", "standing", "ruku", "standing",
           "sujood", "sitting", "sujood", "sitting", "salam_right", "salam_left"]
    report=analyze("fixture", "demo", movement_events(poses), "real", 4, 80)
    assert report.overall_result == "REVIEW_REQUIRED"
    assert report.unexpected_movements


@pytest.mark.parametrize("enabled", [False, True])
def test_mirrored_recovery_is_explicit_opt_in(enabled):
    from app.analysis.prayer_action_predictor import PrayerActionPredictor
    from types import SimpleNamespace
    from PIL import Image
    import numpy as np
    import threading
    predictor=PrayerActionPredictor.__new__(PrayerActionPredictor)
    predictor.mirror_sujood_recovery=enabled
    predictor.ruku_geometry_gate=False
    predictor._lock=threading.Lock()
    landmarks=[SimpleNamespace(x=.5,y=.7,z=0,visibility=1.) for _ in range(33)]
    landmarks[23].y=landmarks[24].y=.4
    image=Image.new("RGB", (384,512))
    calls=[]
    predictor._feature=lambda source:(np.zeros(166),"standard",1.,landmarks,image)
    def classify(feature, started, method, visibility):
        calls.append(method)
        return dict(predicted_action="5_Sujud" if method=="mirror_head_down" else "4_Ruku",confidence=.9)
    predictor._classify=classify
    predictor.draw_landmarks=lambda image,landmarks:image
    result,_=predictor.analyze(image)
    assert result["predicted_action"] == ("5_Sujud" if enabled else "4_Ruku")
    assert len(calls)==(2 if enabled else 1)
