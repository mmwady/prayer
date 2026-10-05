import base64
import json
import struct
import threading
import io
import time

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.analysis.inference import InferencePipeline
from app.config import Settings
from app import main

BASE = '/api/v1/prayer-analyses'

@pytest.fixture
def client(tmp_path, monkeypatch):
    settings = Settings(_env_file=None, analysis_allow_mock=True,
                        analysis_storage_dir=str(tmp_path / 'jobs'), prayer_guidance_enabled=False)
    monkeypatch.setattr(main, 'get_settings', lambda: settings)
    with TestClient(main.create_app()) as c:
        yield c

def jpeg(width=64, height=48):
    output = io.BytesIO()
    Image.new('RGB', (width, height), 'green').save(output, format='JPEG')
    return base64.b64encode(output.getvalue()).decode()


def create_live(client, **changes):
    body = dict(prayer='demo', sample_fps=4, upload_consent=True, scenario='normal')
    body.update(changes)
    return client.post(BASE + '/live', json=body)


def session(client):
    result = create_live(client)
    assert result.status_code == 201, result.text
    data = result.json()
    return BASE + '/' + data['job_id'], {'Authorization': 'Bearer ' + data['access_token']}, data['access_token']


def packet(index, timestamp=None, image=None):
    header = json.dumps(dict(frame_id=f'live_{index}', sequence_index=index,
                             timestamp_ms=index * 250 if timestamp is None else timestamp)).encode()
    return struct.pack('!I', len(header)) + header + base64.b64decode(image or jpeg())


def connect(client, url, token):
    ws = client.websocket_connect(url + '/live')
    return ws


def test_live_infers_before_end_and_reconnect_retry_is_idempotent(client, monkeypatch):
    calls = []
    original = InferencePipeline.predict
    def spy(self, *args, **kwargs):
        calls.append((args[1], threading.get_ident()))
        return original(self, *args, **kwargs)
    monkeypatch.setattr(InferencePipeline, 'predict', spy)
    url, headers, token = session(client)
    with connect(client, url, token) as ws:
        ws.send_json({'token': token})
        assert ws.receive_json()['type'] == 'ready'
        ws.send_bytes(packet(0))
        ack = ws.receive_json()
        assert ack['processed_frames'] == 1
        assert calls and client.get(url + '/report', headers=headers).status_code == 409
    # Reconnect and resend after an uncertain/lost ACK: no duplicate inference.
    with connect(client, url, token) as ws:
        ws.send_json({'token': token})
        assert ws.receive_json()['uploaded_frames'] == 1
        ws.send_bytes(packet(0))
        assert ws.receive_json()['processed_frames'] == 1
        for i in range(1, 80):
            ws.send_bytes(packet(i))
            assert ws.receive_json()['processed_frames'] == i + 1
    assert len(calls) == 80
    assert len({thread for _, thread in calls}) == 1
    assert client.post(url + '/live/complete', headers=headers).status_code == 200
    data = client.get(url + '/report', headers=headers).json()
    assert data['analysis_mode'] == 'mock'
    assert data['overall_result'] == 'OBSERVED_COMPLETE'
    assert client.post(url + '/live/complete', headers=headers).status_code == 200
    assert client.post(url + '/frames', headers=headers, json={'batch_id': 'x', 'frames': []}).status_code == 422
    assert client.post(url + '/complete', headers=headers).status_code == 409
    eid = next(e['evidence_id'] for e in data['events'] if e.get('evidence_id'))
    assert client.get(url + '/evidence/' + eid, headers=headers).status_code == 200
    assert client.get(url + '/evidence/' + eid).status_code == 404
    assert client.delete(url, headers=headers).status_code == 204
    assert client.get(url, headers=headers).status_code == 404


def test_live_consent_capacity_and_exclusive_socket(client):
    assert create_live(client, upload_consent=False).status_code == 422
    url, headers, token = session(client)
    assert create_live(client).status_code == 429
    with connect(client, url, token) as ws:
        ws.send_json({'token': token})
        assert ws.receive_json()['type'] == 'ready'
        with connect(client, url, token) as other:
            other.send_json({'token': token})
            assert other.receive_json()['code'] == 'LIVE_ALREADY_CONNECTED'
        assert client.post(url + '/live/complete', headers=headers).status_code == 409
    assert client.delete(url, headers=headers).status_code == 204
    assert create_live(client).status_code == 201


@pytest.mark.parametrize('token', ['', 'wrong', 'Bearer wrong'])
def test_live_ownership(client, token):
    url, headers, _ = session(client)
    with connect(client, url, token) as ws:
        ws.send_json({'token': token})
        assert ws.receive_json()['code'] == 'ANALYSIS_NOT_FOUND'
    assert client.post(url + '/live/complete').status_code == 404
    assert client.get(url, headers=headers).json()['uploaded_frames'] == 0


@pytest.mark.parametrize('bad', ['header', 'bytes', 'jpeg', 'timestamp', 'conflict', 'order'])
def test_live_invalid_packets_preserve_committed_state(client, bad):
    url, headers, token = session(client)
    with connect(client, url, token) as ws:
        ws.send_json({'token': token}); ws.receive_json()
        ws.send_bytes(packet(0)); ws.receive_json()
        malformed = {
            'header': b'\x00\x00\x10\x00' + b'{}',
            'bytes': b'0' * 201029,
            'jpeg': packet(1, image=base64.b64encode(b'not an image').decode()),
            'timestamp': packet(1, timestamp=0),
            'conflict': packet(0, image=jpeg(80, 60)),
            'order': packet(0, timestamp=500),
        }[bad]
        ws.send_bytes(malformed)
        assert ws.receive_json()['type'] == 'error'
    state = client.get(url, headers=headers).json()
    assert state['uploaded_frames'] == state['processed_frames'] == 1


def test_live_gap_is_uncertain_and_cancel_closes_pipeline(client, monkeypatch):
    closed = []
    monkeypatch.setattr(InferencePipeline, 'close', lambda self: closed.append(True))
    url, headers, token = session(client)
    with connect(client, url, token) as ws:
        ws.send_json({'token': token}); ws.receive_json()
        for i, timestamp in enumerate([0, 250, 4000, 4250]):
            ws.send_bytes(packet(i, timestamp)); ws.receive_json()
    assert client.post(url + '/live/complete', headers=headers).status_code == 200
    report = client.get(url + '/report', headers=headers).json()
    assert report['overall_result'] == 'REVIEW_REQUIRED'
    assert any(e['observation_status'] == 'uncertain' and e['representative_frame_id'] is None
               for e in report['events'])
    assert closed == [True]
    url, headers, token = session(client)
    path = client.app.state.analysis_manager.jobs[url.split('/')[-1]].path
    with connect(client, url, token) as ws:
        ws.send_json({'token': token}); ws.receive_json()
        ws.send_bytes(packet(0)); ws.receive_json()
        assert client.delete(url, headers=headers).status_code == 204
        ws.send_bytes(packet(1))
        assert ws.receive_json()['code'] == 'ANALYSIS_NOT_FOUND'
    assert len(closed) == 2 and not path.exists()


def test_live_limits_and_real_mode_does_not_fall_back(client):
    settings = client.app.state.analysis_manager.settings
    settings.inference_provider = 'real'
    settings.prayer_model_bundle_dir = 'missing-live-weights'
    result = create_live(client, scenario=None)
    assert result.status_code == 201
    data = result.json()
    url = BASE + '/' + data['job_id']
    headers = {'Authorization': 'Bearer ' + data['access_token']}
    with connect(client, url, data['access_token']) as ws:
        ws.send_json({'token': data['access_token']})
        assert ws.receive_json()['code'] == 'MODEL_NOT_CONFIGURED'
    assert client.get(url, headers=headers).json()['status'] == 'FAILED'
    assert client.post(url + '/live/complete', headers=headers).status_code == 409
    client.delete(url, headers=headers)
    settings.inference_provider = 'mock'; settings.analysis_max_frames = 1
    url, headers, token = session(client)
    with connect(client, url, token) as ws:
        ws.send_json({'token': token}); ws.receive_json()
        ws.send_bytes(packet(0)); ws.receive_json()
        ws.send_bytes(packet(1))
        assert ws.receive_json()['code'] == 'FRAME_LIMIT_EXCEEDED'
    assert client.post(url + '/live/complete', headers=headers).status_code == 200


def test_live_leading_and_trailing_blind_time_cannot_be_complete(client):
    url, headers, token = session(client)
    with connect(client, url, token) as ws:
        ws.send_json({'token': token}); ws.receive_json()
        for i in range(80):
            ws.send_bytes(packet(i, timestamp=2000 + i * 250)); ws.receive_json()
    assert client.post(url + '/live/complete', headers=headers,
                       json={'duration_ms': 21000}).status_code == 422
    assert client.post(url + '/live/complete', headers=headers,
                       json={'duration_ms': 24000}).status_code == 200
    report = client.get(url + '/report', headers=headers).json()
    assert report['overall_result'] == 'REVIEW_REQUIRED'
    assert len([e for e in report['events'] if e['observation_status'] == 'uncertain']) >= 2


def test_live_delete_during_inference_waits_before_closing_model_and_storage(client, monkeypatch):
    entered, continue_inference = threading.Event(), threading.Event()
    threads = []
    original = InferencePipeline.predict
    def held(self, *args, **kwargs):
        threads.append(threading.get_ident())
        entered.set()
        assert continue_inference.wait(5)
        return original(self, *args, **kwargs)
    monkeypatch.setattr(InferencePipeline, 'predict', held)
    monkeypatch.setattr(InferencePipeline, 'close', lambda self: threads.append(threading.get_ident()))
    url, headers, token = session(client)
    job = client.app.state.analysis_manager.jobs[url.split('/')[-1]]
    deletion = []
    with connect(client, url, token) as ws:
        ws.send_json({'token': token}); ws.receive_json()
        ws.send_bytes(packet(0))
        assert entered.wait(3)
        deleter = threading.Thread(target=lambda: deletion.append(client.delete(url, headers=headers).status_code))
        deleter.start()
        assert job.cancelled.wait(3)
        assert job.path.exists()  # No use-after-delete in the inference thread.
        continue_inference.set()
        deleter.join(5)
        assert deletion == [204]
    assert threads[0] == threads[1] and not job.path.exists()


def wait_completed(client, url, headers):
    for _ in range(150):
        state = client.get(url, headers=headers).json()
        if state['status'] == 'COMPLETED':
            return state
        assert state['status'] != 'FAILED', state
        time.sleep(.02)
    pytest.fail('Buffered report did not complete')


def test_buffered_ack_is_storage_only_and_slow_inference_never_drops(client, monkeypatch):
    entered, resume = threading.Event(), threading.Event()
    calls, threads = [], []
    original = InferencePipeline.predict
    def slow(self, *args, **kwargs):
        entered.set()
        assert resume.wait(5)
        calls.append(args[1]); threads.append(threading.get_ident())
        return original(self, *args, **kwargs)
    monkeypatch.setattr(InferencePipeline, 'predict', slow)
    data = create_live(client, mode='buffered').json()
    url, token = BASE + '/' + data['job_id'], data['access_token']
    headers = {'Authorization': 'Bearer ' + token}
    try:
        with connect(client, url, token) as ws:
            ws.send_json({'token': token})
            assert ws.receive_json()['mode'] == 'buffered'
            for i in range(60):
                ws.send_bytes(packet(i)); ack = ws.receive_json()
                assert ack['ack_stage'] == 'stored'
                assert ack['uploaded_frames'] == i + 1
                assert ack['processed_frames'] == 0
            assert entered.wait(3)
        # Retrying the last saved packet after a lost ACK keeps one copy.
        with connect(client, url, token) as ws:
            ws.send_json({'token': token}); ws.receive_json()
            ws.send_bytes(packet(59))
            assert ws.receive_json()['uploaded_frames'] == 60
        result = client.post(url + '/live/complete', headers=headers, json={'duration_ms': 15000})
        assert result.status_code == 202
        assert result.json()['buffered_frames'] == 60
        assert client.post(url + '/live/complete', headers=headers,
                           json={'duration_ms': 15000}).status_code == 202
        assert client.get(url + '/report', headers=headers).status_code == 409
    finally:
        resume.set()
    state = wait_completed(client, url, headers)
    assert state['processed_frames'] == state['uploaded_frames'] == 60
    assert calls == [f'live_{i}' for i in range(60)]
    assert len(set(threads)) == 1
    assert client.get(url + '/report', headers=headers).json()['metrics']['processed_frames'] == 60


def test_buffered_limits_reject_explicitly_without_discarding_saved_frames(client):
    settings = client.app.state.analysis_manager.settings
    settings.analysis_live_buffer_bytes = settings.analysis_max_frame_bytes
    data = create_live(client, mode='buffered').json()
    url, token = BASE + '/' + data['job_id'], data['access_token']
    headers = {'Authorization': 'Bearer ' + token}
    with connect(client, url, token) as ws:
        ws.send_json({'token': token}); ws.receive_json()
        ws.send_bytes(packet(0)); ws.receive_json()
        ws.send_bytes(packet(0))
        assert ws.receive_json()['uploaded_frames'] == 1
        ws.send_bytes(packet(1))
        assert ws.receive_json()['code'] == 'LIVE_STORAGE_LIMIT'
    assert client.get(url, headers=headers).json()['uploaded_frames'] == 1
    assert client.post(url + '/live/complete', headers=headers,
                       json={'duration_ms': 1000}).status_code == 202
    assert wait_completed(client, url, headers)['processed_frames'] == 1


def test_live_modes_are_explicit_and_validated(client):
    config = client.get(BASE + '/config').json()
    assert config['live_modes'] == ['buffered', 'adaptive']
    assert config['live_buffer_bytes'] > 0
    assert create_live(client, mode='unsupported').status_code == 422


def test_buffered_late_delivery_preserves_capture_timestamp(client):
    data = create_live(client, mode='buffered').json()
    url, token = BASE + '/' + data['job_id'], data['access_token']
    headers = {'Authorization': 'Bearer ' + token}
    with connect(client, url, token) as ws:
        ws.send_json({'token': token}); ws.receive_json()
        live = client.app.state.live_manager.sessions[data['job_id']]
        live.started -= 7200  # Captured earlier, delivery was delayed.
        ws.send_bytes(packet(0, timestamp=250))
        assert ws.receive_json()['uploaded_frames'] == 1
    assert client.post(url + '/live/complete', headers=headers,
                       json={'duration_ms': 1000}).status_code == 202
    assert wait_completed(client, url, headers)['processed_frames'] == 1


def test_buffered_cancel_waits_for_current_inference_then_discards_only_on_explicit_delete(client, monkeypatch):
    entered, resume = threading.Event(), threading.Event()
    original = InferencePipeline.predict
    def held(self, *args, **kwargs):
        entered.set(); assert resume.wait(5)
        return original(self, *args, **kwargs)
    monkeypatch.setattr(InferencePipeline, 'predict', held)
    data = create_live(client, mode='buffered').json()
    url, token = BASE + '/' + data['job_id'], data['access_token']
    headers = {'Authorization': 'Bearer ' + token}
    job = client.app.state.analysis_manager.jobs[data['job_id']]
    deletion = []
    try:
        with connect(client, url, token) as ws:
            ws.send_json({'token': token}); ws.receive_json()
            for i in range(3):
                ws.send_bytes(packet(i)); ws.receive_json()
            assert entered.wait(3)
        with connect(client, url, token) as ws:
            ws.send_json({'token': token}); ws.receive_json()
            assert job.active
        assert client.post(url + '/live/complete', headers=headers).status_code == 202
        deleter = threading.Thread(target=lambda: deletion.append(client.delete(url, headers=headers).status_code))
        deleter.start()
        assert job.cancelled.wait(3)
        assert job.path.exists()
    finally:
        resume.set()
    deleter.join(5)
    assert deletion == [204] and not job.path.exists()
    assert data['job_id'] not in client.app.state.live_manager.sessions
