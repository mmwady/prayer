// Real Flutter signup/verification/login on an isolated local development-mail host.
// The host simulates an initial mail outage; no external SMTP/Resend request is made.
import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { mkdir, readdir, writeFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../../../', import.meta.url));
const origin = process.env.IQTADI_PUBLIC_URL;
assert.ok(origin && ['127.0.0.1', 'localhost'].includes(new URL(origin).hostname));
const out = path.join(root, 'output/mail-acceptance');
await mkdir(out, { recursive: true });
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const result = { passed: false, external_delivery: false, errors: [] };
let page;
try {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
  page = await context.newPage();
  page.on('pageerror', error => result.errors.push(error.message));
  const activate = async () => {
    await page.locator('flt-glass-pane').waitFor({ state: 'attached', timeout: 90000 });
    const placeholder = page.locator('flt-semantics-placeholder');
    if (await placeholder.count()) await placeholder.evaluate(element => element.click());
  };
  const locate = async locator => {
    const deadline = Date.now() + 30000;
    await page.mouse.move(180, 500); await page.mouse.wheel(0, -10000);
    while (!(await locator.count()) && Date.now() < deadline) {
      await page.mouse.move(180, 650); await page.mouse.wheel(0, 350);
      await page.waitForTimeout(200);
    }
    await locator.scrollIntoViewIfNeeded(); return locator;
  };
  const click = async name => (await locate(page.getByRole('button', { name, exact: typeof name === 'string' }).first())).click();
  const type = async (name, value) => {
    await (await locate(page.getByRole('textbox', { name, exact: typeof name === 'string' }).first())).click();
    await page.waitForTimeout(150);
    await page.keyboard.press('Control+A'); await page.keyboard.type(value, { delay: 20 });
    await page.keyboard.press('Tab'); await page.waitForTimeout(150);
  };
  await page.goto(origin); await activate();
  await click(/الحساب — اختياري/); await click('إنشاء حساب جديد');
  const address = `mail.acceptance.${Date.now()}@example.com`;
  const password = 'Acceptance!2026';
  await type('الاسم', 'Mail Acceptance');
  await type('البريد الإلكتروني', address); await type(/كلمة المرور/, password);
  await click('إنشاء الحساب');
  await locate(page.getByText(/تم حفظ الحساب؛ طلب إرسال رابط التفعيل معلّق/));
  await page.screenshot({ path: path.join(out, 'queued-signup.png'), fullPage: true });
  result.queued_registration_ui = true;
  console.log('Real UI signup saved account and displayed pending mail.');
  const login = await context.request.post(origin + '/api/v1/accounts/session', {
    headers: { 'X-Iqtadi-Account': '1', 'X-Iqtadi-Platform': 'web' }, data: { email: address, password },
  });
  assert.equal(login.status(), 403);
  result.unverified_login_rejected = true;
  await writeFile(path.join(out, 'release-mail.flag'), 'allow local development outbox');
  let files = []; const until = Date.now() + 90000;
  while (!files.length && Date.now() < until) {
    files = (await readdir(path.join(out, 'mail')).catch(() => [])).filter(name => name.endsWith('.eml'));
    if (!files.length) await page.waitForTimeout(500);
  }
  assert.equal(files.length, 1, 'Background retry must deliver exactly one local message.');
  result.automatic_retry_to_local_outbox = true;
  console.log('Background retry wrote local email without another signup request.');
  const parser = 'import sys,re; from email import policy; from email.parser import BytesParser; m=BytesParser(policy=policy.default).parsebytes(open(sys.argv[1],"rb").read()); print(re.search(r"https?://\\S+",m.get_body(preferencelist=("plain",)).get_content()).group())';
  const { stdout } = await promisify(execFile)(process.env.IQTADI_TEST_PYTHON, [
    '-c', parser, path.join(out, 'mail', files[0]),
  ]);
  const link = stdout.trim();
  assert.equal(new URL(link).origin, origin);
  const verification = await context.newPage();
  await verification.goto(link);
  await verification.getByRole('button', { name: 'تأكيد', exact: true }).click();
  await verification.getByText('تم تفعيل البريد بنجاح. عد إلى التطبيق وسجّل الدخول.').waitFor();
  await verification.close();
  result.real_verification_page = true;
  await click('لدي حساب بالفعل'); await click('تسجيل الدخول');
  await locate(page.getByRole('button', { name: /أسرتي/ }));
  await page.screenshot({ path: path.join(out, 'verified-account.png'), fullPage: true });
  await page.reload(); await activate();
  const me = await context.request.get(origin + '/api/v1/accounts/me', {
    headers: { 'X-Iqtadi-Account': '1', 'X-Iqtadi-Platform': 'web' },
  });
  assert.ok(me.ok()); assert.equal((await me.json()).email, address);
  result.login_and_cookie_reload = true;
  assert.deepEqual(result.errors, []);
  result.passed = true;
} catch (error) {
  result.failure = error.stack;
  await page?.screenshot({ path: path.join(out, 'failure.png'), fullPage: true, timeout: 10000 }).catch(() => {});
} finally {
  await writeFile(path.join(out, 'browser-result.json'), JSON.stringify(result, null, 2));
  await browser.close();
}
console.log(JSON.stringify(result));
assert.ok(result.passed, 'Inspect output/mail-acceptance/browser-result.json');
