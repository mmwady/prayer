"""Reference lifecycle and annotation boundaries; extraction quality is tested separately."""
import copy

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.admin import prayer_references as refs


def points():
    return [{'id': side + name, 'x': x, 'y': y, 'confidence': .9}
            for side,x in [('left',.4),('right',.6)]
            for name,y in [('Shoulder',.25),('Hip',.5),('Knee',.7),('Ankle',.9)]] + [
                {'id':'nose','x':.5,'y':.15,'confidence':.9}]


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(refs, 'ROOT', tmp_path)
    def extraction(video, destination):
        return {'fps': 30, 'frame_count': 24, 'frames': [
            {'index': i, 'time_s': i / 30, 'keypoints': points(),
             'world_keypoints':[{**p,'z':0} for p in points()], 'width':640,'height':480,
             'usable': True}
            for i in range(24)]}
    monkeypatch.setattr(refs, 'extract', extraction)
    app = FastAPI()
    app.include_router(refs.router)
    return TestClient(app)


def upload(client):
    result = client.post('/admin/api/prayer-references', data={'name': 'مرجع', 'view': 'side_left'},
                         files={'file': ('reference.mp4', b'fixture', 'video/mp4')})
    assert result.status_code == 200
    return result.json()['id']


def annotations():
    return {'segments': [{'station': station, 'start_frame': i * 4,
                          'end_frame': i * 4 + 3, 'representative_frame': i * 4 + 1,
                          'excluded_frames': []} for i, station in enumerate(refs.STATIONS)]}


def test_draft_activation_and_snapshot_isolation(client):
    assert client.get('/api/v1/prayer-reference').status_code == 404
    rid = upload(client)
    url = '/admin/api/prayer-references/' + rid
    assert client.post(url + '/activate').status_code == 422
    assert client.put(url, json=annotations()).status_code == 200
    assert client.post(url + '/activate').status_code == 200
    active = client.get('/api/v1/prayer-reference').json()
    assert active['revision'] == 1
    assert len(active['segments'][0]['samples']) == 4
    assert client.put(url, json={'segments': []}).status_code == 200
    assert client.get('/api/v1/prayer-reference').json() == active
    assert client.post(url + '/activate').status_code == 422
    assert client.get('/api/v1/prayer-reference').json() == active


@pytest.mark.parametrize('mutation', ['overlap', 'order', 'bounds', 'excluded', 'representative'])
def test_invalid_annotations_leave_draft_unchanged(client, mutation):
    rid = upload(client)
    body = annotations()
    if mutation == 'overlap':
        body['segments'][1]['start_frame'] = 3
    elif mutation == 'order':
        body['segments'].reverse()
    elif mutation == 'bounds':
        body['segments'][-1]['end_frame'] = 24
    elif mutation == 'excluded':
        body['segments'][0]['excluded_frames'] = [9]
    else:
        body['segments'][0]['representative_frame'] = 9
    url = '/admin/api/prayer-references/' + rid
    assert client.put(url, json=body).status_code == 422
    assert client.get(url).json()['revision'] == 0


def test_activation_rejects_poor_evidence(client):
    rid = upload(client)
    body = annotations()
    body['segments'][0]['excluded_frames'] = [2, 3]
    url = '/admin/api/prayer-references/' + rid
    assert client.put(url, json=body).status_code == 200
    assert client.post(url + '/activate').status_code == 422
    assert client.get('/api/v1/prayer-reference').status_code == 404


def test_normalization_removes_translation_and_scale():
    original = points()
    changed = copy.deepcopy(original)
    for p in changed:
        p['x'], p['y'] = p['x'] * .5 + .1, p['y'] * .5 + .2
    a, b = refs.normalized(original), refs.normalized(changed)
    for name in a:
        assert a[name] == pytest.approx(b[name])
    assert refs.normalized([]) == {}


def test_invalid_file_and_path(client):
    assert client.post('/admin/api/prayer-references', data={'name': 'x', 'view': 'front'},
                       files={'file': ('bad.txt', b'x')}).status_code == 422
    assert client.get('/admin/api/prayer-references/invalid').status_code == 404


def test_angles_and_invalid_coordinates():
    joints = refs.normalized(points())
    assert refs.angles(joints)['left_knee'] == pytest.approx(180)
    invalid = points()
    invalid[0]['x'] = float('nan')
    invalid[4]['x'] = float('nan')
    assert refs.normalized(invalid) == {}


def test_failed_extraction_removes_incomplete_upload(client, monkeypatch):
    def fail(*args):
        raise ValueError('No usable body poses found')
    monkeypatch.setattr(refs, 'extract', fail)
    response = client.post('/admin/api/prayer-references', data={'name': 'x', 'view': 'front'},
                           files={'file': ('bad.mp4', b'bad')})
    assert response.status_code == 422
    assert list(refs.ROOT.iterdir()) == []


def test_world_angles_and_normalization():
    points3d=[{**p,'z':.2} for p in points()]
    result=refs.world_normalized(points3d)
    assert refs.angles3d(result)['left_knee']==pytest.approx(180)
    moved=[{**p, 'x':p['x']*2+1,'y':p['y']*2-2,'z':p['z']*2+.5} for p in points3d]
    other=refs.world_normalized(moved)
    for name in result:
        assert other[name]==pytest.approx(result[name])


def test_v2_activation_needs_world_data_and_calibration_evidence(client):
    rid=upload(client)
    url='/admin/api/prayer-references/'+rid
    assert client.put(url,json=annotations()).status_code==200
    path=refs.folder(rid)/'reference.json'
    original=refs.read(path)
    invalid=copy.deepcopy(original)
    for f in invalid['frames']:
        f['world_keypoints']=[]
    refs.write(path,invalid)
    assert client.post(url+'/activate').status_code==422
    invalid=copy.deepcopy(original)
    invalid['frames'][1]['keypoints']=[p for p in invalid['frames'][1]['keypoints'] if p['id']!='nose']
    refs.write(path,invalid)
    assert client.post(url+'/activate').status_code==422
    refs.write(path,original)
    assert client.post(url+'/activate').status_code==200
    active=client.get('/api/v1/prayer-reference').json()
    assert active['schema_version']==2
    assert active['segments'][0]['samples'][0]['world_angles_degrees']['left_knee']==pytest.approx(180)
