// Automated acceptance explicitly requested by the user. All fixtures remain local.
import { chromium, firefox, webkit } from 'playwright';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
import { serve } from './serve.mjs';
import { CLASSES } from '../src/core.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const fixtures = path.join(root, 'browser/test/fixtures');
const output = path.resolve(root, '../../output/browser'); await mkdir(output, { recursive: true });
const server = await serve(root, 8781);
const report = { tested_at: new Date().toISOString(), browsers: [], network_payload_violations: [], levels: {}, device_matrix: {} };
report.model_version=JSON.parse(await readFile(path.join(root,'browser/assets/manifest.json'),'utf8')).model_version;
const features = JSON.parse(await readFile(path.join(fixtures, 'features.json'), 'utf8'));
const images = JSON.parse(await readFile(path.join(fixtures, 'image_reference.json'), 'utf8'));
report.corpus_kind = images.corpus_kind;
report.original_image_count = images.original_image_count;
const configurations = process.argv.includes('--all') ? [{name:'Chrome',type:chromium,channel:'chrome'}, {name:'Edge',type:chromium,channel:'msedge'}, {name:'Firefox',type:firefox}, {name:'WebKit engine (not desktop/iOS Safari)',type:webkit}] : process.argv.includes('--chromium') ? [{name:'Chrome',type:chromium,channel:'chrome'}, {name:'Edge',type:chromium,channel:'msedge'}] : [{name:'Chrome',type:chromium,channel:'chrome'}];
const softmax = x => { const max=Math.max(...x), e=x.map(v=>Math.exp(v-max)), sum=e.reduce((a,b)=>a+b); return e.map(v=>v/sum); };
try {
 for(const configuration of configurations) {
  let browser;
  try {
   browser = await configuration.type.launch({channel:configuration.channel,headless:true,args:configuration.type===chromium?['--use-fake-ui-for-media-stream','--use-fake-device-for-media-stream']:[]});
   const context=await browser.newContext({permissions:configuration.type===chromium?['camera']:[]});
   const page=await context.newPage();
   const errors=[];page.on('pageerror',e=>errors.push(e.message));
   context.on('request',request=>{if(request.postData() || !['GET','HEAD'].includes(request.method()) || !request.url().startsWith('http://127.0.0.1:8781/'))report.network_payload_violations.push({url:request.url(),method:request.method(),has_body:!!request.postData()});});
   await page.goto('http://127.0.0.1:8781/browser/test/harness.html');
   const info=await page.evaluate(()=>window.ready); console.log(configuration.name,info);
   assert.equal(info.model_version,report.model_version);
   let maxProbabilityError=0,featureCases=0,disagreements=0,disagreeResult;
   for(const fixture of features) {
    const actual=await page.evaluate(x=>window.client.classify(new Float32Array(x),{recovery_method:'standard',mean_visibility:.9,inference_ms:0}),fixture.features);
    assert.equal(actual.individual_models.length,3);
    if(actual.classifier_disagreement){disagreements++;disagreeResult??=actual;}
    const reference=fixture.logits.map(softmax);
    reference.forEach((p,j)=>assert.equal(actual.individual_models[j].class_index,p.indexOf(Math.max(...p))));
    const referenceMean=CLASSES.map((_,i)=>reference.reduce((s,p)=>s+p[i],0)/3);
    assert.equal(actual.class_index,referenceMean.indexOf(Math.max(...referenceMean)));
    for(let j=0;j<3;j++) for(let i=0;i<8;i++) {const error=Math.abs(actual.individual_models[j].probabilities[CLASSES[i]]-reference[j][i]);maxProbabilityError=Math.max(maxProbabilityError,error);assert.ok(error<2e-6+2e-5*reference[j][i]);}
    CLASSES.forEach(c=>assert.ok(Math.abs(actual.probabilities[c]-actual.individual_models.reduce((s,m)=>s+m.probabilities[c],0)/3)<1e-12));
    assert.equal(actual.class_index,CLASSES.map(c=>actual.probabilities[c]).indexOf(Math.max(...Object.values(actual.probabilities))));featureCases++;
   }
   const measurements=[];
   for(const image of images.images) {
    const actual=await page.evaluate(async image=>{const response=await fetch(new URL('../test/fixtures/'+image.path,location.href));return await window.client.analyze(await response.blob(),true);},image);
    const samePose=actual.result.pose_detected===image.result.pose_detected;
    const sameClass=actual.result.predicted_action===image.result.predicted_action;
    let featureError=null;
    if(actual.features && image.features)featureError=Math.max(...actual.features.map((v,i)=>Math.abs(v-image.features[i])));
    measurements.push({name:image.original_name,python_action:image.result.predicted_action,browser_action:actual.result.predicted_action,same_pose:samePose,same_class:sameClass,python_recovery:image.result.recovery_method,browser_recovery:actual.result.recovery_method,max_feature_error:featureError,individual_count:actual.result.individual_models.length,
     python_hip:image.landmarks?.[23],browser_hip:actual.landmarks?.[23]});
    assert.equal(actual.result.individual_models.length,3);
    if(measurements.length%20===0)console.log(`${configuration.name}: ${measurements.length}/${images.images.length} image comparisons`);
   }
   // Browser fallback initialization with Worker deliberately unavailable.
   await page.evaluate(()=>window.client.close());
   await page.addInitScript(()=>{window.Worker=undefined;});
   await page.reload();const fallback=await page.evaluate(()=>window.ready);assert.equal(fallback.mode,'main-thread-wasm');
   const fallbackResult=await page.evaluate(x=>window.client.classify(new Float32Array(x),{recovery_method:'standard',mean_visibility:.9,inference_ms:0}),features[0].features);assert.equal(fallbackResult.individual_models.length,3);
   const fallbackImage=await page.evaluate(async image=>{const response=await fetch(new URL('../test/fixtures/'+image.path,location.href));return await window.client.analyze(await response.blob());},images.images[0]);
   assert.equal(fallbackImage.result.predicted_action,images.images[0].result.predicted_action);
   await page.evaluate(()=>window.client.close());await page.close();
   const ui=await context.newPage();await ui.goto('http://127.0.0.1:8781/web/recognizer/');
   await ui.waitForFunction(()=>document.querySelector('#status').textContent.includes('جاهزة'),null,{timeout:120000});
   const imageFile=path.join(fixtures,images.images.find(x=>x.result.pose_detected)?.path??images.images[0].path);
   await ui.locator('#upload').setInputFiles(imageFile); await ui.locator('#result .model').nth(2).waitFor({timeout:120000});assert.equal(await ui.locator('#result .model').count(),3);
   await ui.locator('#photo').setInputFiles(imageFile);await ui.waitForFunction(()=>document.querySelector('#status').textContent.includes('تم التحليل'),null,{timeout:120000});
   await ui.setViewportSize({width:390,height:844});await ui.screenshot({path:path.join(output,configuration.name.replaceAll(/[^a-z0-9]/gi,'_')+'-upload.png'),fullPage:true});
   // Deliberately differing decisions must remain visible in both primary and captured UI.
   assert.ok(disagreeResult,'Representative vectors must exercise classifier disagreement');
   await ui.evaluate(r=>{const data=JSON.parse(sessionStorage.getItem('iqtadi-recognizer-session'));data.results=[r];sessionStorage.setItem('iqtadi-recognizer-session',JSON.stringify(data));},disagreeResult);
   await ui.reload();await ui.waitForFunction(()=>document.querySelector('#status').textContent.includes('جاهزة'),null,{timeout:120000});
   assert.equal(await ui.locator('#result .model').count(),3);assert.ok((await ui.locator('#result').innerText()).includes('يختلف عن القرار المجمع'));
   await ui.locator('#captures details').first().evaluate(el=>{el.open=true;});assert.equal(await ui.locator('#captures .model').count(),3);
   await ui.screenshot({path:path.join(output,configuration.name.replaceAll(/[^a-z0-9]/gi,'_')+'-disagreement.png'),fullPage:true});
   let camera='unverified';
   if(configuration.type===chromium){await ui.locator('#start').click();await ui.waitForFunction(()=>!document.querySelector('#snapshot').disabled);await ui.locator('#snapshot').click();await ui.waitForFunction(()=>document.querySelector('#status').textContent.includes('تم التحليل'),null,{timeout:120000});await ui.locator('#live').click();await ui.waitForTimeout(3000);await ui.locator('#stop').click();camera='synthetic browser camera: photo + live start/stop tested; physical device unverified';}
   assert.deepEqual(errors,[]);
   report.browsers.push({name:configuration.name,version:browser.version(),model_version:info.model_version,status:'tested',mode:info.mode,fallback: fallback.mode,featureCases,maxProbabilityError,disagreementCases:disagreements,disagreement_ui:'primary and captured cards verified',image_count:measurements.length,image_class_agreement:measurements.filter(x=>x.same_class).length,image_pose_agreement:measurements.filter(x=>x.same_pose).length,measurements,camera,page_errors:errors});
  }catch(error){report.browsers.push({name:configuration.name,status:'failed_or_unavailable',error:error.stack});console.error(configuration.name,error.message);}
  finally{await browser?.close();}
 }
 report.device_matrix={'desktop Safari':'unverified (requires macOS Safari)','Android Chrome':'unverified (physical device required)','iOS Safari':'unverified (physical device required)'};
 report.levels.identical_features='See tested browser maxProbabilityError and assets/conversion_report.json';
 report.levels.identical_images_100=images.images.length>=100?'100-image corpus executed; measured agreement, not guaranteed parity':'unverified: only '+images.images.length+' existing images available; supply representative corpus';
 await writeFile(path.join(output,'browser-parity.json'),JSON.stringify(report,null,2));
 assert.equal(report.network_payload_violations.length,0);
 assert.ok(report.browsers.some(b=>b.status==='tested'),'No browser acceptance completed');
 console.log(JSON.stringify(report.browsers.map(({measurements,...b})=>b),null,2));
}finally{server.close();}
