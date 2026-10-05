// Actual local browser acceptance with a deterministic synthetic camera stream.
// The image is a real reference frame; the camera/device itself is simulated.
import { chromium } from 'playwright';
import { serve } from './serve.mjs';
import { readFile,writeFile,mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
const root=fileURLToPath(new URL('../../',import.meta.url)),out=path.resolve(root,'../../output/browser');
const fixtures=path.join(root,'browser/test/fixtures');
const reference=JSON.parse(await readFile(path.join(fixtures,'image_reference.json'),'utf8'));
const image=reference.images.find(x=>x.result.confidence>.99 && x.result.recovery_method==='standard');
assert.ok(image);await mkdir(out,{recursive:true});const server=await serve(root,8783),results=[];
try{
 for(const channel of ['chrome','msedge']){
  const browser=await chromium.launch({channel,headless:true});
  try{
   const context=await browser.newContext(),violations=[],errors=[],requests=[];
   context.on('request',r=>{requests.push({url:r.url(),method:r.method(),has_body:!!r.postData()});if(r.postData() || !['GET','HEAD'].includes(r.method()) || !r.url().startsWith('http://127.0.0.1:8783/'))violations.push(requests.at(-1));});
   const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
   await page.goto('http://127.0.0.1:8783/browser/test/harness.html');await page.evaluate(()=>window.ready);
   const overlapping=await page.evaluate(async image=>{
    const blob=await(await fetch('/browser/test/fixtures/'+image.path)).blob();
    const first=window.client.analyze(blob);let rejection;
    try{await window.client.analyze(blob);}catch(e){rejection=e.message;}
    const value=await first;return {rejection,count:value.result.individual_models.length};
   },image);assert.match(overlapping.rejection,/already running/);assert.equal(overlapping.count,3);
   await page.evaluate(()=>window.client.close());await page.goto('http://127.0.0.1:8783/web/recognizer/');
   await page.waitForFunction(()=>document.querySelector('#status').textContent.includes('جاهزة'),null,{timeout:120000});
   await page.evaluate(async image=>{
    const img=new Image();img.src='/browser/test/fixtures/'+image.path;await img.decode();
    const canvas=document.createElement('canvas');canvas.width=img.naturalWidth;canvas.height=img.naturalHeight;
    canvas.getContext('2d').drawImage(img,0,0);
    navigator.mediaDevices.getUserMedia=async()=>{
     const stream=canvas.captureStream(5);
     const timer=setInterval(()=>canvas.getContext('2d').drawImage(img,0,0),200);
     stream.getVideoTracks()[0].addEventListener('ended',()=>clearInterval(timer));
     return stream;
    };
   },image);
   await page.locator('#start').click();await page.waitForFunction(()=>!document.querySelector('#snapshot').disabled);
   await page.locator('#live').click();await page.locator('#captures .capture').first().waitFor({timeout:60000});
   await page.waitForTimeout(2500);assert.equal(await page.locator('#captures .capture').count(),1,'held action is not captured repeatedly');
   await page.locator('#captures details').evaluate(el=>{el.open=true;});assert.equal(await page.locator('#captures .model').count(),3);
   // File input during active live inference must wait, then display a fresh result.
   await page.locator('#upload').setInputFiles(path.join(fixtures,image.path));
   await page.waitForFunction(()=>document.querySelectorAll('#captures .capture').length===2,null,{timeout:60000});
   assert.equal(await page.locator('#stop').isDisabled(),true,'upload releases the live camera');
   assert.equal(await page.locator('#result .model').count(),3);
   assert.deepEqual(errors,[]);assert.deepEqual(violations,[]);
   results.push({channel,version:browser.version(),status:'passed',single_flight:overlapping.rejection,stable_live_capture:'three stable matches; held-action dedup; exactly three cards',upload_during_live:'passed',camera:'simulated canvas stream from a local real frame; physical camera unverified',request_count:requests.length,network_payload_violations:violations,page_errors:errors});
   console.log(channel+' stable live capture and all-context privacy: passed');
  }finally{await browser.close();}
 }
 await writeFile(path.join(out,'live-privacy.json'),JSON.stringify({tested_at:new Date().toISOString(),results},null,2));
}finally{server.close();}
