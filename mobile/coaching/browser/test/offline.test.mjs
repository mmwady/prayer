import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';

function workerHarness(corrupt=false){
 const handlers={},stores=new Map([['iqtadi-app-old',new Map()]]),requests=[];
 const assets={'index.html':'local flutter application','recognizer/bridge.js':'local model bridge'};
 const manifest={schema_version:'1.0.0',version:'test-version',files:Object.entries(assets).map(([path,value])=>({path,size:value.length,sha256:createHash('sha256').update(value).digest('hex')}))};
 const caches={keys:async()=>[...stores.keys()],delete:async name=>stores.delete(name),open:async name=>{
  if(!stores.has(name))stores.set(name,new Map());const store=stores.get(name);
  return {match:async url=>store.get(String(url))?.clone(),put:async(url,response)=>store.set(String(url),response.clone())};}};
 const self={registration:{scope:'https://app.test/base/'},location:{origin:'https://app.test'},clients:{matchAll:async()=>[],claim:async()=>{}},
  addEventListener:(name,handler)=>handlers[name]=handler,skipWaiting:()=>{self.skipped=true;}};
 const fetch=async url=>{requests.push(String(url));const relative=new URL(url).pathname.slice('/base/'.length);
  if(relative==='iqtadi-offline-manifest.json')return Response.json(manifest);
  return new Response(corrupt&&relative==='recognizer/bridge.js'?'wrong stale version':assets[relative]??'network response');};
 const code=readFileSync(new URL('../../web/iqtadi_service_worker.js',import.meta.url),'utf8').replace('__IQTADI_OFFLINE_VERSION__','test-version');
 vm.runInNewContext(code,{self,caches,fetch,Response,URL,crypto:globalThis.crypto});
 const run=async name=>{let pending;handlers[name]({waitUntil:p=>pending=p});await pending;};
 return {handlers,run,requests,stores,self};
}
test('offline app version activates only after every static file passes its hash; old shell is invalidated',async()=>{
 const harness=workerHarness();await harness.run('install');assert.equal(harness.self.skipped,undefined);
 await harness.run('activate');assert.deepEqual([...harness.stores.keys()],['iqtadi-app-test-version']);
 let response;harness.handlers.fetch({request:new Request('https://app.test/base/recognizer/bridge.js?v=model-hash'),respondWith:p=>response=p});
 assert.equal(await (await response).text(),'local model bridge');assert.equal(harness.requests.length,3);
 let intercepted=false;
 for(const request of [new Request('https://app.test/base/api/v1/mosque'),new Request('https://app.test/base/healthz'),new Request('https://app.test/base/image',{method:'POST',body:'private'})])
  harness.handlers.fetch({request,respondWith:()=>intercepted=true});
 assert.equal(intercepted,false);
 harness.handlers.message({data:{type:'ACTIVATE_UPDATE'}});assert.equal(harness.self.skipped,true);
});
test('partial or stale asset downloads cannot activate an offline cache',async()=>{
 const harness=workerHarness(true);await assert.rejects(harness.run('install'),/version mismatch/);
 assert.equal(harness.stores.has('iqtadi-app-test-version'),false);assert.equal(harness.stores.has('iqtadi-app-old'),true);
});
