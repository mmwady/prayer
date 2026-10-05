// Raw conservative all-optimal-path alignment port of backend/app/analysis/sequence.py.
// Optional backend correction/normalization switches are deliberately not applied.
import { CLASSES } from './core.mjs';
export const POSES = ['standing', 'takbir', 'standing', 'ruku', 'sujood', 'sitting', 'salam_right', 'salam_left'];
export const COUNTS = { fajr: 2, dhuhr: 4, asr: 4, maghrib: 3, isha: 4, demo: 1 };
export const LABELS = { standing: 'القيام', takbir: 'تكبيرة الإحرام', ruku: 'الركوع', standing_after_ruku: 'الاعتدال بعد الركوع', sujood_first: 'السجود الأول', sitting: 'الجلوس بين السجدتين', sujood_second: 'السجود الثاني', intermediate_sitting: 'الجلوس الأوسط', final_sitting: 'الجلوس الأخير', salam_right: 'السلام يمينًا', salam_left: 'السلام يسارًا' };
const stationPose = { ...Object.fromEntries(POSES.map(p => [p, p])), standing_after_ruku: 'standing', sujood_first: 'sujood', sujood_second: 'sujood', intermediate_sitting: 'sitting', final_sitting: 'sitting' };
export function stations(prayer) {
  if (!COUNTS[prayer]) throw Error('Unknown prayer');
  return Array.from({ length: COUNTS[prayer] }, (_, i) => [ ...(i === 0 ? ['takbir'] : []), 'standing', 'ruku', 'standing_after_ruku', 'sujood_first', 'sitting', 'sujood_second', ...(i === 1 && COUNTS[prayer] > 2 ? ['intermediate_sitting'] : []), ...(i === COUNTS[prayer] - 1 ? ['final_sitting', 'salam_right', 'salam_left'] : []) ]);
}
export function temporal(samples, threshold = .65, { min_observations = 1, min_duration_ms = 0, max_gap_ms = 1000 } = {}) {
  samples = samples.map((s, i) => ({ sequence_index: i, ...s })).sort((a, b) => a.timestamp_ms - b.timestamp_ms);
  const groups = [], events = [];
  const pose = s => POSES[CLASSES.indexOf(s.result.predicted_action)] ?? 'unknown';
  const valid = s => s.result.pose_detected && s.result.confidence >= threshold && pose(s) !== 'unknown';
  for (let i = 0; i < samples.length; i++) {
    const item = samples[i];
    if (i && (item.timestamp_ms <= samples[i - 1].timestamp_ms || item.sequence_index <= samples[i - 1].sequence_index)) throw Error('INVALID_TIMESTAMP_ORDER');
    const prev = groups.at(-1)?.at(-1);
    if (prev) {
      if (item.timestamp_ms - prev.timestamp_ms > max_gap_ms) events.push({ pose: 'unknown', start_ms: prev.timestamp_ms, end_ms: item.timestamp_ms, confidence: 0, representative_frame_id: null, candidate_confidence: null, candidate_timestamp_ms: null, candidate_pose: null, observation_status: 'uncertain' });
      else if (valid(item) === valid(prev) && (!valid(item) || pose(item) === pose(prev))) { groups.at(-1).push(item); continue; }
    }
    groups.push([item]);
  }
  for (const group of groups) {
    const stable = valid(group[0]) && group.length >= min_observations && group.at(-1).timestamp_ms - group[0].timestamp_ms >= min_duration_ms;
    const guesses = stable ? group : group.filter(x => x.result.pose_detected && pose(x) !== 'unknown');
    const candidate = guesses.reduce((best, x) => !best || x.result.confidence > best.result.confidence ? x : best, null);
    events.push({ pose: stable ? pose(group[0]) : 'unknown', start_ms: group[0].timestamp_ms, end_ms: group.at(-1).timestamp_ms,
      confidence: group.reduce((s, x) => s + x.result.confidence, 0) / group.length,
      candidate_confidence: candidate?.result.confidence ?? null, candidate_timestamp_ms: candidate?.timestamp_ms ?? null,
      representative_frame_id: candidate?.frame_id ?? null,
      candidate_pose: candidate ? pose(candidate) : null, observation_status: stable ? 'detected' : 'uncertain' });
  }
  return events.sort((a, b) => a.start_ms - b.start_ms || a.end_ms - b.end_ms).map((e, i) => ({ ...e, event_id: 'evt_' + String(i).padStart(4, '0') }));
}
export function sequenceReport(prayer, events) {
  const rows = stations(prayer), expected = rows.flatMap((row, r) => row.map(station => ({ station, r })));
  const detected = events.filter(e => e.observation_status === 'detected');
  const n = detected.length, m = expected.length;
  const matrix = () => Array.from({ length: n + 1 }, () => new Int32Array(m + 1));
  const prefix = matrix(), suffix = matrix(), matches = (i, j) => detected[i].pose === stationPose[expected[j].station];
  for (let i = 0; i < n; i++) for (let j = 0; j < m; j++) prefix[i + 1][j + 1] = Math.max(prefix[i][j + 1], prefix[i + 1][j], prefix[i][j] + Number(matches(i, j)));
  for (let i = n - 1; i >= 0; i--) for (let j = m - 1; j >= 0; j--) suffix[i][j] = Math.max(suffix[i + 1][j], suffix[i][j + 1], suffix[i + 1][j + 1] + Number(matches(i, j)));
  const best = suffix[0][0], candidates = expected.map((_, j) => detected.map((_, i) => i).filter(i => matches(i, j) && prefix[i][j] + 1 + suffix[i + 1][j + 1] === best));
  const reverse = detected.map((_, i) => candidates.map((_, j) => j).filter(j => candidates[j].includes(i)));
  const confirmed = new Map(), used = new Set();
  candidates.forEach((options, j) => {
    const optional = prefix.some((row, i) => row[j] + suffix[i][j + 1] === best);
    if (options.length === 1 && reverse[options[0]].length === 1 && !optional) { confirmed.set(j, detected[options[0]]); used.add(options[0]); }
  });
  let offset = 0;
  const rakahs = rows.map((row, r) => {
    const reports = row.map(station => {
      const event = confirmed.get(offset++);
      return { station, arabic_label: LABELS[station], status: event ? 'DETECTED' : 'UNCONFIRMED', confidence: event?.candidate_confidence ?? event?.confidence ?? null, timestamp_ms: event?.candidate_timestamp_ms ?? event?.start_ms ?? null, event_id: event?.event_id ?? null, evidence_id: event?.evidence_id ?? null };
    });
    return { rakah_number: r + 1, result: reports.every(s => s.status === 'DETECTED') ? 'OBSERVED_COMPLETE' : 'REVIEW_REQUIRED', stations: reports,
      notes: reports.filter(s => s.status === 'UNCONFIRMED').map(s => `لم نتمكن من تأكيد ${s.arabic_label} من الصور المتاحة.`) };
  });
  const unexpected = detected.filter((_, i) => !used.has(i)).map(e => ({ event_id: e.event_id, pose: e.pose, start_ms: e.start_ms,
    confidence: e.candidate_confidence ?? e.confidence, timestamp_ms: e.candidate_timestamp_ms ?? null,
    evidence_id: e.evidence_id ?? null, reason: reverse[detected.indexOf(e)].length ? 'ambiguous' : 'out_of_sequence_or_repeated' }));
  // Match the backend's temporal review placement. Placement is context only.
  const anchors = Array.from(confirmed, ([j, event]) => [event.start_ms, expected[j].r + 1]).sort((a,b) => a[0]-b[0] || a[1]-b[1]);
  const boundaries = []; let base = 0;
  rows.slice(0,-1).forEach((row,r) => { if (row.every((_,j) => confirmed.has(base+j))) boundaries.push([confirmed.get(base+row.length-1).end_ms,r+2]); base += row.length; });
  for (const item of [...unexpected, ...events]) {
    item.review_rakah_number = null; item.review_before_station_index = null;
    if (!anchors.length) continue;
    const preceding = anchors.filter(a => a[0] <= item.start_ms);
    let number = (preceding.at(-1) ?? anchors[0])[1];
    for (const [end,next] of boundaries) if (item.start_ms > end) number = Math.max(number,next);
    const row = rakahs[number-1].stations;
    const slot = row.findIndex(s => s.timestamp_ms !== null && s.timestamp_ms > item.start_ms);
    item.review_rakah_number = number; item.review_before_station_index = slot < 0 ? row.length : slot;
  }
  const completed = rakahs.filter(r => r.result === 'OBSERVED_COMPLETE').length;
  return { prayer, expected_rakahs: rows.length, observed_rakahs: completed, rakahs, events, unexpected_movements: unexpected,
    overall_result: completed === rows.length && !unexpected.length && !events.some(e => e.observation_status === 'uncertain') ? 'OBSERVED_COMPLETE' : 'REVIEW_REQUIRED',
    notice: 'تحليل ترتيب الحركات المرصودة على جهازك، دون حكم على صحة الصلاة.', analysis_mode: 'browser', synthetic: false };
}
