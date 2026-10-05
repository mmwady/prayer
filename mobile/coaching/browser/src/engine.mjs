import { FilesetResolver, PoseLandmarker } from '@mediapipe/tasks-vision';
import * as ort from 'onnxruntime-web/wasm';
import { CLASSES, SEEDS, RECOVERY, featuresFromLandmarks, ensembleResult, failedResult } from './core.mjs';
import { manifestAt, cachedAsset, purgeOldAssets } from './assets.mjs';
import { letterbox, recoveryImage, canvasFor } from './image.mjs';
import { pixelsFromSource } from './decode.mjs';

export class Engine {
  async initialize(base) {
    this.base = base;
    this.manifest = await manifestAt(base);
    await purgeOldAssets(this.manifest.model_version);
    this.preprocessing = JSON.parse(new TextDecoder().decode(await cachedAsset(base, 'preprocessing.json', this.manifest)));
    // No SharedArrayBuffer/COOP dependency. Classifiers are small; portable single-thread WASM.
    ort.env.wasm.numThreads = 1; ort.env.wasm.proxy = false; ort.env.wasm.wasmPaths = new URL('vendor/ort/', base).href;
    const vision = await FilesetResolver.forVisionTasks(new URL('vendor/vision/', base).href);
    this.detector = await PoseLandmarker.createFromOptions(vision, {
      baseOptions: { modelAssetBuffer: new Uint8Array(await cachedAsset(base, 'pose_landmarker_heavy.task', this.manifest)), delegate: 'CPU' },
      runningMode: 'IMAGE', numPoses: 1, minPoseDetectionConfidence: .2, minPosePresenceConfidence: .2, minTrackingConfidence: .2,
      outputSegmentationMasks: false,
    });
    this.sessions = [];
    for (const seed of SEEDS) this.sessions.push(await ort.InferenceSession.create(await cachedAsset(base, `main_seed_${seed}.onnx`, this.manifest), { executionProviders: ['wasm'] }));
    return { model_version: this.manifest.model_version, classes: CLASSES };
  }
  async classify(features, context = {}) {
    if (features.length !== 166 || !features.every(Number.isFinite) || features[165] !== 1) throw Error('Invalid 166-feature input');
    const logits = [];
    // Independent model runs; never average logits.
    for (const session of this.sessions) {
      const output = await session.run({ features: new ort.Tensor('float32', features.slice(), [1, 166]) });
      logits.push(Array.from(output.logits.data));
    }
    return ensembleResult(logits, { model_version: this.manifest.model_version, ...context });
  }
  async analyze(bitmap, diagnostic = false) {
    const started = performance.now();
    const prepared = letterbox(await pixelsFromSource(bitmap));
    for (let i = 0; i < RECOVERY.length; i++) {
      const candidate = recoveryImage(prepared, i), canvas = canvasFor(candidate);
      const landmarks = this.detector.detect(canvas).landmarks[0];
      const features = featuresFromLandmarks(landmarks, this.preprocessing);
      if (!features) continue;
      const result = await this.classify(features, { recovery_method: RECOVERY[i], mean_visibility: landmarks.reduce((s, p) => s + (p.visibility ?? 0), 0) / 33, inference_ms: 0 });
      result.inference_ms = performance.now() - started;
      return { result, landmarks, preview: candidate, ...(diagnostic ? { features: Array.from(features) } : {}) };
    }
    return { result: failedResult({ model_version: this.manifest.model_version, inference_ms: performance.now() - started }), landmarks: [], preview: prepared };
  }
  async close() { this.detector?.close(); for (const session of this.sessions ?? []) await session.release(); }
}
