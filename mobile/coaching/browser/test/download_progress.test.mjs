import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { cachedAsset } from '../src/assets.mjs';
test('download progress reports streamed bytes and verifies the complete model before caching',async()=>{
 const oldFetch=globalThis.fetch,oldCaches=globalThis.caches;
 const data=new Uint8Array([1,2,3,4]),hash=createHash('sha256').update(data).digest('hex'),progress=[];
 let cached;
 try{
  globalThis.caches={open:async()=>({match:async()=>null,put:async(_,r)=>{cached=new Uint8Array(await r.arrayBuffer());}})};
  globalThis.fetch=async()=>new Response(new ReadableStream({start(c){c.enqueue(data.slice(0,2));c.enqueue(data.slice(2));c.close();}}),{headers:{'content-length':'4'}});
  assert.deepEqual(new Uint8Array(await cachedAsset('https://device.test/','test.onnx',{model_version:'v',assets:{'test.onnx':hash}},p=>progress.push(p))),data);
  assert.ok(progress.some(p=>p.phase==='downloading'&&p.loaded===2&&p.total===4));
  assert.deepEqual(progress.at(-1),{phase:'verifying',asset:'test.onnx',loaded:4,total:4});
  assert.deepEqual(cached,data);
 }finally{globalThis.fetch=oldFetch;globalThis.caches=oldCaches;}
});
