import base64
import io
import time

import pytest
from fastapi.testclient import TestClient
from PIL import Image
from pydantic import ValidationError

from app.analysis.contracts import KeypointResult, AnalysisReport
from app.analysis.domain import stations
from app.analysis.inference import (InferencePipeline, MockKeypointExtractor, MockPoseClassifier,
                                    Observation, script)
from app.analysis.sequence import analyze
from app.analysis.temporal import process
from app.config import Settings
from app import main

BASE = '/api/v1/prayer-analyses'


def jpeg(width=64, height=48, format='JPEG'):
    out = io.BytesIO()
    Image.new('RGB', (width, height), 'green').save(out, format=format)
    return base64.b64encode(out.getvalue()).decode()


def frame(index, timestamp=None, image=None):
    return dict(frame_id=f'frame_{index}', sequence_index=index,
                timestamp_ms=index * 500 if timestamp is None else timestamp,
                jpeg_base64=image or jpeg())


@pytest.fixture
def client(tmp_path, monkeypatch):
    settings = Settings(_env_file=None, analysis_allow_mock=True,
                        analysis_storage_dir=str(tmp_path / 'jobs'), prayer_guidance_enabled=False)
    monkeypatch.setattr(main, 'get_settings', lambda: settings)
    with TestClient(main.create_app()) as c:
        yield c


def create(c, prayer='demo', scenario='normal', duration=12000):
    r = c.post(BASE, json=dict(prayer=prayer, scenario=scenario, duration_ms=duration,
                              sample_fps=2, upload_consent=True))
    assert r.status_code == 201, r.text
    data = r.json()
    return BASE + '/' + data['job_id'], {'Authorization': 'Bearer ' + data['access_token']}


def submit(c, url, headers, count):
    for offset in range(0, count, 8):
        r = c.post(url + '/frames', headers=headers,
                   json={'batch_id': f'batch_{offset}',
                         'frames': [frame(i) for i in range(offset, min(count, offset+8))]})
        assert r.status_code == 200, r.text
    assert c.post(url + '/complete', headers=headers).status_code == 202


def finished(c, url, headers):
    for _ in range(200):
        result = c.get(url, headers=headers).json()
        if result['status'] in ('COMPLETED', 'FAILED'):
            return result
        time.sleep(.01)
    pytest.fail('Worker did not finish')


@pytest.mark.parametrize('prayer', ['demo', 'fajr', 'dhuhr', 'asr', 'maghrib', 'isha'])
def test_complete_prayers_and_additional_sittings(client, prayer):
    length = sum(map(len, stations(prayer))) * 2000
    url, headers = create(client, prayer, duration=length)
    submit(client, url, headers, length // 500)
    assert finished(client, url, headers)['status'] == 'COMPLETED'
    data = client.get(url + '/report', headers=headers).json()
    report = AnalysisReport.model_validate(data)
    assert report.overall_result == 'OBSERVED_COMPLETE'
    assert report.observed_rakahs == len(stations(prayer))
    assert report.synthetic and 'اصطناعية' in report.notice
    assert [[s.station for s in r.stations] for r in report.rakahs] == stations(prayer)
    for rakah in report.rakahs:
        for station in rakah.stations:
            assert station.evidence_id
            eurl = url + '/evidence/' + station.evidence_id
            assert client.get(eurl).status_code == 404
            result = client.get(eurl, headers=headers)
            assert result.status_code == 200
            assert result.headers['cache-control'] == 'no-store'
            Image.open(io.BytesIO(result.content)).verify()
    assert client.post(url + '/frames', headers=headers,
                       json={'batch_id': 'later', 'frames': [frame(999)]}).status_code == 409
    assert client.post(url + '/complete', headers=headers).status_code == 202


@pytest.mark.parametrize('scenario', ['missing_ruku', 'missing_sujood', 'uncertain_pose',
                                     'repeated_movement', 'wrong_sequence', 'incomplete_prayer'])
def test_uncertain_sequences_are_honest(client, scenario):
    duration = len(script('fajr', scenario)) * 2000
    url, headers = create(client, 'fajr', scenario, duration)
    submit(client, url, headers, duration // 500)
    assert finished(client, url, headers)['status'] == 'COMPLETED'
    data = client.get(url + '/report', headers=headers).json()
    assert data['overall_result'] == 'REVIEW_REQUIRED'
    unconfirmed = [s for r in data['rakahs'] for s in r['stations'] if s['status'] == 'UNCONFIRMED']
    assert unconfirmed
    assert all(s['evidence_id'] is None for s in unconfirmed)
    if scenario in ('repeated_movement', 'wrong_sequence'):
        assert data['unexpected_movements']


def test_job_ownership_duplicate_batches_and_finalization(client):
    url, headers = create(client)
    other_url, other_headers = create(client)
    body = {'batch_id': 'one', 'frames': [frame(0), frame(1)]}
    assert client.post(url + '/frames', json=body).status_code == 404
    assert client.post(url + '/frames', headers=other_headers, json=body).status_code == 404
    assert client.get(url, headers=other_headers).status_code == 404
    assert client.get(url, headers={b'Authorization': b'Bearer \xff'}).status_code == 404
    assert client.get(url + '/report', headers=other_headers).status_code == 404
    assert client.delete(url, headers=other_headers).status_code == 404
    assert client.get(url + '/report', headers=headers).status_code == 409
    assert client.post(url + '/complete', headers=headers).status_code == 409
    assert client.post(url + '/frames', headers=headers, json=body).status_code == 200
    assert client.post(url + '/frames', headers=headers, json=body).json()['uploaded_frames'] == 2
    body['frames'][0]['jpeg_base64'] = jpeg(80, 60)
    assert client.post(url + '/frames', headers=headers, json=body).status_code == 409
    assert client.get(other_url, headers=other_headers).json()['uploaded_frames'] == 0
    job = client.app.state.analysis_manager.jobs[url.split('/')[-1]]
    assert job.path.exists()
    assert client.delete(url, headers=headers).status_code == 204
    assert not job.path.exists()
    assert client.get(url, headers=headers).status_code == 404


@pytest.mark.parametrize('kind', ['base64', 'png', 'dimension', 'timestamp', 'duplicate_id', 'order', 'bytes', 'batch'])
def test_invalid_uploads_are_atomic(client, kind):
    url, headers = create(client)
    frames = [frame(0), frame(1)]
    if kind == 'base64': frames[-1]['jpeg_base64'] = '!!!!'
    elif kind == 'png': frames[-1]['jpeg_base64'] = jpeg(format='PNG')
    elif kind == 'dimension': frames[-1]['jpeg_base64'] = jpeg(961, 1)
    elif kind == 'timestamp': frames[-1]['timestamp_ms'] = 12000
    elif kind == 'duplicate_id': frames[-1]['frame_id'] = frames[0]['frame_id']
    elif kind == 'order': frames[-1]['timestamp_ms'] = 0
    elif kind == 'bytes': frames[-1]['jpeg_base64'] = 'A' * 270000
    elif kind == 'batch': frames = [frame(i) for i in range(9)]
    result = client.post(url + '/frames', headers=headers, json={'batch_id': 'bad', 'frames': frames})
    assert result.status_code in (413, 422)
    assert client.get(url, headers=headers).json()['uploaded_frames'] == 0
    assert list(client.app.state.analysis_manager.jobs[url.split('/')[-1]].path.iterdir()) == []


def test_request_limit_consent_and_capacity(client):
    client.app.state.analysis_manager.settings.analysis_max_request_bytes = 1024
    rejected = client.post(BASE, content=b'x' * 1025, headers={'Origin': 'http://localhost:8783'})
    assert rejected.status_code == 413
    assert rejected.headers['access-control-allow-origin'] in ('*', 'http://localhost:8783')
    assert client.post(BASE, json=dict(prayer='demo', duration_ms=12000, sample_fps=2,
                                      upload_consent=False, scenario='normal')).status_code == 422
    client.app.state.analysis_manager.settings.analysis_max_jobs = 1
    create(client)
    assert client.post(BASE, json=dict(prayer='demo', duration_ms=12000, sample_fps=2,
                                      upload_consent=True, scenario='normal')).status_code == 429


def test_mock_is_explicit_and_real_never_falls_back(client):
    settings = client.app.state.analysis_manager.settings
    settings.analysis_allow_mock = False
    response = client.post(BASE, json=dict(prayer='demo', duration_ms=12000, sample_fps=2,
                                         upload_consent=True, scenario='normal'))
    assert response.status_code == 409
    settings.inference_provider = 'real'
    settings.prayer_model_bundle_dir = 'missing-test-bundle'
    url, headers = create(client, scenario=None)
    submit(client, url, headers, 4)
    assert finished(client, url, headers)['error'] == 'MODEL_NOT_CONFIGURED'
    assert client.get(url + '/report', headers=headers).status_code == 409


def test_retention_and_shutdown_cleanup(client):
    url, headers = create(client)
    manager = client.app.state.analysis_manager
    job = manager.jobs[url.split('/')[-1]]
    job.created -= manager.settings.analysis_retention_seconds + 1
    assert client.get(url, headers=headers).status_code == 404
    assert not job.path.exists()


def test_new_manager_never_deletes_a_fresh_live_run(client):
    from app.analysis.jobs import JobManager
    manager = client.app.state.analysis_manager
    url, headers = create(client)
    other = JobManager(manager.settings)
    try:
        assert manager.root.exists()
        assert client.get(url, headers=headers).status_code == 200
    finally:
        import shutil
        shutil.rmtree(other.root)


def test_orphan_run_retention(client):
    import os
    manager = client.app.state.analysis_manager
    stale = manager.storage_root / 'run_stale'
    stale.mkdir()
    lease = stale / 'lease'
    lease.touch()
    old = time.time() - manager.settings.analysis_retention_seconds - 61
    os.utime(lease, (old, old))
    manager.cleanup_orphans()
    assert not stale.exists() and manager.root.exists()


def test_delete_processing_job_finishes_cleanup(client, monkeypatch):
    import threading
    from app.analysis import jobs
    started, release = threading.Event(), threading.Event()
    original = jobs.JobManager.run
    def slow(self, job):
        started.set()
        release.wait(5)
        return original(self, job)
    monkeypatch.setattr(jobs.JobManager, 'run', slow)
    url, headers = create(client)
    submit(client, url, headers, 4)
    assert started.wait(2)
    job = client.app.state.analysis_manager.jobs[url.split('/')[-1]]
    assert client.delete(url, headers=headers).status_code == 204
    assert client.get(url, headers=headers).status_code == 404
    release.set()
    for _ in range(100):
        if not job.path.exists(): break
        time.sleep(.01)
    assert not job.path.exists()


def test_cross_batch_order_and_total_frame_limit(client):
    url, headers = create(client)
    assert client.post(url + '/frames', headers=headers, json={
        'batch_id': 'one', 'frames': [frame(0), frame(1)]}).status_code == 200
    assert client.post(url + '/frames', headers=headers, json={
        'batch_id': 'two', 'frames': [frame(2, timestamp=400)]}).status_code == 422
    client.app.state.analysis_manager.settings.analysis_max_frames = 2
    assert client.post(url + '/frames', headers=headers, json={
        'batch_id': 'two', 'frames': [frame(2)]}).status_code == 413


def test_queue_capacity_is_recoverable(client):
    import asyncio
    manager = client.app.state.analysis_manager
    # A detached full queue exercises recovery without racing the managed worker.
    saved = manager.queue
    full = asyncio.Queue(maxsize=1)
    full.put_nowait('placeholder')
    manager.queue = full
    try:
        url, headers = create(client)
        assert client.post(url + '/frames', headers=headers, json={
            'batch_id': 'one', 'frames': [frame(0)]}).status_code == 200
        assert client.post(url + '/complete', headers=headers).status_code == 429
        assert client.get(url, headers=headers).json()['status'] == 'UPLOADING'
    finally:
        manager.queue = saved


def test_admin_loopback_boundary(client):
    settings = client.app.state.analysis_manager.settings
    settings.prayer_admin_token = 'test-admin-token'
    assert client.get('/admin/prayer').status_code == 403
    assert client.get('/admin/prayer', headers={'Authorization': 'Bearer test-admin-token'}).status_code == 200


def test_keypoint_contract_and_scripted_classifier():
    points = MockKeypointExtractor().extract(b'arbitrary-image-not-analyzed')
    assert len(points.keypoints) == 32 and not points.detected
    assert all(p.x is None and p.confidence == 0 for p in points.keypoints)
    assert MockPoseClassifier('ruku', .96).classify(points).pose == 'ruku'
    invalid = points.model_dump()
    invalid['keypoints'][0]['id'] = 1
    with pytest.raises(ValidationError): KeypointResult.model_validate(invalid)
    invalid = points.model_dump()
    invalid['keypoints'][0]['confidence'] = float('nan')
    with pytest.raises(ValidationError): KeypointResult.model_validate(invalid)


def obs(i, pose='standing', confidence=.96, time_ms=None):
    return Observation(f'f{i}', i * 500 if time_ms is None else time_ms, i, pose, confidence, pose != 'unknown')


def test_temporal_spikes_gaps_order_and_evidence():
    events = process([obs(0), obs(1), obs(2), obs(3, 'ruku'), obs(4), obs(5),
                      obs(6, 'unknown'), obs(7, 'ruku', .3), obs(8, time_ms=9000)])
    assert events[1].pose == 'ruku' and events[1].observation_status == 'detected'
    assert sum(e.observation_status == 'uncertain' for e in events) >= 2
    assert events[0].representative_frame_id == 'f0'
    with pytest.raises(ValueError): process([obs(0), obs(1, time_ms=0)])
    with pytest.raises(ValueError): process([obs(0, time_ms=500), obs(1, time_ms=0)])


def test_single_confident_frame_counts_without_duration_or_consecutive_frames():
    settings = Settings(_env_file=None)
    assert settings.temporal_min_observations == 1
    assert settings.temporal_min_duration_ms == 0
    events = process([obs(0, 'ruku', .9), obs(1, 'unknown', 0), obs(2, 'sujood', .8)],
                     confidence=settings.temporal_confidence,
                     min_observations=settings.temporal_min_observations,
                     min_duration_ms=settings.temporal_min_duration_ms)
    assert [e.pose for e in events] == ['ruku', 'unknown', 'sujood']
    assert [e.observation_status for e in events] == ['detected', 'uncertain', 'detected']
    assert events[0].start_ms == events[0].end_ms == 0
    assert events[0].representative_frame_id == 'f0'
    assert process([obs(0, 'ruku', .64)])[0].observation_status == 'uncertain'
    assert process([obs(0, 'ruku', .65)])[0].observation_status == 'detected'


def test_uncertain_candidate_uses_actual_frame_confidence_without_confirmation():
    events = process([obs(0, 'ruku', .3), obs(1, 'sitting', .55), obs(2, 'unknown', 0)])
    event = events[0]
    assert event.pose == 'unknown' and event.observation_status == 'uncertain'
    assert event.candidate_pose == 'sitting'
    assert event.candidate_confidence == .55
    assert event.candidate_timestamp_ms == 500
    assert event.representative_frame_id == 'f1'
    absent = process([obs(0, 'unknown', 0)])[0]
    assert absent.candidate_pose is None and absent.representative_frame_id is None


@pytest.mark.parametrize('scenario', ['uncertain_pose', 'repeated_movement'])
def test_suspected_evidence_is_private_and_deleted_with_job(client, scenario):
    duration = len(script('fajr', scenario)) * 2000
    url, headers = create(client, 'fajr', scenario, duration)
    submit(client, url, headers, duration // 500)
    assert finished(client, url, headers)['status'] == 'COMPLETED'
    report = client.get(url + '/report', headers=headers).json()
    if scenario == 'uncertain_pose':
        candidates = [e for e in report['events'] if e['candidate_pose'] == 'ruku'
                      and e['observation_status'] == 'uncertain']
        assert candidates and candidates[0]['candidate_confidence'] == .35
    else:
        candidates = report['unexpected_movements']
        assert candidates and all(e['confidence'] is not None for e in candidates)
    evidence_url = url + '/evidence/' + candidates[0]['evidence_id']
    assert client.get(evidence_url).status_code == 404
    image = client.get(evidence_url, headers=headers)
    assert image.status_code == 200 and image.headers['cache-control'] == 'no-store'
    Image.open(io.BytesIO(image.content)).verify()
    assert client.delete(url, headers=headers).status_code == 204
    assert client.get(evidence_url, headers=headers).status_code == 404


def test_incomplete_single_rakah_never_assigned_to_arbitrary_fajr_rakah():
    pipeline = InferencePipeline('mock', 'demo', 'normal', __import__('app.analysis.domain', fromlist=['DEFAULT_POSE_MAP']).DEFAULT_POSE_MAP)
    events = process([pipeline.predict(b'x', f'f{i}', i*500, i) for i in range(24)])
    result = analyze('ambiguous', 'fajr', events, 'mock', 2, 24)
    assert result.overall_result == 'REVIEW_REQUIRED'
    assert result.observed_rakahs == 0
    assert result.unexpected_movements
