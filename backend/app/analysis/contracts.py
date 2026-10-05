"""Version 1 contracts. No anatomical topology is assumed for the 32 slots."""
from enum import Enum
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class Contract(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)


class Keypoint(Contract):
    id: int = Field(ge=0, le=31)
    x: float | None = Field(default=None, ge=0, le=1)
    y: float | None = Field(default=None, ge=0, le=1)
    confidence: float = Field(ge=0, le=1)

    @model_validator(mode='after')
    def coordinates(self):
        if (self.x is None) != (self.y is None):
            raise ValueError('Both coordinates must be present or missing')
        if self.x is None and self.confidence != 0:
            raise ValueError('Missing slot must have confidence zero')
        return self


class KeypointResult(Contract):
    # Top-left image origin; x right, y down, normalized AFTER EXIF orientation.
    # ids 0..31 are model-defined slots, not ML Kit/MediaPipe landmark ids.
    keypoints: list[Keypoint] = Field(min_length=32, max_length=32)
    detected: bool

    @model_validator(mode='after')
    def ordering(self):
        if [p.id for p in self.keypoints] != list(range(32)):
            raise ValueError('Exactly 32 ordered slots (0..31) are required')
        if not self.detected and any(p.confidence != 0 or p.x is not None for p in self.keypoints):
            raise ValueError('No detection requires all slots missing')
        return self


class PosePrediction(Contract):
    pose: str = Field(min_length=1, max_length=64)
    confidence: float = Field(ge=0, le=1)
    model_version: str = Field(min_length=1, max_length=128)


Prayer = Literal['fajr', 'dhuhr', 'asr', 'maghrib', 'isha', 'demo']
Scenario = Literal['normal', 'normal_fajr', 'normal_dhuhr', 'missing_ruku',
                   'missing_sujood', 'uncertain_pose', 'repeated_movement',
                   'wrong_sequence', 'incomplete_prayer']


class CreateAnalysis(Contract):
    prayer: Prayer
    duration_ms: int = Field(gt=0)
    sample_fps: float = Field(gt=0, le=10)
    upload_consent: Literal[True]
    scenario: Scenario | None = None


class FrameInput(Contract):
    frame_id: str = Field(pattern=r'^[a-zA-Z0-9_-]{1,64}$')
    timestamp_ms: int = Field(ge=0)
    sequence_index: int = Field(ge=0)
    jpeg_base64: str = Field(min_length=4)


class FrameBatch(Contract):
    batch_id: str = Field(pattern=r'^[a-zA-Z0-9_-]{1,64}$')
    frames: list[FrameInput] = Field(min_length=1)


class JobStatus(str, Enum):
    CREATED = 'CREATED'
    UPLOADING = 'UPLOADING'
    QUEUED = 'QUEUED'
    PROCESSING = 'PROCESSING'
    COMPLETED = 'COMPLETED'
    FAILED = 'FAILED'
    CANCELLED = 'CANCELLED'


class Result(str, Enum):
    OBSERVED_COMPLETE = 'OBSERVED_COMPLETE'
    REVIEW_REQUIRED = 'REVIEW_REQUIRED'


class StationStatus(str, Enum):
    DETECTED = 'DETECTED'
    UNCONFIRMED = 'UNCONFIRMED'


class MovementEvent(Contract):
    event_id: str
    pose: str
    start_ms: int
    end_ms: int
    confidence: float = Field(ge=0, le=1)
    representative_frame_id: str | None
    observation_status: Literal['detected', 'uncertain']
    candidate_pose: str | None = None
    candidate_confidence: float | None = Field(default=None, ge=0, le=1)
    candidate_timestamp_ms: int | None = None
    evidence_id: str | None = None
    review_rakah_number: int | None = None
    review_before_station_index: int | None = None


class StationReport(Contract):
    station: str
    arabic_label: str
    status: StationStatus = StationStatus.UNCONFIRMED
    confidence: float | None = None
    timestamp_ms: int | None = None
    event_id: str | None = None
    evidence_id: str | None = None


class RakahReport(Contract):
    rakah_number: int
    result: Result
    stations: list[StationReport]
    notes: list[str]


class UnexpectedMovement(Contract):
    event_id: str
    pose: str
    start_ms: int
    reason: Literal['ambiguous', 'out_of_sequence_or_repeated']
    confidence: float | None = Field(default=None, ge=0, le=1)
    timestamp_ms: int | None = None
    evidence_id: str | None = None
    review_rakah_number: int | None = None
    review_before_station_index: int | None = None


class Metrics(Contract):
    detected_stations: int
    unconfirmed_stations: int
    unexpected_movements: int
    processed_frames: int
    sample_fps: float
    inference_provider: Literal['mock', 'real']
    model_version: str


MOCK_NOTICE = 'محاكاة تحليل — النتائج اصطناعية وليست تحليلًا فعليًا للفيديو'


class AnalysisReport(Contract):
    schema_version: Literal['1.0'] = '1.0'
    analysis_id: str
    prayer: Prayer
    expected_rakahs: int
    observed_rakahs: int
    analysis_mode: Literal['mock', 'real']
    synthetic: bool
    notice: str
    status: Literal['COMPLETED'] = 'COMPLETED'
    overall_result: Result
    rakahs: list[RakahReport]
    events: list[MovementEvent]
    unexpected_movements: list[UnexpectedMovement]
    metrics: Metrics
