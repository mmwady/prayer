"""Video-backed prayer references. Draft edits never mutate the activated snapshot."""
from __future__ import annotations

import json
import math
import threading
from pathlib import Path
from typing import Literal
from uuid import uuid4

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field, model_validator

ROOT = Path(__file__).resolve().parents[2] / 'data' / 'prayer_references'
router = APIRouter(tags=['prayer references'])
LOCK = threading.Lock()
STATIONS = ['standing', 'ruku', 'standing_after_ruku', 'sujood_first', 'sitting', 'sujood_second']
JOINTS = {0: 'nose', 11: 'leftShoulder', 12: 'rightShoulder', 13: 'leftElbow',
          14: 'rightElbow', 15: 'leftWrist', 16: 'rightWrist', 23: 'leftHip',
          24: 'rightHip', 25: 'leftKnee', 26: 'rightKnee', 27: 'leftAnkle', 28: 'rightAnkle'}


class Segment(BaseModel):
    station: Literal['standing', 'ruku', 'standing_after_ruku', 'sujood_first', 'sitting', 'sujood_second']
    start_frame: int = Field(ge=0)
    end_frame: int = Field(ge=0)
    representative_frame: int = Field(ge=0)
    excluded_frames: list[int] = Field(default_factory=list)

    @model_validator(mode='after')
    def bounds(self):
        if not self.start_frame <= self.representative_frame <= self.end_frame:
            raise ValueError('Representative frame must be within the segment')
        if any(i < self.start_frame or i > self.end_frame for i in self.excluded_frames):
            raise ValueError('Excluded frames must be within the segment')
        if self.representative_frame in self.excluded_frames:
            raise ValueError('Representative frame cannot be excluded')
        return self


class Annotation(BaseModel):
    segments: list[Segment] = Field(max_length=6)


def folder(reference_id: str) -> Path:
    if len(reference_id) != 32 or any(c not in '0123456789abcdef' for c in reference_id):
        raise HTTPException(404, 'Reference not found')
    path = ROOT / reference_id
    if not (path / 'reference.json').exists():
        raise HTTPException(404, 'Reference not found')
    return path


def read(path: Path):
    return json.loads(path.read_text(encoding='utf-8'))


def write(path: Path, data):
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=False, allow_nan=False), encoding='utf-8')
    temp.replace(path)


def normalized(points):
    """Translation/scale invariant coordinates; camera view remains part of the reference."""
    visible = {p['id']: p for p in points if .65 <= p['confidence'] <= 1
               and all(math.isfinite(p[a]) and 0 <= p[a] <= 1 for a in ['x', 'y'])}
    for side in ['left', 'right']:
        names = [side + j for j in ['Shoulder', 'Hip', 'Knee', 'Ankle']]
        if all(n in visible for n in names):
            shoulder, hip = visible[names[0]], visible[names[1]]
            scale = math.hypot(shoulder['x'] - hip['x'], shoulder['y'] - hip['y'])
            if scale > .04:
                return {name: {'x': (p['x'] - hip['x']) / scale,
                               'y': (p['y'] - hip['y']) / scale}
                        for name, p in visible.items()}
    return {}


def angles(points):
    result = {}
    for side in ['left', 'right']:
        for joint, triple in {'elbow': ['Shoulder', 'Elbow', 'Wrist'],
                              'hip': ['Shoulder', 'Hip', 'Knee'],
                              'knee': ['Hip', 'Knee', 'Ankle']}.items():
            names = [side + name for name in triple]
            if not all(name in points for name in names):
                continue
            a, b, c = [points[name] for name in names]
            u, v = (a['x'] - b['x'], a['y'] - b['y']), (c['x'] - b['x'], c['y'] - b['y'])
            length = math.hypot(*u) * math.hypot(*v)
            if length > 1e-8:
                cosine = max(-1, min(1, (u[0] * v[0] + u[1] * v[1]) / length))
                result[side + '_' + joint] = math.degrees(math.acos(cosine))
    return result


def world_normalized(points):
    visible = {p['id']: p for p in points if .65 <= p['confidence'] <= 1
               and all(math.isfinite(p[a]) for a in ['x', 'y', 'z'])}
    required = ['leftHip', 'rightHip', 'leftShoulder', 'rightShoulder']
    if not all(n in visible for n in required):
        return {}
    center = {a: (visible['leftHip'][a] + visible['rightHip'][a]) / 2 for a in ['x', 'y', 'z']}
    shoulders = {a: (visible['leftShoulder'][a] + visible['rightShoulder'][a]) / 2
                 for a in ['x', 'y', 'z']}
    scale = math.sqrt(sum((shoulders[a] - center[a]) ** 2 for a in center))
    if scale < .04:
        return {}
    return {n: {a: (p[a] - center[a]) / scale for a in center} for n, p in visible.items()}


def angles3d(points):
    result = {}
    for side in ['left', 'right']:
        for joint, triple in {'elbow': ['Shoulder', 'Elbow', 'Wrist'],
                              'hip': ['Shoulder', 'Hip', 'Knee'],
                              'knee': ['Hip', 'Knee', 'Ankle']}.items():
            names = [side + name for name in triple]
            if not all(n in points for n in names):
                continue
            a, b, c = [points[n] for n in names]
            u = [a[k] - b[k] for k in ['x', 'y', 'z']]
            v = [c[k] - b[k] for k in ['x', 'y', 'z']]
            length = math.sqrt(sum(x*x for x in u) * sum(x*x for x in v))
            if length > 1e-8:
                cosine = max(-1, min(1, sum(x*y for x, y in zip(u, v)) / length))
                result[side + '_' + joint] = math.degrees(math.acos(cosine))
    return result


def extract(video: Path, destination: Path):
    import cv2
    import mediapipe as mp
    cap = cv2.VideoCapture(str(video))
    fps = cap.get(cv2.CAP_PROP_FPS)
    if not cap.isOpened() or not math.isfinite(fps) or fps <= 0:
        cap.release()
        raise ValueError('Cannot decode video or read its frame rate')
    frames = []
    try:
        with mp.solutions.pose.Pose(model_complexity=2, min_detection_confidence=.65,
                                    min_tracking_confidence=.65) as pose:
            while True:
                ok, image = cap.read()
                if not ok:
                    break
                if len(frames) >= 18000:
                    raise ValueError('Video exceeds 18000 frames; upload a shorter clip')
                result = pose.process(cv2.cvtColor(image, cv2.COLOR_BGR2RGB))
                points = []
                world_points = []
                if result.pose_landmarks:
                    for index, name in JOINTS.items():
                        p = result.pose_landmarks.landmark[index]
                        if all(math.isfinite(v) for v in [p.x, p.y, p.visibility]):
                            points.append({'id': name, 'x': p.x, 'y': p.y,
                                           'confidence': p.visibility})
                        if result.pose_world_landmarks:
                            w = result.pose_world_landmarks.landmark[index]
                            if all(math.isfinite(v) for v in [w.x, w.y, w.z, p.visibility]):
                                world_points.append({'id': name, 'x': w.x, 'y': w.y,
                                                     'z': w.z, 'confidence': p.visibility})
                frame_id = len(frames)
                # Images remain aligned with source frame indices even when pose detection fails.
                if not cv2.imwrite(str(destination / f'{frame_id}.jpg'), image):
                    raise ValueError('Failed to save a video frame')
                frames.append({'index': frame_id, 'time_s': frame_id / fps,
                               'keypoints': points, 'world_keypoints': world_points,
                               'width': image.shape[1], 'height': image.shape[0],
                               'usable': bool(normalized(points))})
    finally:
        cap.release()
    if not frames or not any(f['usable'] for f in frames):
        raise ValueError('No usable body poses found in this video')
    return {'fps': fps, 'frame_count': len(frames), 'frames': frames}


@router.get('/admin/prayer')
def page():
    return FileResponse(Path(__file__).with_name('prayer.html'))


@router.post('/admin/api/prayer-references')
def upload(file: UploadFile = File(...), name: str = Form(...),
           view: Literal['side_left', 'side_right', 'front', 'oblique_left', 'oblique_right'] = Form(...)):
    if not name.strip() or len(name) > 120:
        raise HTTPException(422, 'Enter a name of up to 120 characters')
    if not (file.filename or '').lower().endswith('.mp4'):
        raise HTTPException(422, 'Upload an MP4 video')
    reference_id = uuid4().hex
    path = ROOT / reference_id
    path.mkdir(parents=True)
    try:
        with (path / 'video.mp4').open('wb') as target:
            size = 0
            while chunk := file.file.read(1024 * 1024):
                size += len(chunk)
                if size > 200 * 1024 * 1024:
                    raise HTTPException(413, 'Video limit is 200 MB')
                target.write(chunk)
        with LOCK:
            data = extract(path / 'video.mp4', path)
        data.update({'id': reference_id, 'name': name.strip(), 'view': view,
                     'schema_version': 2, 'segments': [], 'revision': 0})
        write(path / 'reference.json', data)
        return data
    except Exception as error:
        import shutil
        shutil.rmtree(path)
        if isinstance(error, HTTPException):
            raise
        if isinstance(error, (ValueError, ImportError)):
            raise HTTPException(422, str(error)) from error
        raise HTTPException(500, 'Video processing failed') from error
    finally:
        file.file.close()


@router.get('/admin/api/prayer-references')
def listing():
    active = read(ROOT / 'active.json') if (ROOT / 'active.json').exists() else None
    return {'references': [{k: d[k] for k in ['id', 'name', 'view', 'revision', 'frame_count']}
                           for p in sorted(ROOT.glob('*/reference.json')) for d in [read(p)]],
            'active': {'id': active['id'], 'revision': active['revision']} if active else None}


@router.get('/admin/api/prayer-references/{reference_id}')
def detail(reference_id: str):
    return read(folder(reference_id) / 'reference.json')


@router.get('/admin/api/prayer-references/{reference_id}/frames/{index}')
def image(reference_id: str, index: int):
    path = folder(reference_id)
    if index < 0 or not (path / f'{index}.jpg').exists():
        raise HTTPException(404, 'Frame not found')
    return FileResponse(path / f'{index}.jpg')


@router.put('/admin/api/prayer-references/{reference_id}')
def annotate(reference_id: str, body: Annotation):
    with LOCK:
        path = folder(reference_id) / 'reference.json'
        data = read(path)
        seen = set()
        previous_end = -1
        previous_order = -1
        for segment in body.segments:
            order = STATIONS.index(segment.station)
            if segment.station in seen or order <= previous_order:
                raise HTTPException(422, 'Stations must be unique and in prayer order')
            if segment.start_frame <= previous_end or segment.end_frame >= data['frame_count']:
                raise HTTPException(422, 'Segments overlap or exceed the video')
            seen.add(segment.station)
            previous_end, previous_order = segment.end_frame, order
        data['segments'] = [s.model_dump() for s in body.segments]
        data['revision'] += 1
        write(path, data)
    return data


def compile_reference(data):
    if [s['station'] for s in data['segments']] != STATIONS:
        raise HTTPException(422, 'Define all six stations in order before activation')
    compiled = []
    for segment in data['segments']:
        samples = []
        excluded = set(segment['excluded_frames'])
        for frame in data['frames'][segment['start_frame']:segment['end_frame'] + 1]:
            if frame['index'] not in excluded:
                points = normalized(frame['keypoints'])
                if points:
                    world = world_normalized(frame.get('world_keypoints', []))
                    samples.append({'frame': frame['index'], 'joints': points,
                                    'angles_degrees': angles(points), 'world_joints': world,
                                    'world_angles_degrees': angles3d(world)})
        if len(samples) < 3 or segment['representative_frame'] not in {s['frame'] for s in samples}:
            raise HTTPException(422, f"{segment['station']}: select at least three usable frames and a usable representative")
        representative = data['frames'][segment['representative_frame']]
        if data['schema_version'] >= 2 and (
            sum(bool(s['world_joints']) for s in samples) < 3
            or not world_normalized(representative.get('world_keypoints', []))
        ):
            raise HTTPException(422, f"{segment['station']}: insufficient 3D data; review the segment or re-upload")
        # Observed ranges describe this recording; they are not calibrated acceptance tolerances.
        ranges = {}
        for name in JOINTS.values():
            values = [s['joints'][name] for s in samples if name in s['joints']]
            if len(values) >= 3:
                ranges[name] = {axis: {'min': min(p[axis] for p in values),
                                       'max': max(p[axis] for p in values)} for axis in ['x', 'y']}
        angle_ranges = {}
        for name in {name for s in samples for name in s['angles_degrees']}:
            values = [s['angles_degrees'][name] for s in samples if name in s['angles_degrees']]
            if len(values) >= 3:
                angle_ranges[name] = {'min': min(values), 'max': max(values)}
        compiled.append({**segment, 'samples': samples, 'observed_joint_ranges': ranges,
                         'observed_angle_ranges_degrees': angle_ranges,
                         'representative_keypoints': representative['keypoints'],
                         'image_aspect_ratio': representative.get('width', 1) / representative.get('height', 1)})
    if data['schema_version'] >= 2:
        standing = compiled[0]['representative_keypoints']
        valid = {p['id'] for p in standing if p['confidence'] >= .65 and
                 all(math.isfinite(p[a]) and 0 <= p[a] <= 1 for a in ['x', 'y'])}
        if not {'nose', 'leftShoulder', 'rightShoulder', 'leftHip', 'rightHip',
                'leftKnee', 'rightKnee', 'leftAnkle', 'rightAnkle'} <= valid:
            raise HTTPException(422, 'Standing representative must show the head, torso and both legs clearly for calibration')
    return {k: data[k] for k in ['id', 'name', 'view', 'schema_version', 'revision']} | {
        'normalization': 'visible-side-hip-origin-torso-scale-v1',
        'world_coordinate_space': 'mediapipe_world_meters',
        'world_normalization': 'hip-center-torso-scale-v1',
        'min_joint_confidence': .65, 'segments': compiled}


@router.post('/admin/api/prayer-references/{reference_id}/activate')
def activate(reference_id: str):
    with LOCK:
        data = compile_reference(read(folder(reference_id) / 'reference.json'))
        write(ROOT / 'active.json', data)
    return {'id': data['id'], 'revision': data['revision'], 'status': 'active'}


@router.get('/api/v1/prayer-reference')
def active_reference():
    if not (ROOT / 'active.json').exists():
        raise HTTPException(404, 'No activated prayer reference')
    return read(ROOT / 'active.json')
