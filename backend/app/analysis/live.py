"""Consent-based camera sessions. Ordered inference, bounded storage, resumable ACKs.

The bearer token travels in the first WS message, never the URL. Each binary
packet contains a 4-byte big-endian JSON-header length, header, then JPEG bytes.
Only one socket owns a session; buffered ACK means stored, adaptive ACK means processed. Retrying
the identical packet is idempotent, including after disconnect during inference.
"""
import asyncio
import base64
import json
import logging
import shutil
import struct
import time
from typing import Literal
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field

from fastapi import APIRouter, Header, HTTPException, Request, Response, WebSocket, WebSocketDisconnect
from pydantic import Field, ValidationError

from .contracts import Contract, CreateAnalysis, FrameBatch, FrameInput, JobStatus, Prayer, Scenario
from .inference import InferencePipeline, ModelNotConfigured, Observation

router = APIRouter(prefix='/api/v1/prayer-analyses', tags=['live prayer analysis'])
logger = logging.getLogger(__name__)


class CreateLive(Contract):
    prayer: Prayer
    sample_fps: float = Field(gt=0, le=10)
    upload_consent: bool
    scenario: Scenario | None = None
    mode: Literal['buffered', 'adaptive'] = 'adaptive'


class FrameHeader(Contract):
    frame_id: str = Field(pattern=r'^[a-zA-Z0-9_-]{1,64}$')
    sequence_index: int = Field(ge=0)
    timestamp_ms: int = Field(ge=0)


class CompleteLive(Contract):
    duration_ms: int | None = Field(default=None, gt=0)


@dataclass
class Session:
    job: object
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)
    executor: ThreadPoolExecutor = field(default_factory=lambda: ThreadPoolExecutor(max_workers=1))
    pipeline: object | None = None
    observations: list = field(default_factory=list)
    connected: bool = False
    closed: bool = False
    started: float | None = None
    mode: str = 'adaptive'
    worker: asyncio.Task | None = None
    finalizer: asyncio.Task | None = None
    ending: bool = False
    stored_bytes: int = 0
    processing_ms: float = 0


class LiveManager:
    def __init__(self, jobs):
        self.jobs = jobs
        self.sessions = {}
        self.cleanup_task = None

    async def start(self):
        self.cleanup_task = asyncio.create_task(self.cleanup())

    async def cleanup(self):
        while True:
            await asyncio.sleep(10)
            for jid, session in list(self.sessions.items()):
                if jid not in self.jobs.jobs or session.job.cancelled.is_set():
                    await self.release(session)

    async def close(self):
        self.cleanup_task.cancel()
        await asyncio.gather(self.cleanup_task, return_exceptions=True)
        for session in list(self.sessions.values()):
            self.jobs.delete(session.job)
            await self.release(session)

    async def release(self, session):
        async with session.lock:
            session.closed = True
        # Buffered inference does not hold the upload lock. Wait before disposal.
        for task in (session.worker, session.finalizer):
            if task and task is not asyncio.current_task():
                await asyncio.gather(task, return_exceptions=True)
        async with session.lock:
            if session.job.id in self.sessions:
                if session.pipeline:
                    await self.execute(session, session.pipeline.close)
                session.executor.shutdown(wait=True)
                self.sessions.pop(session.job.id, None)
                if session.job.cancelled.is_set():
                    shutil.rmtree(session.job.path, ignore_errors=True)

    def create(self, body):
        if not body.upload_consent:
            raise HTTPException(422, 'UPLOAD_CONSENT_REQUIRED')
        settings = self.jobs.settings
        if len(self.sessions) >= settings.analysis_workers:
            raise HTTPException(429, 'LIVE_CAPACITY_REACHED')
        job = self.jobs.create(CreateAnalysis(
            prayer=body.prayer, sample_fps=body.sample_fps, upload_consent=True,
            duration_ms=settings.analysis_max_duration_ms, scenario=body.scenario))
        job.live = True
        self.sessions[job.id] = Session(job, mode=body.mode)
        return job

    def own(self, jid, token):
        job = self.jobs.own(jid, token)
        if not job.live:
            raise HTTPException(409, 'NOT_A_LIVE_SESSION')
        session = self.sessions.get(jid)
        if not session:
            raise HTTPException(409, 'LIVE_SESSION_FINALIZED')
        return session

    async def execute(self, session, function, *args):
        # Keep MediaPipe creation, use and disposal on the same dedicated thread.
        future = asyncio.get_running_loop().run_in_executor(session.executor, function, *args)
        try:
            return await asyncio.shield(future)
        except asyncio.CancelledError:
            await future  # Never delete files while the thread is using them.
            raise

    def prepare_pipeline(self, session):
        s = self.jobs.settings
        job = session.job
        if session.pipeline is None:
            session.pipeline = InferencePipeline(
                s.inference_provider, job.request.prayer, job.request.scenario or 'normal',
                s.analysis_pose_map, s.prayer_model_bundle_dir, s.temporal_confidence,
                mirror_sujood_recovery=s.prayer_mirror_sujood_recovery,
                ruku_geometry_gate=s.prayer_ruku_geometry_gate,
                seated_probability_projection=s.prayer_seated_probability_projection)

    async def prepare(self, session):
        async with session.lock:
            job = session.job
            if session.closed or job.cancelled.is_set():
                raise HTTPException(404, 'ANALYSIS_NOT_FOUND')
            if session.pipeline is not None:
                # Reconnect must not clear the active buffered worker's file lease.
                return
            job.active = True
            try:
                await self.execute(session, self.prepare_pipeline, session)
                if session.started is None:
                    session.started = time.monotonic()
            except ModelNotConfigured:
                job.status, job.error = JobStatus.FAILED, 'MODEL_NOT_CONFIGURED'
                raise HTTPException(409, job.error) from None
            finally:
                job.active = False

    def predict(self, session, frame):
        started = time.perf_counter()
        self.prepare_pipeline(session)
        job = session.job
        observation = session.pipeline.predict(frame.path.read_bytes(), frame.frame_id,
                                               frame.timestamp_ms, frame.sequence_index,
                                               evidence_path=frame.path)
        session.observations.append(observation)
        job.processed_frames += 1
        session.processing_ms = (time.perf_counter() - started) * 1000
        logger.info('Live frame processed job=%s index=%s mode=%s processing_ms=%.1f pending=%s',
                    job.id, frame.sequence_index, session.mode, session.processing_ms,
                    len(job.frames) - job.processed_frames)

    def snapshot(self, session):
        return dict(**session.job.snapshot(), mode=session.mode,
                    buffered_frames=len(session.job.frames) - session.job.processed_frames,
                    processing_ms=round(session.processing_ms, 1))

    async def drain(self, session):
        """Only one consumer, ordered disk references; never discard queued frames."""
        job = session.job
        while not session.closed and not job.cancelled.is_set():
            async with session.lock:
                if job.processed_frames >= len(job.frames) or job.status == JobStatus.FAILED:
                    return
                frame = job.frames[job.processed_frames]
                job.active = True
            try:
                await self.execute(session, self.predict, session, frame)
            except Exception:
                job.status, job.error = JobStatus.FAILED, 'ANALYSIS_PROCESSING_FAILED'
                logger.exception('Live buffered analysis failed job=%s', job.id)
                return
            finally:
                job.active = False

    def start_drain(self, session):
        if session.worker is None or session.worker.done():
            session.worker = asyncio.create_task(self.drain(session))

    async def frame(self, session, packet):
        s = self.jobs.settings
        if len(packet) < 5 or len(packet) > s.analysis_max_frame_bytes + 1028:
            raise HTTPException(413, 'FRAME_TOO_LARGE')
        size = struct.unpack('!I', packet[:4])[0]
        if not 1 <= size <= 1024 or 4 + size >= len(packet):
            raise HTTPException(422, 'INVALID_FRAME_PACKET')
        try:
            header = FrameHeader.model_validate_json(packet[4:4+size])
        except ValidationError:
            raise HTTPException(422, 'INVALID_FRAME_HEADER') from None
        async with session.lock:
            job = session.job
            if session.closed or job.cancelled.is_set():
                raise HTTPException(404, 'ANALYSIS_NOT_FOUND')
            if session.ending:
                raise HTTPException(409, 'UPLOAD_FINALIZED')
            # Late delivery of captured images remains valid in buffered mode.
            if session.mode == 'adaptive' and session.started is not None and time.monotonic() - session.started >= s.analysis_max_duration_ms / 1000:
                raise HTTPException(422, 'LIVE_DURATION_LIMIT')
            new = header.frame_id not in job.batches
            if new and session.stored_bytes + s.analysis_max_frame_bytes > s.analysis_live_buffer_bytes:
                raise HTTPException(507, 'LIVE_STORAGE_LIMIT')
            received = time.perf_counter()
            item = FrameInput(**header.model_dump(), jpeg_base64=base64.b64encode(packet[4+size:]).decode())
            self.jobs.upload(job, FrameBatch(batch_id=header.frame_id, frames=[item]))
            if new:
                session.stored_bytes += job.frames[-1].path.stat().st_size
            if session.mode == 'buffered':
                self.start_drain(session)
                logger.info('Live frame stored job=%s index=%s storage_ms=%.1f pending=%s',
                            job.id, header.sequence_index, (time.perf_counter()-received)*1000,
                            len(job.frames)-job.processed_frames)
                return dict(type='ack', frame_id=header.frame_id, ack_stage='stored',
                            **self.snapshot(session))
            if job.processed_frames < len(job.frames):
                job.active = True
                try:
                    await self.execute(session, self.predict, session, job.frames[-1])
                except ModelNotConfigured:
                    job.status, job.error = JobStatus.FAILED, 'MODEL_NOT_CONFIGURED'
                    raise HTTPException(409, job.error) from None
                except Exception:
                    job.status, job.error = JobStatus.FAILED, 'ANALYSIS_PROCESSING_FAILED'
                    raise HTTPException(500, job.error) from None
                finally:
                    job.active = False
                    if job.cancelled.is_set():
                        shutil.rmtree(job.path, ignore_errors=True)
            return dict(type='ack', frame_id=header.frame_id, ack_stage='processed', **self.snapshot(session))

    async def complete_buffered(self, session, duration_ms):
        await session.worker
        if session.closed or session.job.cancelled.is_set():
            return
        try:
            await self.finish(session, duration_ms, drained=True)
        except HTTPException:
            # Failure is exposed by the existing private status route.
            if not session.job.cancelled.is_set():
                session.job.status = JobStatus.FAILED
                session.job.error = session.job.error or 'ANALYSIS_PROCESSING_FAILED'

    async def begin_finish(self, session, duration_ms):
        async with session.lock:
            job = session.job
            if session.closed or job.cancelled.is_set():
                raise HTTPException(404, 'ANALYSIS_NOT_FOUND')
            if job.status == JobStatus.FAILED:
                raise HTTPException(409, job.error)
            if not job.frames:
                raise HTTPException(409, 'NO_UPLOADED_FRAMES')
            if duration_ms is not None and (duration_ms <= job.frames[-1].timestamp_ms or
                                            duration_ms > self.jobs.settings.analysis_max_duration_ms):
                raise HTTPException(422, 'INVALID_LIVE_DURATION')
            if not session.ending:
                session.ending = True
                job.status = JobStatus.PROCESSING
                self.start_drain(session)
                session.finalizer = asyncio.create_task(self.complete_buffered(session, duration_ms))
            return self.snapshot(session)

    async def finish(self, session, duration_ms=None, drained=False):
        if session.mode == 'buffered' and not drained:
            return await self.begin_finish(session, duration_ms)
        async with session.lock:
            job = session.job
            if session.closed or job.cancelled.is_set():
                raise HTTPException(404, 'ANALYSIS_NOT_FOUND')
            if not job.frames:
                raise HTTPException(409, 'NO_UPLOADED_FRAMES')
            if job.status == JobStatus.FAILED:
                raise HTTPException(409, job.error)
            s = self.jobs.settings
            observations = list(session.observations)
            first, last = observations[0], observations[-1]
            if duration_ms is not None and (duration_ms <= last.timestamp_ms or duration_ms > s.analysis_max_duration_ms):
                raise HTTPException(422, 'INVALID_LIVE_DURATION')
            # Blind periods at either end are uncertainty, just like interior gaps.
            if first.timestamp_ms > s.temporal_max_gap_ms:
                observations.insert(0, Observation('live_start_gap', 0, -1, 'unknown', 0, False))
            if duration_ms is not None and duration_ms - last.timestamp_ms > s.temporal_max_gap_ms:
                observations.append(Observation('live_end_gap', duration_ms - 1,
                                                last.sequence_index + 1, 'unknown', 0, False))
            job.status = JobStatus.PROCESSING
            job.active = True
            try:
                job.report = await self.execute(session, self.jobs.build_report, job,
                                               observations, session.pipeline.model_version)
                if job.report.synthetic:
                    job.report.notice = 'محاكاة تحليل — النتائج اصطناعية وليست تحليلًا فعليًا للكاميرا'
                if job.cancelled.is_set():
                    raise HTTPException(404, 'ANALYSIS_NOT_FOUND')
                job.status = JobStatus.COMPLETED
            except HTTPException:
                raise
            except Exception:
                job.status, job.error = JobStatus.FAILED, 'ANALYSIS_PROCESSING_FAILED'
                raise HTTPException(500, job.error) from None
            finally:
                job.active = False
        await self.release(session)
        return job.snapshot()


@router.post('/live', status_code=201)
async def create_live(body: CreateLive, request: Request):
    job = request.app.state.live_manager.create(body)
    return {**job.snapshot(), 'access_token': job.token}


@router.post('/{job_id}/live/complete')
async def complete_live(job_id: str, request: Request, response: Response, body: CompleteLive | None = None,
                        authorization: str | None = Header(default=None)):
    token = (authorization or '').removeprefix('Bearer ')
    manager = request.app.state.live_manager
    job = manager.jobs.own(job_id, token)
    if not job.live:
        raise HTTPException(409, 'NOT_A_LIVE_SESSION')
    if job.status == JobStatus.COMPLETED:
        return job.snapshot()
    session = manager.own(job_id, token)
    result = await manager.finish(session, body.duration_ms if body else None)
    if session.mode == 'buffered':
        response.status_code = 202
    return result


@router.websocket('/{job_id}/live')
async def stream(job_id: str, websocket: WebSocket):
    manager = websocket.app.state.live_manager
    session = None
    claimed = False
    await websocket.accept()
    try:
        text = await asyncio.wait_for(websocket.receive_text(), timeout=5)
        if len(text) > 1024:
            raise HTTPException(401, 'AUTH_REQUIRED')
        auth = json.loads(text)
        session = manager.own(job_id, auth.get('token', '') if isinstance(auth, dict) else '')
        if session.connected:
            raise HTTPException(409, 'LIVE_ALREADY_CONNECTED')
        session.connected = claimed = True
        await manager.prepare(session)
        await websocket.send_json(dict(type='ready', **manager.snapshot(session)))
        while True:
            packet = await asyncio.wait_for(websocket.receive_bytes(), timeout=60)
            result = await manager.frame(session, packet)
            await websocket.send_json(result)
    except WebSocketDisconnect:
        pass  # Session survives disconnect for an identical-frame retry.
    except HTTPException as exc:
        try:
            await websocket.send_json(dict(type='error', code=exc.detail))
            await websocket.close(code=1008)
        except (WebSocketDisconnect, RuntimeError):
            pass
    except (asyncio.TimeoutError, ValueError, RuntimeError, KeyError, TypeError):
        try:
            await websocket.close(code=1008)
        except RuntimeError:
            pass
    finally:
        if claimed:
            session.connected = False
