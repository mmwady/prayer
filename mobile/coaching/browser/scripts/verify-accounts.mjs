// Actual Flutter Web + backend auth + local models. No mocked inference.
import {chromium} from 'playwright';
import {readFile,readdir,writeFile,mkdir} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
const root=fileURLToPath(new URL('../../../../',import.meta.url));
const out=path.join(root,'output/accounts');await mkdir(out,{recursive:true});
const origin='http://127.0.0.1:8000';
const browser=await chromium.launch({channel:'chrome',headless:true});
const result={browser:browser.version(),errors:[],requests:[],passed:false,physical_camera:false};
let context,page;
try{
 context=await browser.newContext({viewport:{width:390,height:844}});
 context.on('request',r=>{if(!['GET','HEAD'].includes(r.method())){
   const body=r.postData();let keys=[];try{keys=Object.keys(JSON.parse(body));}catch{}
   result.requests.push({path:new URL(r.url()).pathname,method:r.method(),keys});
   assert.ok(!keys.some(k=>['image','video','landmarks','features','tensor','frame','predictions'].includes(k)),'Visual data in HTTP request');
 }});
 page=await context.newPage();page.on('pageerror',e=>result.errors.push(e.message));
 await page.goto(origin,{waitUntil:'domcontentloaded',timeout:120000});await page.locator('flt-glass-pane').waitFor({state:'attached',timeout:120000});
 const activate=async()=>{const p=page.locator('flt-semantics-placeholder');if(await p.count())await p.evaluate(e=>e.click());};await activate();
 const locate=async(locator,timeout=30000)=>{const until=Date.now()+timeout;if(!(await locator.count())){await page.mouse.move(180,500);await page.mouse.wheel(0,-15000);await page.waitForTimeout(250);}while(!(await locator.count())&&Date.now()<until){await page.mouse.move(180,650);await page.mouse.wheel(0,400);await page.waitForTimeout(250);}await locator.scrollIntoViewIfNeeded();return locator;};
 const click=async(name)=>{const button=await locate(page.getByRole('button',{name}));await button.click();};
 const back=async()=>{await page.getByRole('button',{name:'Back',exact:true}).click();};
 await click(/الحساب والمتابعة — اختياري/);
 await page.screenshot({path:path.join(out,'web-account-phone.png'),fullPage:true});
 await writeFile(path.join(out,'account-semantics.html'),await page.content());
 console.log('Account page opened; semantic textboxes:',await page.getByRole('textbox').evaluateAll(nodes=>nodes.map(n=>({label:n.getAttribute('aria-label'),placeholder:n.getAttribute('placeholder')}))));
 // Login is exercised through the real rendered UI. Account creation and email
 // confirmation below use normal public APIs to keep the run repeatable.
 const email='acceptance-'+Date.now()+'@example.com',password='Local acceptance password!';
 const headers={'X-Iqtadi-Account':'1','Content-Type':'application/json','X-Iqtadi-Platform':'web'};
 const api=async(p,method='GET',body)=>{const r=await context.request.fetch(origin+'/api/v1/accounts'+p,{method,headers,data:body});assert.ok(r.ok(),p+': '+r.status()+' '+await r.text());return r.json();};
 await api('/auth/signup','POST',{name:'Mohamed — browser acceptance',email,password,role:'PARENT'});
 const raw=execFileSync(path.join(root,'backend/.venv/Scripts/python.exe'),['-c',
   "import sys,re; from pathlib import Path; from email.parser import BytesParser; from email import policy; messages=[BytesParser(policy=policy.default).parsebytes(p.read_bytes()) for p in Path(sys.argv[1]).glob('*.eml')]; texts=[m.get_body(preferencelist=('plain',)).get_content() for m in messages if sys.argv[2] in str(m['To'])]; print(re.search(r'token=([A-Za-z0-9_-]+)',texts[-1]).group(1))",path.join(out,'mail'),email],{encoding:'utf8'}).trim();
 assert.ok(raw,'Development verification email missing');await api('/auth/verify','POST',{token:raw});
 const type=async(locator,value)=>{const field=await locate(locator);await field.click();await page.waitForTimeout(150);await page.keyboard.press('Control+A');await page.keyboard.type(value,{delay:35});await page.keyboard.press('Tab');await page.waitForTimeout(150);};
 await type(page.getByRole('textbox',{name:'البريد الإلكتروني',exact:true}),email);
 await type(page.getByRole('textbox',{name:/كلمة المرور/}),password);
 await click('تسجيل الدخول');await page.getByRole('button',{name:'لوحة المتابعة',exact:true}).waitFor({timeout:30000});
 const group=await api('/groups','POST',{name:'Acceptance family',timezone:'Africa/Cairo'});
 const child=await api('/groups/'+group.id+'/children','POST',{name:'Omar',age:11});
 await click('لوحة المتابعة');await page.getByRole('button',{name:'ربط جهاز',exact:true}).waitFor({timeout:30000});
 await page.screenshot({path:path.join(out,'web-dashboard-phone.png'),fullPage:true});
 await click('ربط جهاز');await page.waitForTimeout(500);
 await page.screenshot({path:path.join(out,'web-qr-pairing.png'),fullPage:true});
 await click('إغلاق');
 const pairing=await api('/children/'+child.id+'/pairing','POST');
 await back();
 await type(page.getByRole('textbox',{name:'رمز الربط المؤقت',exact:true}),pairing.code);
 await click('ربط الجهاز');await page.getByRole('button',{name:'مزامنة النتائج',exact:true}).waitFor({timeout:30000});
 assert.equal((await api('/device')).child_id,child.id);result.manual_pairing=true;
 await page.reload();await page.locator('flt-glass-pane').waitFor({state:'attached',timeout:60000});await activate();
 await click(/السلام عليكم يا Omar/);await page.getByRole('button',{name:'مزامنة النتائج',exact:true}).waitFor({timeout:30000});result.persisted_session=true;await back();
 console.log('Real backend login, QR rendering, manual Web pairing and reload passed');
 await page.waitForFunction(()=>window.iqtadiOffline?.status()?.ready,null,{timeout:240000});
 await page.waitForFunction(()=>!!navigator.serviceWorker.controller,null,{timeout:30000});
 // Reload under the activated service worker so its model workers are controlled.
 await page.reload({waitUntil:'domcontentloaded'});await page.locator('flt-glass-pane').waitFor({state:'attached',timeout:60000});await activate();
 await context.setOffline(true);
 await click('صلاة الفجر');
 const chooser=page.waitForEvent('filechooser');await click('اختيار فيديو محلي');await (await chooser).setFiles(path.join(root,'output/local-training/acceptance-real-video.mp4'));
 await page.getByRole('button',{name:'بدء التحليل على جهازك',exact:true}).waitFor({timeout:120000});await click('بدء التحليل على جهازك');
 // Completion is proven by persisted report + queued summary, independently of
 // the lazy report list's off-screen export button semantics.
 let sessions=[];const completedBy=Date.now()+180000;
 while(!sessions.length && Date.now()<completedBy){sessions=await page.evaluate(()=>window.iqtadiLocal.listSessions());if(!sessions.length)await page.waitForTimeout(500);}
 assert.ok(sessions.length>0,'The real analysis did not persist a local report');
 const saved=await page.evaluate(id=>window.iqtadiLocal.loadSession(id),sessions[0].id);
 assert.equal(saved.report.analysis_mode,'local');assert.equal(saved.report.synthetic,false);
 assert.ok(Object.values(saved.predictions).every(p=>p.individual_models.length===3));
 // shared_preferences_web JSON-encodes string values; the queue itself is JSON.
 const readQueue=()=>Object.entries(localStorage).filter(([k])=>k.includes('account_queue_')).flatMap(([k,v])=>{const value=JSON.parse(v);return typeof value==='string'?JSON.parse(value):value;});
 await page.waitForFunction(()=>Object.entries(localStorage).filter(([k])=>k.includes('account_queue_')).some(([k,v])=>{const value=JSON.parse(v);return (typeof value==='string'?JSON.parse(value):value).length===1;}),null,{timeout:15000});
 const queued=await page.evaluate(readQueue);
 assert.equal(queued.length,1);assert.equal(queued[0].payload.prayer,'fajr');
 result.offline={frames:Object.keys(saved.predictions).length,overall:saved.report.overall_result,queue:queued.length};
 await page.screenshot({path:path.join(out,'web-offline-result.png'),fullPage:true});
 await back();await click(/السلام عليكم يا Omar/);
 await context.setOffline(false);await click('مزامنة النتائج');
 await page.waitForFunction(()=>Object.entries(localStorage).filter(([k])=>k.includes('account_queue_')).every(([k,v])=>{const value=JSON.parse(v);return (typeof value==='string'?JSON.parse(value):value).length===0;}),null,{timeout:30000});
 const progress=await api('/groups/'+group.id+'/progress');assert.ok(Object.values(progress.children[0].states).some(s=>['UNCERTAIN','INCOMPLETE','ON_TIME','LATE','CORRECT_TIMING_UNKNOWN'].includes(s)));
 result.dashboard_received=progress.children[0].states;
 await click('لوحة المتابعة');await page.getByRole('button',{name:'ربط جهاز',exact:true}).waitFor({timeout:30000});
 for(const width of [320,1024]){await page.setViewportSize({width,height:900});await page.waitForTimeout(500);await page.screenshot({path:path.join(out,'web-dashboard-'+width+'.png'),fullPage:true});}
 // A new context is signed out: inference entry remains freely available.
 const guest=await browser.newContext({viewport:{width:390,height:844}});const guestPage=await guest.newPage();await guestPage.goto(origin);await guestPage.locator('flt-glass-pane').waitFor({state:'attached',timeout:60000});
 const gp=guestPage.locator('flt-semantics-placeholder');await gp.waitFor({state:'attached',timeout:60000});await gp.evaluate(e=>e.click());
 const guestPrayer=guestPage.getByRole('button',{name:/^صلاة الفجر/});const guestBy=Date.now()+30000;
 while(!(await guestPrayer.count())&&Date.now()<guestBy){await guestPage.mouse.move(300,550);await guestPage.mouse.wheel(0,500);await guestPage.waitForTimeout(250);}
 await guestPrayer.scrollIntoViewIfNeeded();await guestPrayer.click();await guestPage.getByRole('heading',{name:'تحليل فيديو — صلاة الفجر',exact:true}).waitFor({timeout:30000});result.guest_prayer_available=true;await guest.close();
 assert.deepEqual(result.errors,[]);result.passed=true;
 console.log('Offline local MediaPipe/three ONNX classifiers, queue, reconnection and dashboard passed');
}catch(error){result.error=error.stack;console.error(error);await page?.screenshot({path:path.join(out,'web-acceptance-failure.png'),fullPage:true,timeout:10000}).catch(()=>{});await writeFile(path.join(out,'web-acceptance-failure.html'),await page?.content().catch(()=> '')??'');}
finally{await writeFile(path.join(out,'web-acceptance.json'),JSON.stringify(result,null,2));await browser.close();}
assert.ok(result.passed,'Inspect output/accounts/web-acceptance.json');
