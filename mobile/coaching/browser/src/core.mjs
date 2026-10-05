export const SCHEMA_VERSION = '2.0.0';
export const SEEDS = ['2026', '3407', '8111'];
export const CLASSES = ['1_Qiyam', '2_Takbir', '3_Qiyam_Recitation', '4_Ruku', '5_Sujud', '6_Jalsa', '7_Salam_Right', '8_Salam_Left'];
export const ARABIC = ['القيام', 'التكبير', 'القيام والقراءة', 'الركوع', 'السجود', 'الجلسة', 'التسليم يمينًا', 'التسليم يسارًا'];
export const RECOVERY = ['standard', 'autocontrast', 'contrast_1.15', 'rotate_minus_5', 'rotate_plus_5'];
const f = Math.fround;
export function validatePreprocessing(p) {
  if (p.mean?.length !== 165 || p.std?.length !== 165 ||
      !p.mean.every(Number.isFinite) || !p.std.every(x => Number.isFinite(x) && x > 0)) throw Error('Invalid preprocessing assets');
}
export function featuresFromLandmarks(landmarks, preprocessing) {
  validatePreprocessing(preprocessing);
  if (landmarks?.length !== 33) return null;
  const xyz = landmarks.map(p => [f(p.x), f(p.y), f(p.z)]);
  if (!xyz.flat().every(Number.isFinite)) return null;
  const hip = [0, 1, 2].map(k => f(f(xyz[23][k] + xyz[24][k]) * 0.5));
  const norm = (x, y) => f(Math.sqrt(f(f(x * x) + f(y * y))));
  const torso = norm(...[0, 1].map(k => f(f(f(xyz[11][k] + xyz[12][k]) * 0.5) - hip[k])));
  const shoulders = norm(f(xyz[11][0] - xyz[12][0]), f(xyz[11][1] - xyz[12][1]));
  const scale = Math.max(torso, shoulders);
  if (!Number.isFinite(scale) || scale <= 1e-4) return null;
  const raw = new Float32Array(165);
  xyz.forEach((p, i) => p.forEach((v, k) => { raw[3 * i + k] = f(f(v - hip[k]) / scale); }));
  landmarks.forEach((p, i) => { raw[99 + i] = p.visibility ?? 0; raw[132 + i] = p.presence ?? 0; });
  const features = new Float32Array(166);
  for (let i = 0; i < 165; i++) features[i] = f(f(raw[i] - f(preprocessing.mean[i])) / f(preprocessing.std[i]));
  features[165] = 1;
  return features.every(Number.isFinite) ? features : null;
}
export function softmax(logits) {
  if (logits.length !== 8 || !Array.from(logits).every(Number.isFinite)) throw Error('Invalid model logits');
  const max = Math.max(...logits), exps = Array.from(logits, x => Math.exp(x - max));
  const sum = exps.reduce((a, b) => a + b, 0);
  return exps.map(x => x / sum);
}
export function averageProbabilities(arrays) {
  if (arrays.length !== 3 || arrays.some(a => a.length !== 8 || !Array.from(a).every(x => Number.isFinite(x) && x >= 0))) throw Error('Exactly three valid models are required');
  return CLASSES.map((_, i) => (arrays[0][i] + arrays[1][i] + arrays[2][i]) / 3);
}
export function decision(probabilities) {
  const order = CLASSES.map((_, i) => i).sort((a, b) => probabilities[b] - probabilities[a] || b - a);
  return { predicted_action: CLASSES[order[0]], class_index: order[0], confidence: probabilities[order[0]],
    probabilities: Object.fromEntries(CLASSES.map((c, i) => [c, probabilities[i]])),
    top3: order.slice(0, 3).map(i => ({ action: CLASSES[i], probability: probabilities[i] })) };
}
export function ensembleResult(logits, context) {
  const probabilities = logits.map(softmax);
  const individual_models = probabilities.map((p, i) => ({ seed: SEEDS[i], ...decision(p) }));
  const aggregate = decision(averageProbabilities(probabilities));
  return { ...aggregate, individual_models, pose_detected: true, normalization_valid: true,
    schema_version: SCHEMA_VERSION, model_version: context.model_version,
    recovery_method: context.recovery_method, mean_visibility: context.mean_visibility,
    inference_ms: context.inference_ms, model_type: 'exp1_full_head_attention',
    classifier_disagreement: individual_models.some(m => m.class_index !== aggregate.class_index), warning: null };
}
export function failedResult(context) {
  const empty = { predicted_action: null, class_index: null, confidence: 0, probabilities: {}, top3: [] };
  return { ...empty, individual_models: SEEDS.map(seed => ({ seed, ...empty, available: false })),
    pose_detected: false, normalization_valid: false, schema_version: SCHEMA_VERSION,
    model_version: context.model_version, recovery_method: 'failed', mean_visibility: null,
    inference_ms: context.inference_ms, warning: 'Pose detection and recovery failed; individual classifiers were not run.' };
}
export function validResult(r, version) {
  if (!r || r.schema_version !== SCHEMA_VERSION || r.model_version !== version || r.individual_models?.length !== 3 ||
      !r.individual_models.every((m, i) => m.seed === SEEDS[i])) return false;
  if (!Number.isFinite(r.inference_ms) || r.inference_ms < 0) return false;
  const empty = m => m.predicted_action === null && m.class_index === null && m.confidence === 0 &&
    !!m.probabilities && Object.keys(m.probabilities).length === 0 && Array.isArray(m.top3) && m.top3.length === 0;
  if (!r.pose_detected) return r.pose_detected === false && r.normalization_valid === false && empty(r) &&
    typeof r.warning === 'string' && r.warning.length > 0 && r.individual_models.every(m => m.available === false && empty(m));
  try {
    const arrays = r.individual_models.map(m => CLASSES.map(c => m.probabilities[c]));
    const avg = averageProbabilities(arrays);
    const distribution = p => p.every(x => Number.isFinite(x) && x >= 0 && x <= 1) && Math.abs(p.reduce((sum,x) => sum+x,0)-1) <= 1e-5;
    if (!arrays.every(distribution) || !distribution(avg) || !Number.isFinite(r.mean_visibility) || r.mean_visibility < 0 || r.mean_visibility > 1) return false;
    const complete = (m, p) => m.predicted_action === CLASSES[m.class_index] && Number.isFinite(m.confidence) &&
      Math.abs(m.confidence - p[m.class_index]) < 1e-7 && m.top3?.length === 3 &&
      m.top3.every((item, i) => item.action === decision(p).top3[i].action && Math.abs(item.probability - decision(p).top3[i].probability) < 1e-7);
    return r.pose_detected === true && r.normalization_valid === true && RECOVERY.includes(r.recovery_method) && r.class_index === decision(avg).class_index && complete(r, avg) &&
      CLASSES.every((c, i) => Math.abs(r.probabilities[c] - avg[i]) <= 1e-7) &&
      r.individual_models.every((m, i) => m.class_index === decision(arrays[i]).class_index && complete(m, arrays[i]));
  } catch { return false; }
}
export function readSession(storage, version) {
  const key = 'iqtadi-recognizer-session';
  try {
    const data = JSON.parse(storage.getItem(key));
    if (data?.schema_version === SCHEMA_VERSION && data?.model_version === version &&
        Array.isArray(data.results) && data.results.every(r => validResult(r, version))) return data.results;
  } catch { /* Corrupt local session is invalidated. */ }
  try { storage.removeItem(key); } catch { /* Storage denied: continue without persistence. */ } return [];
}
export function saveSession(storage, version, results) {
  if (!results.every(r => validResult(r, version))) throw Error('Cannot persist an incomplete prediction');
  storage.setItem('iqtadi-recognizer-session', JSON.stringify({ schema_version: SCHEMA_VERSION, model_version: version, results }));
}
export class StableCapture {
  constructor(threshold = .7) { this.threshold = threshold; this.candidate = null; this.count = 0; this.lastAction = null; this.lastTime = 0; }
  update(result, seconds) {
    const action = result.pose_detected ? result.predicted_action : null;
    if (!action || result.confidence < this.threshold) { this.candidate = null; this.count = 0; return false; }
    if (action === this.candidate) this.count++;
    else { this.candidate = action; this.count = 1; if (action !== this.lastAction) this.lastAction = null; }
    if (this.count >= 3 && seconds - this.lastTime >= 3 && action !== this.lastAction) {
      this.lastAction = action; this.lastTime = seconds; return true;
    }
    return false;
  }
}
