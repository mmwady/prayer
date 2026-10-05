// Real browser acceptance of the shared Flutter JS bridge and offline assets.
// Local test bytes are passed directly into the page; no HTTP request carries them.
import {chromium} from 'playwright';
import {serve} from './serve.mjs';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';

const project=fileURLToPath(new URL('../../',import.meta.url)),out=path.resolve(project,'../../output/local-training');
await mkdir(out,{recursive:true});
const imageReferences=JSON.parse(await readFile(new URL('../test/fixtures/image_reference.json',import.meta.url),'utf8'));
const fixture=imageReferences.images.find(x=>x.result.pose_detected);
const bytes=Array.from(await readFile(new URL('../test/fixtures/'+fixture.path,import.meta.url)));
const server=await serve(path.join(project,'build/web'),8787),results=[];
try{
 for(const name of ['chrome','msedge']){
  let browser,page;const result={browser:name,passed:false,external_requests:[],payload_requests:[],errors:[]};
  try{
   browser=await chromium.launch({channel:name,headless:true});result.version=browser.version();
   const context=await browser.newContext({acceptDownloads:true,viewport:{width:390,height:844}});page=await context.newPage();
   context.on('request',request=>{if(!request.url().startsWith('http://127.0.0.1:8787/')&&!request.url().startsWith('blob:'))result.external_requests.push(request.url());if(!['GET','HEAD'].includes(request.method())||request.postData())result.payload_requests.push(request.url());});
   page.on('pageerror',error=>result.errors.push(error.message));
   await page.goto('http://127.0.0.1:8787/');await page.waitForFunction(()=>!!window.iqtadiLocal,null,{timeout:60000});
   const info=await page.evaluate(()=>window.iqtadiLocal.initialize());assert.equal(info.inference_provider,'local');assert.equal(info.model_ready,true);assert.equal(info.storage_available,true);
   result.model_version=info.model_version;result.execution_mode=info.mode;
   const observation=await page.evaluate(async input=>{const value=await window.iqtadiLocal.analyze(new Uint8Array(input));window.acceptanceObservation=value;
    return {result:value.result,preview_size:value.preview_jpeg.length,preview_header:Array.from(value.preview_jpeg.slice(0,3))};},bytes);
   assert.equal(observation.result.individual_models.length,3);assert.deepEqual(observation.preview_header,[255,216,255]);assert.ok(observation.preview_size>0);
   result.predicted_action=observation.result.predicted_action;result.preview_size=observation.preview_size;
   const persistence=await page.evaluate(async()=>{
    const api=window.iqtadiLocal,{result,preview_jpeg}=window.acceptanceObservation;
    const report=await api.report('demo',[{frame_id:'frame_0',timestamp_ms:0,sequence_index:0,result}],{analysis_id:'acceptance_session',sample_fps:4});
    await api.saveSession({id:'acceptance_session',model_version:result.model_version,report,predictions:report.predictions,evidence:[{id:'frame_0',bytes:preview_jpeg}]});
    const session=await api.loadSession('acceptance_session'),evidence=await api.loadEvidence('acceptance_session','frame_0');
    return {report_mode:report.analysis_mode,report_schema:report.schema_version,individual:session.predictions.frame_0.individual_models.length,evidence_size:evidence.length,list_count:(await api.listSessions()).length};
   });assert.equal(persistence.report_mode,'local');assert.equal(persistence.report_schema,'1.0');assert.equal(persistence.individual,3);assert.equal(persistence.evidence_size,observation.preview_size);
   result.persistence=persistence;
   const downloadPromise=page.waitForEvent('download');await page.evaluate(()=>window.iqtadiLocal.exportSession('acceptance_session'));const download=await downloadPromise;
   assert.equal(download.suggestedFilename(),'iqtadi-acceptance_session.json');result.local_export=true;
   const overlapping=await page.evaluate(async input=>{const api=window.iqtadiLocal;return (await Promise.allSettled([api.analyze(new Uint8Array(input)),api.analyze(new Uint8Array(input))])).map(x=>({status:x.status,message:x.reason?.message}));},bytes);
   assert.equal(overlapping.filter(x=>x.status==='rejected'&&/already running/.test(x.message)).length,1);result.overlap_rejected=true;
   console.log(name+': local bridge, three classifiers, preview evidence, IndexedDB/export and overlap checks passed. Waiting for complete offline cache.');
   const progress=setInterval(async()=>{try{console.log(name+' offline progress:',await page.evaluate(()=>window.iqtadiOffline?.status()));}catch{}},20000);
   try{await page.waitForFunction(()=>{const status=window.iqtadiOffline?.status();return status?.ready||['failed','unavailable'].includes(status?.state);},null,{timeout:240000});}
   finally{clearInterval(progress);}
   result.offline_status=await page.evaluate(()=>window.iqtadiOffline.status());
   assert.equal(result.offline_status.ready,true,result.offline_status.warning ?? 'Offline cache did not complete');
   await context.setOffline(true);await page.reload();await page.waitForFunction(()=>!!window.iqtadiLocal,null,{timeout:60000});
   const offline=await page.evaluate(async input=>{const info=await window.iqtadiLocal.initialize(),observation=await window.iqtadiLocal.analyze(new Uint8Array(input)),session=await window.iqtadiLocal.loadSession('acceptance_session');
    const evidence=await window.iqtadiLocal.loadEvidence('acceptance_session','frame_0');return {model_version:info.model_version,action:observation.result.predicted_action,individual:observation.result.individual_models.length,saved_individual:session.predictions.frame_0.individual_models.length,evidence_size:evidence.length};},bytes);
   assert.equal(offline.model_version,info.model_version);assert.equal(offline.action,observation.result.predicted_action);assert.equal(offline.individual,3);assert.equal(offline.saved_individual,3);result.offline=offline;
   await page.screenshot({path:path.join(out,name+'-offline.png'),fullPage:true});
   await page.evaluate(()=>window.iqtadiLocal.deleteSession('acceptance_session'));assert.equal(await page.evaluate(()=>window.iqtadiLocal.loadSession('acceptance_session')),null);
   assert.deepEqual(result.external_requests,[]);assert.deepEqual(result.payload_requests,[]);assert.deepEqual(result.errors,[]);result.passed=true;
   console.log(name+': offline reload, offline inference, saved evidence and deletion passed.');
  }catch(error){result.error=error.stack;result.offline_failure_status=await page?.evaluate(()=>window.iqtadiOffline?.status()).catch(()=>null);console.error(name+': '+error.message, result.offline_failure_status);}
  finally{await browser?.close();results.push(result);await writeFile(path.join(out,'browser-local-services.json'),JSON.stringify({tested_at:new Date().toISOString(),results},null,2));}
 }
 assert.ok(results.every(result=>result.passed),'Every requested browser must pass; inspect output/local-training/browser-local-services.json');
}finally{server.close();}
