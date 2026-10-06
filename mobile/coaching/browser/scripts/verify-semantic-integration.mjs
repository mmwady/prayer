// Real Flutter, local models, authenticated backend and isolated demo database.
// Invoke only against a local acceptance server; never against production data.
import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../../../', import.meta.url));
const origin = process.env.IQTADI_PUBLIC_URL;
if (!origin || !['127.0.0.1', 'localhost'].includes(new URL(origin).hostname)) {
  throw Error('Set IQTADI_PUBLIC_URL to an isolated loopback acceptance server.');
}
const password = process.env.IQTADI_DEMO_PASSWORD;
assert.ok(password, 'Set the isolated demonstration password.');
const out = path.join(root, 'output/e2e');
await mkdir(out, { recursive: true });
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const result = { passed: false, errors: [], mutations: [], physical_camera: false };
const bounded = (promise, milliseconds = 10000) => Promise.race([
  promise, new Promise((_, reject) => setTimeout(() => reject(Error('Diagnostic timed out')), milliseconds).unref()),
]);
let page;
try {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
  context.on('request', request => {
    if (['GET', 'HEAD'].includes(request.method())) return;
    const url = new URL(request.url());
    let keys = [];
    try { keys = Object.keys(JSON.parse(request.postData())); } catch {}
    if (!['http:', 'https:'].includes(url.protocol) || request.method() === 'OPTIONS') return;
    result.mutations.push({ path: url.pathname, method: request.method(), keys });
  });
  page = await context.newPage();
  page.on('pageerror', error => result.errors.push(error.message));
  await page.goto(origin);
  const activate = async () => {
    await page.locator('flt-glass-pane').waitFor({ state: 'attached', timeout: 120000 });
    const placeholder = page.locator('flt-semantics-placeholder');
    if (await placeholder.count()) await placeholder.evaluate(element => element.click());
  };
  await activate();
  const locate = async locator => {
    const deadline = Date.now() + 30000;
    if (!(await locator.count())) {
      await page.mouse.move(180, 500); await page.mouse.wheel(0, -15000);
    }
    while (!(await locator.count()) && Date.now() < deadline) {
      await page.mouse.move(180, 650); await page.mouse.wheel(0, 350);
      await page.waitForTimeout(250);
    }
    await locator.scrollIntoViewIfNeeded();
    return locator;
  };
  const click = async name => (await locate(page.getByRole('button', { name }).first())).click();
  const back = async () => page.getByRole('button', { name: 'Back', exact: true }).click();
  const api = async (url, method = 'GET', body) => {
    const response = await context.request.fetch(origin + '/api/v1/accounts' + url, {
      method, headers: { 'X-Iqtadi-Account': '1', 'X-Iqtadi-Platform': 'web' }, data: body,
    });
    assert.ok(response.ok(), url + ': ' + response.status());
    return response.json();
  };
  await click(/الحساب — اختياري/);
  const type = async (locator, value) => {
    await (await locate(locator)).click();
    await page.waitForTimeout(150);
    await page.keyboard.press('Control+A');
    await page.keyboard.type(value, { delay: 25 });
    await page.keyboard.press('Tab');
    await page.waitForTimeout(150);
  };
  await type(page.getByRole('textbox', { name: 'البريد الإلكتروني', exact: true }), 'demo@example.com');
  const passwordField = page.getByRole('textbox', { name: /كلمة المرور/ });
  await type(passwordField, password);
  await click('تسجيل الدخول');
  await locate(page.getByRole('button', { name: /أسرتي/ }));
  console.log('Real rendered login and account hub passed.');
  const identity = await api('/me');
  const device = await api('/device');
  assert.equal(device.profile_kind, 'SELF');
  result.authenticated_identity = identity.id;
  result.self_profile = device.child_id;
  await page.screenshot({ path: path.join(out, 'account-hub.png'), fullPage: true });
  await click(/أسرتي/);
  await page.waitForTimeout(1500);
  await page.screenshot({ path: path.join(out, 'family.png'), fullPage: true });
  await back();
  await click(/^مجموعات المسجد/);
  await page.waitForTimeout(1500);
  await page.screenshot({ path: path.join(out, 'mosque-groups.png'), fullPage: true });
  await back(); await back();
  for (const prayer of ['صلاة الفجر', 'صلاة الظهر', 'صلاة العصر', 'صلاة المغرب', 'صلاة العشاء', 'ركعة تجريبية']) {
    await click(prayer);
    await locate(page.getByRole('button', { name: 'اختيار فيديو محلي', exact: true }));
    assert.equal(await page.getByRole('checkbox').count(), 0);
    await back();
  }
  result.six_prayer_routes = true;
  console.log('Family, mosque groups and all six prayer routes passed.');
  console.log('Offline cache:', await bounded(page.evaluate(() => window.iqtadiOffline?.status())));
  await page.waitForFunction(() => window.iqtadiOffline?.status()?.ready, null, { timeout: 240000 });
  console.log('Offline cache ready.');
  await page.waitForFunction(() => !!navigator.serviceWorker.controller, null, { timeout: 30000 });
  await page.reload(); await activate();
  console.log('Reload under service worker passed.');
  await context.setOffline(true);
  await click('صلاة الفجر');
  const chooser = page.waitForEvent('filechooser');
  await click('اختيار فيديو محلي');
  await (await chooser).setFiles(process.env.IQTADI_ACCEPTANCE_VIDEO || path.join(root, 'output/e2e/acceptance-real-video.mp4'));
  const start = page.getByRole('button', { name: 'بدء التحليل على جهازك', exact: true });
  await start.waitFor({ timeout: 120000 });
  await page.waitForFunction(() => Array.from(document.querySelectorAll('[role=button]')).some(e =>
    e.textContent === 'بدء التحليل على جهازك' && e.getAttribute('aria-disabled') !== 'true'), null, { timeout: 120000 });
  await start.click();
  let sessions = [];
  const completedBy = Date.now() + 180000;
  while (!sessions.length && Date.now() < completedBy) {
    sessions = await bounded(page.evaluate(() => window.iqtadiLocal.listSessions()), 30000);
    if (!sessions.length) await page.waitForTimeout(500);
  }
  assert.ok(sessions.length, 'Real local analysis must finish and save its report.');
  const saved = await page.evaluate(id => window.iqtadiLocal.loadSession(id), sessions[0].id);
  assert.equal(saved.report.analysis_mode, 'local');
  assert.equal(saved.report.synthetic, false);
  assert.ok(Object.values(saved.predictions).every(prediction => prediction.individual_models.length === 3));
  const queue = () => Object.entries(localStorage).filter(([key]) => key.includes('account_queue_')).flatMap(([, raw]) => {
    const value = JSON.parse(raw); return typeof value === 'string' ? JSON.parse(value) : value;
  });
  await page.waitForFunction(() => Object.entries(localStorage).filter(([key]) => key.includes('account_queue_')).some(([, raw]) => {
    const value = JSON.parse(raw); return (typeof value === 'string' ? JSON.parse(value) : value).length === 1;
  }), null, { timeout: 15000 });
  const queued = await page.evaluate(queue);
  assert.equal(queued[0].payload.client_attempt_id, saved.id);
  assert.equal(queued[0].payload.movement_score, saved.report.movement_score);
  result.offline = { frames: Object.keys(saved.predictions).length, overall: saved.report.overall_result, score: saved.report.movement_score };
  console.log('Real offline local inference, report and scalar queue passed.');
  await page.screenshot({ path: path.join(out, 'offline-prayer-result.png'), fullPage: true });
  await context.setOffline(false);
  await back(); await click(/مرحبًا/);
  await click('مزامنة');
  await page.waitForFunction(() => Object.entries(localStorage).filter(([key]) => key.includes('account_queue_')).every(([, raw]) => {
    const value = JSON.parse(raw); return (typeof value === 'string' ? JSON.parse(value) : value).length === 0;
  }), null, { timeout: 30000 });
  const progress = await api('/device/progress');
  assert.equal(progress.child_id, device.child_id);
  assert.ok(progress.movement_score !== null);
  result.persisted_score = progress.movement_score;
  const duplicate = await api('/attempts', 'POST', queued[0].payload);
  assert.equal(duplicate.duplicate, true);
  result.idempotent_retry = true;
  await page.reload(); await activate();
  assert.equal((await api('/device')).child_id, device.child_id);
  result.session_survived_reload = true;
  await click(/رفيق المسجد — Mosque Companion/);
  await page.waitForTimeout(1500);
  await page.screenshot({ path: path.join(out, 'companion.png'), fullPage: true });
  result.companion_route = true;
  await click('أحتاج رفيقًا');
  await click('استخدم منزلًا تجريبيًا — محاكاة الانطلاق');
  await click('التالي: اختيار المسجد');
  await click('التالي: تفاصيل الرحلة');
  await click('اعرض الرفقاء المناسبين');
  await locate(page.getByText('رفقاء ورحلات مناسبة', { exact: true }));
  await page.screenshot({ path: path.join(out, 'companion-matches.png'), fullPage: true });
  result.companion_demo_request_and_matching = true;
  assert.deepEqual(result.errors, []);
  for (const mutation of result.mutations) {
    assert.ok(mutation.path.startsWith('/api/v1/accounts/') || mutation.path.startsWith('/api/v1/mosque-demo/'), mutation.path);
    assert.ok(!mutation.keys.some(key => ['image', 'video', 'frame', 'landmarks', 'features', 'tensor', 'predictions'].includes(key)));
  }
  result.passed = true;
} catch (error) {
  result.failure = error.stack;
  result.offline_cache = await bounded(page?.evaluate(() => window.iqtadiOffline?.status())).catch(() => null);
  await page?.screenshot({ path: path.join(out, 'failure.png'), fullPage: true, timeout: 10000 }).catch(() => {});
  await writeFile(path.join(out, 'failure.html'), await bounded(page?.content()).catch(() => '') ?? '');
} finally {
  await writeFile(path.join(out, 'semantic-browser.json'), JSON.stringify(result, null, 2));
  await browser.close();
}
console.log(JSON.stringify(result));
assert.ok(result.passed, 'Inspect output/e2e/semantic-browser.json');
