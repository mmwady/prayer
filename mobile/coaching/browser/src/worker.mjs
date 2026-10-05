import { Engine } from './engine.mjs';
let engine, busy = false;
self.onmessage = async ({ data }) => {
  if (busy) { self.postMessage({ id: data.id, error: 'Overlapping inference refused' }); data.bitmap?.close(); return; }
  busy = true;
  try {
    let value;
    if (data.type === 'init') { engine = new Engine(); value = await engine.initialize(data.base); }
    else if (data.type === 'features') value = await engine.classify(new Float32Array(data.features), data.context);
    else if (data.type === 'analyze') value = await engine.analyze(data.blob ?? data.bitmap, data.diagnostic);
    else throw Error('Unknown worker operation');
    self.postMessage({ id: data.id, value });
  } catch (error) { self.postMessage({ id: data.id, error: error.message }); }
  finally { data.bitmap?.close(); busy = false; }
};
