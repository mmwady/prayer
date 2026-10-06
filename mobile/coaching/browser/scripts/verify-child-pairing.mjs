import { chromium, request as playwrightRequest } from 'playwright';

const origin = process.env.IQTADI_PUBLIC_URL;
const password = process.env.IQTADI_DEMO_PASSWORD;
if (!origin || !password) {
  throw new Error('Set IQTADI_PUBLIC_URL and IQTADI_DEMO_PASSWORD.');
}

const accountHeaders = {
  'X-Iqtadi-Account': '1',
  'X-Iqtadi-Platform': 'android',
};
const anonymous = await playwrightRequest.newContext({
  baseURL: origin,
  extraHTTPHeaders: accountHeaders,
});
const loginResponse = await anonymous.post('/api/v1/accounts/session', {
  data: { email: 'demo@example.com', password },
});
if (!loginResponse.ok()) throw new Error(`Parent login failed: ${loginResponse.status()}`);
const login = await loginResponse.json();
await anonymous.dispose();

const parent = await playwrightRequest.newContext({
  baseURL: origin,
  extraHTTPHeaders: {
    ...accountHeaders,
    Authorization: `Bearer ${login.session_token}`,
  },
});
const families = await (await parent.get('/api/v1/accounts/families')).json();
const family = families.find((value) => value.id === 'demo-family') ?? families[0];
if (!family) throw new Error('No family is available for the pairing check.');
const detail = await (
  await parent.get(`/api/v1/accounts/families/${family.id}`)
).json();
const child = detail.dependents[0];
if (!child) throw new Error('No child is available for the pairing check.');
const pairingResponse = await parent.post(
  `/api/v1/accounts/children/${child.id}/pairing`,
);
if (!pairingResponse.ok()) {
  throw new Error(`Pairing creation failed: ${pairingResponse.status()}`);
}
const pairing = await pairingResponse.json();

const browser = await chromium.launch({
  headless: true,
  ...(process.env.IQTADI_BROWSER_PATH
    ? { executablePath: process.env.IQTADI_BROWSER_PATH }
    : {}),
});
const childContext = await browser.newContext({ serviceWorkers: 'block' });
const page = await childContext.newPage();
const pageErrors = [];
const apiResponses = [];
const apiRequests = [];
page.on('pageerror', (error) => pageErrors.push(error.message));
page.on('request', (request) => {
  if (request.url().includes('/api/v1/accounts/')) {
    const url = new URL(request.url());
    apiRequests.push({ method: request.method(), origin: url.origin, path: url.pathname });
  }
});
page.on('requestfailed', (request) => {
  if (request.url().includes('/api/v1/accounts/')) {
    apiRequests.push({
      method: request.method(),
      path: new URL(request.url()).pathname,
      failure: request.failure()?.errorText,
    });
  }
});
page.on('response', (response) => {
  if (response.url().includes('/api/v1/accounts/')) {
    apiResponses.push({ path: new URL(response.url()).pathname, status: response.status() });
  }
});
let device;
try {
  await page.goto(pairing.qr_url, {
    waitUntil: 'domcontentloaded',
    timeout: 120_000,
  });
  try {
    await page.waitForFunction(
      () => Object.keys(localStorage).some((key) => key.includes('account_child_')),
      null,
      { timeout: Number(process.env.IQTADI_PAIR_TIMEOUT ?? 120_000) },
    );
  } catch (error) {
    console.error(
      JSON.stringify({
        pairing_failed: true,
        url_has_pair_fragment: new URL(page.url()).hash.startsWith('#pair='),
        title: await page.title(),
        canvas_count: await page.locator('canvas').count(),
        storage_keys: await page.evaluate(() => Object.keys(localStorage)),
        api_requests: apiRequests,
        api_responses: apiResponses,
        page_errors: pageErrors,
      }),
    );
    throw error;
  }
  device = await page.evaluate(async () => {
    const response = await fetch('/api/v1/accounts/device', {
      headers: {
        'X-Iqtadi-Account': '1',
        'X-Iqtadi-Platform': 'web',
      },
    });
    if (!response.ok) throw new Error(`Child session failed: ${response.status}`);
    return response.json();
  });
  if (device.child_id !== child.id || device.profile_kind !== 'DEPENDENT') {
    throw new Error('The QR linked a different profile.');
  }
  if (new URL(page.url()).hash) throw new Error('The one-time QR secret remained in the URL.');

  const progress = await page.evaluate(async () => {
    const response = await fetch('/api/v1/accounts/device/progress', {
      headers: {
        'X-Iqtadi-Account': '1',
        'X-Iqtadi-Platform': 'web',
      },
    });
    if (!response.ok) throw new Error(`Child progress failed: ${response.status}`);
    return response.json();
  });
  if (progress.child_id !== child.id) {
    throw new Error('The score belongs to a different child.');
  }

  const revoke = await parent.delete(
    `/api/v1/accounts/children/${child.id}/devices/${device.id}`,
  );
  if (!revoke.ok()) throw new Error(`Parent revocation failed: ${revoke.status()}`);
  await page.waitForFunction(
    () => !Object.keys(localStorage).some((key) => key.includes('account_child_')),
    null,
    { timeout: 45_000 },
  );

  console.log(
    JSON.stringify({
      direct_qr: pairing.qr_url.startsWith(
        `${origin}/api/v1/accounts/pairing/open#pair=`,
      ),
      child_name: child.name,
      profile_kind: device.profile_kind,
      weekly_points: progress.weekly_points,
      weekly_valid_prayers: progress.weekly_valid_prayers,
      streak: progress.streak,
      mosque_group_rankings: progress.group_rankings?.length ?? 0,
      parent_revocation_cleared_child: true,
      pairing_secret_cleared_from_url: true,
    }),
  );
} finally {
  if (device) {
    await parent.delete(
      `/api/v1/accounts/children/${child.id}/devices/${device.id}`,
    );
  }
  await childContext.close();
  await browser.close();
  if (login.practice_session_token) {
    const practice = await playwrightRequest.newContext({
      baseURL: origin,
      extraHTTPHeaders: {
        ...accountHeaders,
        Authorization: `Bearer ${login.practice_session_token}`,
      },
    });
    await practice.delete('/api/v1/accounts/device');
    await practice.dispose();
  }
  await parent.delete('/api/v1/accounts/session');
  await parent.dispose();
}
