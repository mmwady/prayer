// Actual Flutter routes, real local video and a simulated camera based on a real
// local frame. No server inference, no input payloads, no religious-validity claim.
import {chromium} from 'playwright';
import {serve} from './serve.mjs';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
const project=fileURLToPath(new URL('../../',import.meta.url)),out=path.resolve(project,'../../output/local-training');
const references=JSON.parse(await readFile(new URL('../test/fixtures/image_reference.json',import.meta.url),'utf8'));
const fixture=references.images.find(x=>x.result.confidence>.99&&x.result.recovery_method==='standard');
const image='data:image/png;base64,'+(await readFile(new URL('../test/fixtures/'+fixture.path,import.meta.url))).toString('base64');
await mkdir(out,{recursive:true});
const server=await serve(path.join(project,'build/web'),8788),results=[];
try {
 for(const channel of ['chrome','msedge']){
  const browser=await chromium.launch({channel,headless:true});let page;
  const result={browser:channel,version:browser.version(),passed:false,requests:[],violations:[],errors:[],camera:'simulated canvas camera based on a local real frame; physical camera unverified'};
  try {
   const context=await browser.newContext({acceptDownloads:true,viewport:{width:390,height:844}});
   await context.addInitScript(image=>{navigator.mediaDevices.getUserMedia=async()=>{const img=new Image();img.src=image;await img.decode();const canvas=document.createElement('canvas');canvas.width=img.naturalWidth;canvas.height=img.naturalHeight;const draw=()=>canvas.getContext('2d').drawImage(img,0,0);draw();const stream=canvas.captureStream(8),timer=setInterval(draw,125);stream.getVideoTracks()[0].addEventListener('ended',()=>clearInterval(timer));return stream;};},image);
   context.on('request',r=>{const item={url:r.url(),method:r.method(),has_body:!!r.postData()};result.requests.push(item);if(r.postData()||!['GET','HEAD'].includes(r.method())||(/^https?:/.test(r.url())&&!r.url().startsWith('http://127.0.0.1:8788/'))||r.url().includes('/api/'))result.violations.push(item);});
   page=await context.newPage();page.on('pageerror',e=>result.errors.push(e.message));
   await page.goto('http://127.0.0.1:8788/');await page.locator('flt-glass-pane').waitFor({state:'attached',timeout:60000});
   const activate=async()=>{const placeholder=page.locator('flt-semantics-placeholder');if(await placeholder.count())await placeholder.evaluate(e=>e.click());};await activate();
   const locate=async(locator,timeout=30000)=>{const until=Date.now()+timeout;if(!(await locator.count())){await page.mouse.move(180,500);await page.mouse.wheel(0,-15000);await page.waitForTimeout(250);}while(!(await locator.count())&&Date.now()<until){await page.mouse.move(180,650);await page.mouse.wheel(0,400);await page.waitForTimeout(250);}await locator.scrollIntoViewIfNeeded();return locator;};
   const click=async(label)=>{const button=await locate(page.getByRole('button',{name:label}));await button.click();};
   const back=async()=>{await page.getByRole('button',{name:'Back',exact:true}).click();};
   const prayers=['صلاة الفجر','صلاة الظهر','صلاة العصر','صلاة المغرب','صلاة العشاء','ركعة تجريبية'];
   for(const prayer of prayers){await click(prayer);await page.getByRole('button',{name:'اختيار فيديو محلي',exact:true}).waitFor();assert.equal(await page.getByRole('checkbox').count(),0);await back();}
   result.six_prayer_routes=true;
   console.log(channel+': six prayer routes passed');
   await click('ركعة تجريبية');const chooser=page.waitForEvent('filechooser');await click('اختيار فيديو محلي');await (await chooser).setFiles(path.join(out,'acceptance-real-video.mp4'));
   await page.getByRole('button',{name:'بدء التحليل على جهازك',exact:true}).waitFor({timeout:120000});
   await click('بدء التحليل على جهازك');await page.getByRole('button',{name:'تصدير التقرير المحلي',exact:true}).waitFor({timeout:180000});
   const history=await page.evaluate(()=>window.iqtadiLocal.listSessions());assert.equal(history.length,1);
   const stored=await page.evaluate(id=>window.iqtadiLocal.loadSession(id),history[0].id);
   assert.equal(stored.report.analysis_mode,'local');assert.equal(stored.report.synthetic,false);assert.equal(Object.keys(stored.predictions).length,16);
   assert.ok(Object.values(stored.predictions).every(r=>r.individual_models.length===3));
   for(const prediction of Object.values(stored.predictions)) if(prediction.pose_detected){
    const classes=Object.keys(prediction.probabilities),average=classes.map(c=>prediction.individual_models.reduce((s,m)=>s+m.probabilities[c],0)/3);
    classes.forEach((c,i)=>assert.ok(Math.abs(prediction.probabilities[c]-average[i])<=1e-6));
    const ranked=average.map((p,i)=>({p,i})).sort((a,b)=>b.p-a.p||b.i-a.i);assert.equal(prediction.class_index,ranked[0].i);
   }
   result.video={frames:16,saved_id:history[0].id,status:stored.report.status,overall_result:stored.report.overall_result};
   console.log(channel+': real16-frame video, report and local save passed');
   await page.screenshot({path:path.join(out,channel+'-flutter-video-report.png'),fullPage:true});
   const download=page.waitForEvent('download');await click('تصدير التقرير المحلي');result.export=(await download).suggestedFilename();
   await back();await click('تقاريري على الجهاز');await page.getByRole('button',{name:/ركعة تجريبية/}).click();await page.getByRole('button',{name:'تصدير التقرير المحلي',exact:true}).waitFor();
   result.history_reopened=true;await back();await back();
   console.log(channel+': export and reopened history passed');
   await click('ركعة تجريبية');await click('تحليل مباشر بالكاميرا');await click('فتح الكاميرا وضبط المكان');
   await page.getByRole('button',{name:'ابدأ التحليل المباشر',exact:true}).waitFor({timeout:120000});
   await page.waitForFunction(()=>Array.from(document.querySelectorAll('[role=button]')).some(e=>e.textContent==='ابدأ التحليل المباشر'&&e.getAttribute('aria-disabled')!=='true'));
   assert.equal(await page.getByRole('checkbox').count(),0);await click('ابدأ التحليل المباشر');
   await locate(page.getByRole('button',{name:/حركة محفوظة/}).first(),120000);
   // Flutter may omit dynamically changing read-only text from its DOM semantics.
   // Unit widget checks validate all three cards; retain actual rendered evidence.
   await page.screenshot({path:path.join(out,channel+'-flutter-live-model-cards.png'),fullPage:true});
   await click('إنهاء الصلاة وإظهار التقرير');
   await page.waitForFunction(async()=>(await window.iqtadiLocal.listSessions()).length===2,null,{timeout:120000});
   await locate(page.getByRole('button',{name:'تصدير التقرير المحلي',exact:true}));
   const sessions=await page.evaluate(()=>window.iqtadiLocal.listSessions());assert.equal(sessions.length,2);
   const live=await page.evaluate(id=>window.iqtadiLocal.loadSession(id),sessions[0].id);
   assert.ok(live.report.captured_actions.length>=1);assert.ok(live.report.captured_actions.every(c=>c.result.individual_models.length===3));
   result.live={frames:Object.keys(live.predictions).length,automatic_captures:live.report.captured_actions.length};
   await page.screenshot({path:path.join(out,channel+'-flutter-live-report.png'),fullPage:true});
   await back();await back();await click('تقاريري على الجهاز');await page.getByRole('button',{name:/ركعة تجريبية/}).first().click();
   await click('حذف التقرير وصور أدلته من الجهاز');
   await page.waitForFunction(async()=>(await window.iqtadiLocal.listSessions()).length===1,null,{timeout:15000});
   assert.equal((await page.evaluate(()=>window.iqtadiLocal.listSessions())).length,1);result.delete_saved=true;
   assert.deepEqual(result.violations,[]);assert.deepEqual(result.errors,[]);result.passed=true;
   console.log(channel+': six local prayer routes, real video, live capture, export, history, delete and privacy passed');
  }catch(error){result.error=error.stack;await page?.screenshot({path:path.join(out,channel+'-flutter-workflow-failure.png'),fullPage:true});await writeFile(path.join(out,channel+'-flutter-workflow-failure.html'),await page.content());console.error(error);}finally{results.push(result);await browser.close();}
 }
 await writeFile(path.join(out,'flutter-workflows.json'),JSON.stringify({tested_at:new Date().toISOString(),results},null,2));assert.ok(results.every(r=>r.passed));
}finally{server.close();}
