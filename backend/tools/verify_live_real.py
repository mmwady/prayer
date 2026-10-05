"""No-body smoke check of live sessions with the actual bundled CPU models.

Synthetic solid images test loading/transport/cleanup, never prayer accuracy.
No LLM calls; no configuration changes. Run from backend/.
"""
import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fastapi.testclient import TestClient
from PIL import Image
from app import main
from app.config import Settings


def verify():
    with tempfile.TemporaryDirectory(prefix='iqtadi_live_') as directory:
        settings = Settings(_env_file=None, inference_provider='real',
                            prayer_guidance_enabled=False, analysis_storage_dir=directory)
        main.get_settings = lambda: settings
        image = io.BytesIO()
        Image.new('RGB', (640, 480), 'black').save(image, format='JPEG')
        with TestClient(main.create_app()) as client:
            response = client.post('/api/v1/prayer-analyses/live', json={
                'prayer': 'demo', 'sample_fps': 4, 'upload_consent': True})
            response.raise_for_status()
            created = response.json()
            url = '/api/v1/prayer-analyses/' + created['job_id']
            headers = {'Authorization': 'Bearer ' + created['access_token']}
            milliseconds = []
            setup_started = time.perf_counter()
            with client.websocket_connect(url + '/live') as ws:
                ws.send_json({'token': created['access_token']})
                assert ws.receive_json()['type'] == 'ready'
                setup_ms = round((time.perf_counter() - setup_started) * 1000, 1)
                for index in range(8):
                    header = json.dumps({'frame_id': f'black_{index}',
                                         'sequence_index': index, 'timestamp_ms': index * 250}).encode()
                    started = time.perf_counter()
                    ws.send_bytes(struct.pack('!I', len(header)) + header + image.getvalue())
                    ack = ws.receive_json()
                    assert ack.get('processed_frames') == index + 1, ack
                    milliseconds.append(round((time.perf_counter() - started) * 1000, 1))
            result = client.post(url + '/live/complete', headers=headers, json={'duration_ms': 2000})
            result.raise_for_status()
            report = client.get(url + '/report', headers=headers).json()
            assert report['analysis_mode'] == 'real' and not report['synthetic']
            assert report['metrics']['detected_stations'] == 0
            assert report['overall_result'] == 'REVIEW_REQUIRED'
            assert not any(event.get('evidence_id') for event in report['events'])
            assert client.delete(url, headers=headers).status_code == 204
            print(json.dumps({'synthetic_black_images': 8, 'analysis_mode': 'real',
                              'detected_stations': 0, 'result': report['overall_result'],
                              'model_version': report['metrics']['model_version'],
                              'setup_ms': setup_ms,
                              'frame_ack_ms': milliseconds, 'deleted': True}))


if __name__ == '__main__':
    verify()
