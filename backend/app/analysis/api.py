from fastapi import APIRouter, Header, HTTPException, Request, Response

from .contracts import AnalysisReport, CreateAnalysis, FrameBatch, JobStatus, MOCK_NOTICE

router = APIRouter(prefix='/api/v1/prayer-analyses', tags=['recorded prayer analysis'])


def manager(request):
    return request.app.state.analysis_manager


def own(request, job_id, authorization):
    token = authorization.removeprefix('Bearer ') if authorization and authorization.startswith('Bearer ') else ''
    return manager(request).own(job_id, token)


@router.get('/config')
async def configuration(request: Request):
    s = manager(request).settings
    return dict(inference_provider=s.inference_provider, mock_enabled=s.analysis_allow_mock,
                mock_notice=MOCK_NOTICE, frame_sample_fps=s.frame_sample_fps,
                batch_frames=s.analysis_batch_frames, max_frame_bytes=s.analysis_max_frame_bytes,
                max_dimension=s.analysis_max_dimension, max_frames=s.analysis_max_frames,
                max_duration_ms=s.analysis_max_duration_ms,
                max_request_bytes=s.analysis_max_request_bytes,
                live_enabled=True,
                live_modes=['buffered', 'adaptive'],
                live_buffer_bytes=s.analysis_live_buffer_bytes,
                experimental_postprocessing=dict(
                    mirror_sujood_recovery=s.prayer_mirror_sujood_recovery,
                    ruku_geometry_gate=s.prayer_ruku_geometry_gate,
                    seated_probability_projection=s.prayer_seated_probability_projection,
                    sequence_normalization=s.prayer_sequence_normalization,
                    rakah_transition_anchors=s.prayer_rakah_transition_anchors))


@router.post('', status_code=201)
async def create(body: CreateAnalysis, request: Request):
    job = manager(request).create(body)
    return {**job.snapshot(), 'access_token': job.token}


@router.post('/{job_id}/frames')
async def frames(job_id: str, body: FrameBatch, request: Request,
                 authorization: str | None = Header(default=None)):
    # Validation/storage is bounded to a small batch, serialized on the event loop.
    job = own(request, job_id, authorization)
    if job.live:
        raise HTTPException(409, 'LIVE_REQUIRES_WEBSOCKET')
    return manager(request).upload(job, body)


@router.post('/{job_id}/complete', status_code=202)
async def complete(job_id: str, request: Request, authorization: str | None = Header(default=None)):
    job = own(request, job_id, authorization)
    if job.live:
        raise HTTPException(409, 'LIVE_REQUIRES_LIVE_COMPLETE')
    return manager(request).complete(job)


@router.get('/{job_id}')
async def status(job_id: str, request: Request, authorization: str | None = Header(default=None)):
    return own(request, job_id, authorization).snapshot()


@router.get('/{job_id}/report', response_model=AnalysisReport)
async def report(job_id: str, request: Request, response: Response,
                 authorization: str | None = Header(default=None)):
    job = own(request, job_id, authorization)
    if job.status != JobStatus.COMPLETED:
        raise HTTPException(409, job.error or 'REPORT_NOT_READY')
    response.headers['Cache-Control'] = 'no-store'
    return job.report


@router.get('/{job_id}/evidence/{evidence_id}')
async def evidence(job_id: str, evidence_id: str, request: Request,
                   authorization: str | None = Header(default=None)):
    job = own(request, job_id, authorization)
    if job.status != JobStatus.COMPLETED or evidence_id not in job.evidence:
        raise HTTPException(404, 'EVIDENCE_NOT_FOUND')
    # Bytes snapshot avoids delete/retention races between route and FileResponse.
    return Response(job.evidence[evidence_id].read_bytes(), media_type='image/jpeg',
                    headers={'Cache-Control': 'no-store'})


@router.delete('/{job_id}', status_code=204)
async def delete(job_id: str, request: Request, authorization: str | None = Header(default=None)):
    job = own(request, job_id, authorization)
    manager(request).delete(job)
    session = request.app.state.live_manager.sessions.get(job_id)
    if session:
        await request.app.state.live_manager.release(session)
    return Response(status_code=204)
