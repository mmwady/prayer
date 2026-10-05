import { SCHEMA_VERSION, validResult } from './core.mjs';
import { temporal, sequenceReport } from './sequence.mjs';

export const REPORT_SCHEMA_VERSION = '1.0';
export const SESSION_SCHEMA_VERSION = '1.0.0';
export const LOCAL_LIMITS = Object.freeze({ frame_sample_fps: 4, max_frame_dimension: 960,
  analysis_max_frame_bytes: 200000, analysis_max_frames: 2400, max_video_duration_ms: 1200000,
  frame_batch_size: 1, temporal_confidence: .65, temporal_min_observations: 1,
  temporal_min_duration_ms: 0, temporal_max_gap_ms: 1000 });

// All probability decisions are retained, including disagreement and no-pose diagnostics.
export function buildLocalReport(prayer, samples, options = {}) {
  if (!Array.isArray(samples) || samples.length > LOCAL_LIMITS.analysis_max_frames) throw Error('LOCAL_FRAME_LIMIT');
  const version = options.model_version ?? samples[0]?.result?.model_version;
  if (!version) throw Error('MODEL_VERSION_REQUIRED');
  const ids = new Set();
  for (const [i,s] of samples.entries()) {
    if (typeof s.frame_id !== 'string' || !/^[a-zA-Z0-9_-]{1,64}$/.test(s.frame_id) || ids.has(s.frame_id)) throw Error('INVALID_FRAME_ID');
    ids.add(s.frame_id);
    if (!Number.isInteger(s.timestamp_ms) || s.timestamp_ms < 0 || !Number.isInteger(s.sequence_index ?? i) || (s.sequence_index ?? i) < 0) throw Error('INVALID_TIMESTAMP_ORDER');
    if (!validResult(s.result,version)) throw Error('INVALID_PREDICTION_SCHEMA: expected three model decisions');
  }
  const events = temporal(samples, options.temporal_confidence ?? .65, options);
  for (const event of events) event.evidence_id = event.representative_frame_id;
  const report = sequenceReport(prayer,events);
  const detected = report.rakahs.reduce((sum,row) => sum + row.stations.filter(s => s.status === 'DETECTED').length,0);
  const total = report.rakahs.reduce((sum,row) => sum + row.stations.length,0);
  return { ...report, schema_version: REPORT_SCHEMA_VERSION, prediction_schema_version: SCHEMA_VERSION,
    analysis_id: options.analysis_id ?? 'local_' + (globalThis.crypto?.randomUUID?.() ?? Date.now()),
    status: 'COMPLETED', analysis_mode: 'local', synthetic: false,
    model_version: version, predictions: Object.fromEntries(samples.map(s => [s.frame_id,s.result])),
    metrics: { detected_stations: detected, unconfirmed_stations: total-detected,
      unexpected_movements: report.unexpected_movements.length, processed_frames: samples.length,
      sample_fps: options.sample_fps ?? LOCAL_LIMITS.frame_sample_fps,
      inference_provider: 'local', model_version: version },
    uncertainty: { classifier_disagreements: samples.filter(s => s.result.classifier_disagreement).map(s => s.frame_id),
      unavailable_individual_results: samples.filter(s => !s.result.pose_detected).map(s => s.frame_id),
      notice: 'ثقة التصنيف تخص الحركة المرصودة، ولا تعني صحة الصلاة. اختلاف النماذج محفوظ للمراجعة.' } };
}

export function predictionValues(predictions) {
  const values = Array.isArray(predictions) ? predictions : Object.values(predictions ?? {});
  return values.map(p => p.result ?? p);
}
export function validStoredSession(session,version) {
  return !!session && session.schema_version === SCHEMA_VERSION && session.storage_schema_version === SESSION_SCHEMA_VERSION && session.report_schema_version === REPORT_SCHEMA_VERSION && session.prediction_schema_version === SCHEMA_VERSION &&
    session.model_version === version && session.report?.schema_version === REPORT_SCHEMA_VERSION && session.report.status === 'COMPLETED' &&
    session.report.analysis_mode === 'local' && session.report.synthetic === false &&
    session.report.model_version === version && !!session.report.predictions &&
    !!session.predictions && predictionValues(session.predictions).every(p => validResult(p,version)) &&
    predictionValues(session.report.predictions).every(p => validResult(p,version)) &&
    (session.report.captured_actions ?? []).every(item => validResult(item.result,version));
}
