export class RecognizerClient {
  constructor(base = new URL('./', location.href).href, onProgress = () => {}) { this.base = base; this.onProgress = onProgress; this.id = 0; this.pending = new Map(); this.busy = false; }
  async initialize() {
    try {
      if (typeof Worker === 'undefined' || typeof OffscreenCanvas === 'undefined') throw Error('Worker/OffscreenCanvas unavailable');
      // MediaPipe's shipped WASM loader uses importScripts/ModuleFactory globals.
      // A classic bundled worker supports that loader across browser engines.
      this.worker = new Worker(new URL('worker.js', this.base));
      this.worker.onmessage = ({ data }) => { if (data.progress) { this.onProgress(data.progress); return; } const pending = this.pending.get(data.id); if (!pending) return; this.pending.delete(data.id); clearTimeout(pending.timer); data.error ? pending.reject(Error(data.error)) : pending.resolve(data.value); };
      this.worker.onerror = event => { for (const p of this.pending.values()) { clearTimeout(p.timer); p.reject(Error(event.message || 'Worker failure')); } this.pending.clear(); };
      this.info = await this.call('init', { base: this.base }); this.mode = 'worker';
    } catch (error) {
      this.worker?.terminate(); this.worker = null;
      this.fallbackReason = error.message;
      // Safari/worker initialization fallback stays entirely on-device. Yield before each run.
      const { Engine } = await import('./engine.mjs');
      this.engine = new Engine(); this.info = await this.engine.initialize(this.base, this.onProgress); this.mode = 'main-thread-wasm';
    }
    return { ...this.info, mode: this.mode, fallback_reason: this.fallbackReason };
  }
  call(type, data, transfer = []) {
    const id = ++this.id;
    return new Promise((resolve, reject) => {
      // First downloads can exceed two minutes. Do not kill a healthy download
      // and restart it in the fallback; keep the inference deadline unchanged.
      const timer = type === 'init' ? null : setTimeout(() => { this.pending.delete(id); reject(Error('Inference timed out; restart recognition')); }, 120000);
      this.pending.set(id, { resolve, reject, timer });
      this.worker.postMessage({ id, type, ...data }, transfer);
    });
  }
  async analyze(source, diagnostic = false) {
    if (this.busy) throw Error('Inference already running');
    this.busy = true;
    let bitmap;
    try {
      if (source instanceof Blob) {
        if (this.worker) return await this.call('analyze', { blob: source, diagnostic });
        await new Promise(r => setTimeout(r, 0));
        return await this.engine.analyze(source, diagnostic);
      }
      bitmap = typeof createImageBitmap === 'function' ? await createImageBitmap(source, { imageOrientation: 'from-image', premultiplyAlpha: 'none', colorSpaceConversion: 'none' }) : null;
      if (this.worker) {
        if (!bitmap) throw Error('ImageBitmap unavailable');
        return await this.call('analyze', { bitmap, diagnostic }, [bitmap]);
      }
      await new Promise(r => setTimeout(r, 0));
      // HTMLImageElement/Canvas fallback for older browser decoders.
      if (!bitmap && source instanceof Blob) {
        const url = URL.createObjectURL(source), image = new Image();
        try { image.src = url; await image.decode(); return await this.engine.analyze(image, diagnostic); }
        finally { URL.revokeObjectURL(url); }
      }
      return await this.engine.analyze(bitmap ?? source, diagnostic);
    } finally { bitmap?.close(); this.busy = false; }
  }
  async classify(features, context) { return this.worker ? this.call('features', { features: Array.from(features), context }) : this.engine.classify(features, context); }
  async close() { this.worker?.terminate(); for (const p of this.pending.values()) { clearTimeout(p.timer); p.reject(Error('Recognizer closed')); } this.pending.clear(); await this.engine?.close(); }
}
