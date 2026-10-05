"""Bounded local jobs; lifespan owns workers, cancellation and retention cleanup."""
import asyncio
import base64
import binascii
import hashlib
import hmac
import io
import os
import secrets
import shutil
import tempfile
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from uuid import uuid4

from fastapi import HTTPException
from PIL import Image, ImageOps, UnidentifiedImageError

from .contracts import CreateAnalysis, FrameBatch, JobStatus
from .domain import DEFAULT_POSE_MAP
from .inference import InferencePipeline, ModelNotConfigured
from .sequence import analyze
from .temporal import process


@dataclass
class StoredFrame:
    frame_id: str
    timestamp_ms: int
    sequence_index: int
    path: Path


@dataclass
class Job:
    id: str
    token: str
    request: CreateAnalysis
    path: Path
    created: float = field(default_factory=time.monotonic)
    status: JobStatus = JobStatus.CREATED
    processed_frames: int = 0
    frames: list[StoredFrame] = field(default_factory=list)
    batches: dict[str, str] = field(default_factory=dict)
    error: str | None = None
    report: object | None = None
    evidence: dict[str, Path] = field(default_factory=dict)
    cancelled: threading.Event = field(default_factory=threading.Event)
    active: bool = False
    live: bool = False

    def snapshot(self):
        return dict(job_id=self.id, status=self.status, uploaded_frames=len(self.frames),
                    processed_frames=self.processed_frames, error=self.error)


class JobManager:
    def __init__(self, settings):
        self.settings = settings
        if any(v not in DEFAULT_POSE_MAP for v in settings.analysis_pose_map.values()):
            raise ValueError('Pose mapping values must be canonical physical poses')
        root = Path(settings.analysis_storage_dir).resolve()
        root.mkdir(parents=True, exist_ok=True)
        # Separate app instances (including tests) must not delete a live run.
        self.storage_root = root
        self.root = Path(tempfile.mkdtemp(prefix='run_', dir=root))
        self.lease = self.root / 'lease'
        self.lease.touch()
        self.cleanup_orphans()
        self.jobs: dict[str, Job] = {}
        self.queue = asyncio.Queue(maxsize=settings.analysis_max_jobs)
        self.tasks = []

    async def start(self):
        self.tasks = [asyncio.create_task(self.worker()) for _ in range(self.settings.analysis_workers)]
        self.tasks.append(asyncio.create_task(self.retention()))

    async def close(self):
        for job in self.jobs.values():
            job.cancelled.set()
        # Workers finish current thread work before their sentinel; no orphan tasks.
        self.tasks[-1].cancel()
        await asyncio.gather(self.tasks[-1], return_exceptions=True)
        for _ in self.tasks[:-1]:
            await self.queue.put(None)
        await asyncio.gather(*self.tasks[:-1])
        shutil.rmtree(self.root, ignore_errors=True)

    def create(self, request):
        s = self.settings
        if len(self.jobs) >= s.analysis_max_jobs:
            raise HTTPException(429, 'JOB_CAPACITY_REACHED')
        if request.duration_ms > s.analysis_max_duration_ms:
            raise HTTPException(422, 'VIDEO_TOO_LONG')
        if s.inference_provider == 'mock' and (not s.analysis_allow_mock or request.scenario is None):
            raise HTTPException(409, 'MOCK_REQUIRES_EXPLICIT_DEVELOPMENT_SCENARIO')
        if s.inference_provider == 'real' and request.scenario is not None:
            raise HTTPException(422, 'MOCK_SCENARIO_NOT_ALLOWED')
        if request.scenario in ('normal_fajr', 'normal_dhuhr') and request.scenario != 'normal_' + request.prayer:
            raise HTTPException(422, 'SCENARIO_PRAYER_MISMATCH')
        jid, token = uuid4().hex, secrets.token_urlsafe(32)
        path = self.root / jid
        path.mkdir()
        job = Job(jid, token, request, path)
        self.jobs[jid] = job
        return job

    def own(self, jid, token):
        job = self.jobs.get(jid)
        if not job or not hmac.compare_digest(job.token.encode(), (token or '').encode()):
            raise HTTPException(404, 'ANALYSIS_NOT_FOUND')
        if time.monotonic() - job.created > self.settings.analysis_retention_seconds:
            self.delete(job)
            raise HTTPException(404, 'ANALYSIS_EXPIRED')
        return job

    def upload(self, job, batch: FrameBatch):
        s = self.settings
        if job.status not in (JobStatus.CREATED, JobStatus.UPLOADING):
            raise HTTPException(409, 'UPLOAD_FINALIZED')
        digest = hashlib.sha256(batch.model_dump_json().encode()).hexdigest()
        if batch.batch_id in job.batches:
            if job.batches[batch.batch_id] != digest:
                raise HTTPException(409, 'BATCH_ID_CONFLICT')
            return job.snapshot()
        if len(batch.frames) > s.analysis_batch_frames or len(job.frames) + len(batch.frames) > s.analysis_max_frames:
            raise HTTPException(413, 'FRAME_LIMIT_EXCEEDED')
        seen = {f.frame_id for f in job.frames}
        previous = job.frames[-1] if job.frames else None
        prepared = []
        for f in batch.frames:
            if f.frame_id in seen or f.timestamp_ms >= job.request.duration_ms:
                raise HTTPException(422, 'INVALID_FRAME_ID_OR_TIMESTAMP')
            if previous and (f.timestamp_ms <= previous.timestamp_ms or f.sequence_index <= previous.sequence_index):
                raise HTTPException(422, 'INVALID_TIMESTAMP_ORDER')
            if len(f.jpeg_base64) > ((s.analysis_max_frame_bytes + 2) // 3) * 4:
                raise HTTPException(413, 'FRAME_TOO_LARGE')
            try:
                raw = base64.b64decode(f.jpeg_base64, validate=True)
                if len(raw) > s.analysis_max_frame_bytes:
                    raise HTTPException(413, 'FRAME_TOO_LARGE')
                with Image.open(io.BytesIO(raw)) as image:
                    if image.format != 'JPEG':
                        raise HTTPException(422, 'JPEG_REQUIRED')
                    if max(image.size) > s.analysis_max_dimension or min(image.size) < 1:
                        raise HTTPException(422, 'IMAGE_DIMENSION_LIMIT')
                    image.load()
                    output = io.BytesIO()
                    ImageOps.exif_transpose(image).convert('RGB').save(output, format='JPEG', quality=85)
                    normalized = output.getvalue()
                    if len(normalized) > s.analysis_max_frame_bytes:
                        raise HTTPException(413, 'NORMALIZED_FRAME_TOO_LARGE')
            except (binascii.Error, UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
                raise HTTPException(422, 'INVALID_JPEG') from None
            prepared.append((f, normalized))
            seen.add(f.frame_id)
            previous = f
        # Validate whole batch before committing; rollback disk writes on failure.
        stored = []
        try:
            for f, raw in prepared:
                path = job.path / (uuid4().hex + '.jpg')
                stored.append(StoredFrame(f.frame_id, f.timestamp_ms, f.sequence_index, path))
                with path.open('wb') as output:
                    output.write(raw)
                    if job.live:
                        output.flush()
                        os.fsync(output.fileno())
        except OSError:
            for frame in stored:
                frame.path.unlink(missing_ok=True)
            raise HTTPException(507, 'TEMPORARY_STORAGE_FAILED') from None
        job.frames.extend(stored)
        job.batches[batch.batch_id] = digest
        job.status = JobStatus.UPLOADING
        return job.snapshot()

    def complete(self, job):
        if job.status in (JobStatus.QUEUED, JobStatus.PROCESSING, JobStatus.COMPLETED):
            return job.snapshot()
        if job.status != JobStatus.UPLOADING or not job.frames:
            raise HTTPException(409, 'NO_UPLOADED_FRAMES')
        job.status = JobStatus.QUEUED
        try:
            self.queue.put_nowait(job)
        except asyncio.QueueFull:
            job.status = JobStatus.UPLOADING
            raise HTTPException(429, 'PROCESSING_QUEUE_FULL') from None
        return job.snapshot()

    def delete(self, job):
        job.cancelled.set()
        job.status = JobStatus.CANCELLED
        self.jobs.pop(job.id, None)
        if not job.active:
            shutil.rmtree(job.path, ignore_errors=True)

    async def retention(self):
        while True:
            await asyncio.sleep(min(30, self.settings.analysis_retention_seconds))
            self.lease.touch()
            self.cleanup_orphans()
            for job in list(self.jobs.values()):
                if time.monotonic() - job.created > self.settings.analysis_retention_seconds:
                    self.delete(job)

    def cleanup_orphans(self):
        """Crashed run directories expire; fresh app instances are left alone."""
        expiry = max(60, self.settings.analysis_retention_seconds)
        for path in self.storage_root.glob('run_*'):
            if path == self.root or path.is_symlink() or not path.is_dir():
                continue
            lease = path / 'lease'
            try:
                modified = lease.stat().st_mtime if lease.exists() else path.stat().st_mtime
                if time.time() - modified > expiry:
                    shutil.rmtree(path)
            except FileNotFoundError:
                pass  # Another cleanup completed concurrently.

    async def worker(self):
        while True:
            job = await self.queue.get()
            try:
                if job is None:
                    return
                if job.cancelled.is_set():
                    continue
                job.active = True
                job.status = JobStatus.PROCESSING
                try:
                    report = await asyncio.to_thread(self.run, job)
                    if not job.cancelled.is_set():
                        job.report = report
                        job.status = JobStatus.COMPLETED
                except ModelNotConfigured:
                    job.error = 'MODEL_NOT_CONFIGURED'
                    job.status = JobStatus.FAILED
                except Exception:
                    # No raw frames, keypoints, filenames or secrets in logs/errors.
                    job.error = 'ANALYSIS_PROCESSING_FAILED'
                    job.status = JobStatus.FAILED
                finally:
                    job.active = False
                    if job.cancelled.is_set():
                        shutil.rmtree(job.path, ignore_errors=True)
                        job.status = JobStatus.CANCELLED
            finally:
                self.queue.task_done()

    def run(self, job):
        s = self.settings
        pipeline = InferencePipeline(s.inference_provider, job.request.prayer,
                                     job.request.scenario or 'normal', s.analysis_pose_map,
                                     s.prayer_model_bundle_dir, s.temporal_confidence,
                                     mirror_sujood_recovery=s.prayer_mirror_sujood_recovery,
                                     ruku_geometry_gate=s.prayer_ruku_geometry_gate,
                                     seated_probability_projection=s.prayer_seated_probability_projection)
        observations = []
        try:
            for f in job.frames:
                if job.cancelled.is_set():
                    return None
                observations.append(pipeline.predict(f.path.read_bytes(), f.frame_id,
                                                      f.timestamp_ms, f.sequence_index,
                                                      evidence_path=f.path))
                job.processed_frames += 1
        finally:
            pipeline.close()
        return self.build_report(job, observations, pipeline.model_version)

    def build_report(self, job, observations, model_version):
        s = self.settings
        events = process(observations, confidence=s.temporal_confidence,
                         min_observations=s.temporal_min_observations,
                         min_duration_ms=s.temporal_min_duration_ms, max_gap_ms=s.temporal_max_gap_ms)
        report = analyze(job.id, job.request.prayer, events, s.inference_provider,
                         job.request.sample_fps, len(job.frames), model_version,
                         normalize_sequence=s.prayer_sequence_normalization,
                         transition_anchors=s.prayer_rakah_transition_anchors)
        by_event = {e.event_id: e for e in events}
        frames = {f.frame_id: f for f in job.frames}
        evidence_paths = set()
        for event in report.events:
            if event.representative_frame_id:
                source = frames[event.representative_frame_id]
                eid = secrets.token_urlsafe(24)
                event.evidence_id = eid
                job.evidence[eid] = source.path
                evidence_paths.add(source.path)
        for movement in report.unexpected_movements:
            movement.evidence_id = by_event[movement.event_id].evidence_id
        for rakah in report.rakahs:
            for station in rakah.stations:
                if station.event_id:
                    station.evidence_id = by_event[station.event_id].evidence_id
        # Retain only bounded representative imagery after successful analysis.
        for frame in job.frames:
            if frame.path not in evidence_paths:
                frame.path.unlink(missing_ok=True)
        return report
