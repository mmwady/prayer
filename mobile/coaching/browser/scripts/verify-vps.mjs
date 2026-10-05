// Real public HTTPS acceptance; model inference is real, camera input is simulated.
import { chromium } from 'playwright';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
const origin = new URL(process.argv[2]).origin;
assert.equal(new URL(origin).protocol, 'https:');
const project = fileURLToPath(new URL('../../', import.meta.url));
const out = path.resolve(project, '../../output/vps');
await mkdir(out, { recursive: true });
const references = JSON.parse(await readFile(new URL('../test/fixtures/image_reference.json', import.meta.url), 'utf8'));
const fixture = references.images.find(x => x.result.confidence > .99 && x.result.recovery_method === 'standard');
const image = 'data:image/jpeg;base64,' + (await readFile(new URL('../test/fixtures/' + fixture.path, import.meta.url))).toString('base64');
const result = { origin, tested_at: new Date().toISOString(), passed: false, errors: [], requests: [], failed_requests: [], console_errors: [], camera: 'simulated canvas stream; physical device unverified' };
const browser = await chromium.launch({ channel: 'chrome', headless: true });
let page;
try {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, acceptDownloads: true, serviceWorkers: 'block' });
  await context.addInitScript(image => {
    navigator.mediaDevices.getUserMedia = async () => {
      const img = new Image(); img.src = image; await img.decode();
      const canvas = document.createElement('canvas'); canvas.width = img.naturalWidth; canvas.height = img.naturalHeight;
      const draw = () => canvas.getContext('2d').drawImage(img, 0, 0); draw();
      const stream = canvas.captureStream(8), timer = setInterval(draw, 125);
      stream.getVideoTracks()[0].addEventListener('ended', () => clearInterval(timer));
      return stream;
    };
  }, image);
  context.on('request', r => {
    if (!r.url().startsWith('https:')) return;
    result.requests.push({ url: r.url(), method: r.method(), has_body: !!r.postData() });
  });
  page = await context.newPage(); page.on('pageerror', e => result.errors.push(e.message));
  // Keep the loading state visible long enough to verify its real percentage.
  // Only the automated browser is throttled; public hosting is unchanged.
  const network = await context.newCDPSession(page);
  await network.send('Network.enable');
  await network.send('Network.emulateNetworkConditions', { offline: false, latency: 50,
    downloadThroughput: 1024 * 1024, uploadThroughput: 1024 * 1024 });
  page.on('requestfailed', r => result.failed_requests.push({ url: r.url(), error: r.failure()?.errorText }));
  page.on('console', m => { if (m.type() === 'error') result.console_errors.push(m.text()); });
  await page.goto(origin, { waitUntil: 'domcontentloaded', timeout: 120000 });
  await page.locator('flt-glass-pane').waitFor({ state: 'attached', timeout: 120000 });
  const placeholder = page.locator('flt-semantics-placeholder');
  if (await placeholder.count()) await placeholder.evaluate(e => e.click());
  assert.ok(await page.evaluate(() => isSecureContext && !!navigator.mediaDevices));
  const locate = async locator => {
    if (!await locator.count()) { await page.mouse.move(10, 650); await page.mouse.wheel(0, -15000); await page.waitForTimeout(300); }
    const until = Date.now() + 600000;
    while (Date.now() < until) {
      const box = await locator.count() ? await locator.boundingBox({ timeout: 500 }).catch(() => null) : null;
      if (box && box.y >= 0 && box.y + box.height <= 844) {
        if (await locator.getAttribute('aria-disabled') !== 'true') return locator;
        await page.waitForTimeout(300); continue;
      }
      // Flutter scrolls its canvas list, not the surrounding browser document.
      // Wheel outside the camera's HTML platform view so Flutter receives it.
      await page.mouse.move(10, 650); await page.mouse.wheel(0, box && box.y < 0 ? -350 : 350); await page.waitForTimeout(300);
    }
    throw Error('Control not visible: ' + locator);
  };
  const click = async name => (await locate(page.getByRole('button', { name }))).click({ timeout: 240000 });
  const back = async () => page.getByRole('button', { name: 'Back', exact: true }).click();
  const waitSessions = async count => {
    const until = Date.now() + 240000;
    while (Date.now() < until) {
      const sessions = await page.evaluate(() => window.iqtadiLocal.listSessions());
      if (sessions.length === count) return sessions;
      await page.waitForTimeout(500);
    }
    throw Error('Timed out waiting for ' + count + ' saved local reports');
  };
  await page.screenshot({ path: path.join(out, 'public-home.png'), fullPage: true });
  for (const name of ['صلاة الفجر', 'صلاة الظهر', 'صلاة العصر', 'صلاة المغرب', 'صلاة العشاء', 'ركعة تجريبية']) {
    await click(name); await page.getByRole('button', { name: 'اختيار فيديو محلي', exact: true }).waitFor(); await back();
  }
  result.six_prayer_routes = true; console.log('Public six-prayer navigation passed');
  await click('ركعة تجريبية');
  const chooser = page.waitForEvent('filechooser'); await click('اختيار فيديو محلي');
  await (await chooser).setFiles(path.resolve(project, '../../output/local-training/acceptance-real-video.mp4'));
  await page.getByRole('button', { name: 'جارٍ فتح الفيديو…', exact: true }).waitFor({ state: 'hidden', timeout: 15000 });
  await page.waitForFunction(() => {
    const p = window.iqtadiLocal.initializationProgress();
    return p.phase === 'downloading' && p.asset.endsWith('.task') && p.total > 0 && p.loaded >= p.total * .1;
  }, null, { timeout: 240000 });
  await locate(page.locator('[aria-label*="تحميل موديل الحركة"]'));
  result.model_progress = await page.evaluate(() => window.iqtadiLocal.initializationProgress());
  assert.ok(result.model_progress.total > 0);
  await page.screenshot({ path: path.join(out, 'public-model-progress.png'), fullPage: true });
  console.log('Public local video opened independently; model download percentage is visible');
  await page.getByRole('button', { name: 'بدء التحليل على جهازك', exact: true }).waitFor({ timeout: 240000 });
  await click('بدء التحليل على جهازك');
  result.initialization = await page.evaluate(() => window.iqtadiLocal.initialize());
  assert.equal(result.initialization.mode, 'worker');
  assert.equal(result.requests.filter(r => r.url.includes('/assets/pose_landmarker_heavy.task')).length, 1);
  const history = await waitSessions(1);
  const stored = await page.evaluate(id => window.iqtadiLocal.loadSession(id), history[0].id);
  assert.equal(stored.report.analysis_mode, 'local'); assert.equal(stored.report.synthetic, false);
  assert.equal(Object.keys(stored.predictions).length, 16);
  assert.ok(Object.values(stored.predictions).every(r => r.individual_models.length === 3));
  result.video = { frames: 16, status: stored.report.status, overall_result: stored.report.overall_result };
  await page.screenshot({ path: path.join(out, 'public-video-report.png'), fullPage: true });
  console.log('Public HTTPS real local video and three-model inference passed');
  await back(); await click('ركعة تجريبية'); await click('تحليل مباشر بالكاميرا'); await click('فتح الكاميرا وضبط المكان');
  await page.waitForTimeout(1500);
  const startLive = await locate(page.getByRole('button', { name: 'ابدأ التحليل المباشر', exact: true }));
  await startLive.evaluate(element => element.click());
  console.log('Public simulated camera started through the accessible start control');
  await page.waitForTimeout(12000);
  await page.screenshot({ path: path.join(out, 'public-live-capture.png'), fullPage: true });
  await click('إنهاء الصلاة وإظهار التقرير');
  const sessions = await waitSessions(2);
  const live = await page.evaluate(id => window.iqtadiLocal.loadSession(id), sessions[0].id);
  assert.ok(live.report.captured_actions.length >= 1);
  result.live = { frames: Object.keys(live.predictions).length, captures: live.report.captured_actions.length };
  await page.screenshot({ path: path.join(out, 'public-live-report.png'), fullPage: true });
  console.log('Public HTTPS simulated camera with real inference passed');
  const privatePosts = result.requests.filter(r => r.has_body);
  assert.deepEqual(privatePosts, [], 'Prayer video/camera sent a network payload');
  const headers = { 'X-Iqtadi-Account': '1', Origin: origin };
  const config = await context.request.get(origin + '/api/v1/accounts/config', { headers });
  assert.equal(config.status(), 200); result.accounts = await config.json();
  const rejected = await context.request.get(origin + '/api/v1/accounts/config', { headers: { ...headers, Origin: 'https://unauthorized.example' } });
  assert.equal(rejected.status(), 403);
  for (const route of ['/admin', '/admin/prayer', '/openapi.json', '/recognizer/missing.onnx', '/missing.wasm']) {
    const response = await context.request.get(origin + route); assert.equal(response.status(), 404, route);
  }
  result.admin_blocked = true; result.missing_assets_404 = true;
  const health = await context.request.get(origin + '/healthz'); assert.equal(health.status(), 200); result.health = await health.json();
  // Reopen the public entry point; native camera platform views can move the
  // browser document's scroll position outside Flutter's virtual app bar.
  await page.goto(origin, { waitUntil: 'domcontentloaded', timeout: 120000 });
  await page.locator('flt-glass-pane').waitFor({ state: 'attached', timeout: 120000 });
  const reopenedPlaceholder = page.locator('flt-semantics-placeholder');
  if (await reopenedPlaceholder.count()) await reopenedPlaceholder.evaluate(e => e.click());
  await click(/الحساب والمتابعة — اختياري/);
  await page.screenshot({ path: path.join(out, 'public-accounts.png'), fullPage: true });
  assert.deepEqual(result.errors, []); result.passed = true;
} catch (e) {
  result.error = e.stack; console.error(e);
  await writeFile(path.join(out, 'public-failure.html'), await page.content()).catch(() => {});
  await page?.screenshot({ path: path.join(out, 'public-failure.png'), fullPage: true }).catch(() => {});
  process.exitCode = 1;
} finally {
  await writeFile(path.join(out, 'acceptance.json'), JSON.stringify(result, null, 2));
  await browser.close();
  console.log(JSON.stringify({ passed: result.passed, video: result.video, live: result.live, accounts: result.accounts, error: result.error }));
}
