import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { cachedAsset, manifestAt, purgeOldAssets } from '../src/assets.mjs';
import { preservePresence } from '../scripts/mediapipe-presence.mjs';
import { CLASSES, SCHEMA_VERSION } from '../src/core.mjs';
test('pinned MediaPipe converter preserves genuine presence and rejects dependency drift',()=>{
 const original=readFileSync(new URL('../node_modules/@mediapipe/tasks-vision/vision_bundle.mjs',import.meta.url),'utf8');
 assert.ok(preservePresence(original).includes('visibility:Fn(n,4)??0,presence:Fn(n,5)??0'));
 assert.throws(()=>preservePresence(original+'\n'));
});
test('model bytes are hash checked, versioned and read from cache without duplicate downloads',async()=>{
 const originalFetch=globalThis.fetch, originalCaches=globalThis.caches;
 const data=new TextEncoder().encode('test model bytes'), hash=createHash('sha256').update(data).digest('hex');
 const m={model_version:'test-version',assets:{'test.onnx':hash}}, entries=new Map();let requests=0;
 const cache={match:async u=>entries.get(String(u))?.clone(),put:async(u,r)=>entries.set(String(u),r),delete:async u=>entries.delete(String(u))};
 globalThis.caches={open:async()=>cache};globalThis.fetch=async u=>{requests++;assert.ok(String(u).includes('?v='+hash));return new Response(data);};
 try{assert.deepEqual(new Uint8Array(await cachedAsset('https://device.test/','test.onnx',m)),data);await cachedAsset('https://device.test/','test.onnx',m);assert.equal(requests,1);
  entries.clear();globalThis.fetch=async()=>new Response('stale wrong model');await assert.rejects(cachedAsset('https://device.test/','test.onnx',m),/hash mismatch/);
 }finally{globalThis.fetch=originalFetch;globalThis.caches=originalCaches;}
});
test('manifest class/schema drift fails and previous model cache is removed',async()=>{
 const originalFetch=globalThis.fetch, originalCaches=globalThis.caches;const deleted=[];
 try{globalThis.fetch=async()=>Response.json({schema_version:SCHEMA_VERSION,classes:[...CLASSES].reverse()});await assert.rejects(manifestAt('https://device.test/'),/mismatch/);
  globalThis.caches={keys:async()=>['iqtadi-models-old','iqtadi-models-new','unrelated-cache'],delete:async name=>deleted.push(name)};await purgeOldAssets('new');assert.deepEqual(deleted,['iqtadi-models-old']);
 }finally{globalThis.fetch=originalFetch;globalThis.caches=originalCaches;}
});
test('cache storage denial falls back to normal fetch',async()=>{
 const originalFetch=globalThis.fetch, originalCaches=globalThis.caches, data=new Uint8Array([1,2,3]);
 try{globalThis.caches={open:async()=>{throw Error('denied')}};globalThis.fetch=async()=>new Response(data);await cachedAsset('https://device.test/','a.onnx',{model_version:'v',assets:{'a.onnx':createHash('sha256').update(data).digest('hex')}});}
 finally{globalThis.fetch=originalFetch;globalThis.caches=originalCaches;}
});
test('an offline manifest loads only from schema/class-validated local cache',async()=>{
 const originalFetch=globalThis.fetch,originalCaches=globalThis.caches;let saved;
 const cache={match:async()=>saved?.clone(),put:async(_,response)=>{saved=response.clone();}};
 try{globalThis.caches={open:async()=>cache};globalThis.fetch=async()=>Response.json({schema_version:SCHEMA_VERSION,classes:CLASSES,model_version:'offline-v1'});
  assert.equal((await manifestAt('https://device.test/')).model_version,'offline-v1');globalThis.fetch=async()=>{throw Error('offline');};
  assert.equal((await manifestAt('https://device.test/')).model_version,'offline-v1');
  saved=Response.json({schema_version:'old',classes:CLASSES});await assert.rejects(manifestAt('https://device.test/'),/mismatch/);
  saved=null;await assert.rejects(manifestAt('https://device.test/'),/complete the first download/);
 }finally{globalThis.fetch=originalFetch;globalThis.caches=originalCaches;}
});
