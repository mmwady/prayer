import { chromium } from 'playwright';
import { serve } from './serve.mjs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { mkdir,writeFile } from 'node:fs/promises';
const root=fileURLToPath(new URL('../../',import.meta.url)),out=path.resolve(root,'../../output/browser');
await mkdir(out,{recursive:true});const server=await serve(path.join(root,'build/web'),8782);
let browser,page;
try{
 browser=await chromium.launch({channel:'chrome',headless:true});page=await browser.newPage({viewport:{width:390,height:844}});const errors=[];
 page.on('pageerror',e=>errors.push(e.message));await page.goto('http://127.0.0.1:8782/');
 await page.locator('flt-glass-pane').waitFor({state:'attached',timeout:60000});await page.waitForTimeout(4000);
 const semantics=page.locator('flt-semantics-placeholder');if(await semantics.count())await semantics.evaluate(el=>el.click());
 await page.getByRole('button',{name:/تحليل الصور والكاميرا على جهازك/}).click({timeout:30000});
 const frame=page.frameLocator('iframe[title="تحليل حركات الصلاة على جهازك"]');
 await frame.locator('#status').filter({hasText:'جاهزة'}).waitFor({timeout:120000});
 assert.equal(await frame.locator('body').evaluate(async()=>{await document.fonts.ready;return document.fonts.check('12px Iqtadi');}),true);
 await page.screenshot({path:path.join(out,'flutter-local-recognizer.png'),fullPage:true});
 assert.deepEqual(errors,[]);await writeFile(path.join(out,'flutter-integration.json'),JSON.stringify({browser:browser.version(),home_card:true,iframe_ready:true,errors},null,2));
 console.log('Flutter home → local recognizer: passed');
}catch(error){await page?.screenshot({path:path.join(out,'flutter-integration-failure.png'),fullPage:true});await writeFile(path.join(out,'flutter-integration-failure.html'),await page.content());throw error;}
finally{await browser?.close();server.close();}
