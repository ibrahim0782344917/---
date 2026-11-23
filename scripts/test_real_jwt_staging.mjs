/**
 * Staging-only real JWT/HTTP smoke test for Supabase shitreed-test.
 * Usage: Node.js 20+, environment variables only; never commit credentials.
 * This script sends real password sign-ins and uses returned signed access tokens.
 * It does not modify app data or deploy anything.
 */
const fixedUrl = 'https://tgvdwotbrnhcoykuxdpr.supabase.co';
const required = [
  'TEST_SUPABASE_PUBLISHABLE_KEY',
  'TEST_ADMIN_EMAIL', 'TEST_ADMIN_PASSWORD',
  'TEST_MERCHANT_EMAIL', 'TEST_MERCHANT_PASSWORD',
  'TEST_SPARE_EMAIL', 'TEST_SPARE_PASSWORD',
];
const missing = required.filter((key) => !process.env[key]);
if (missing.length) {
  console.error('Missing environment variable names: ' + missing.join(', '));
  process.exit(2);
}
if ((process.env.TEST_SUPABASE_URL ?? fixedUrl).replace(/\/$/, '') !== fixedUrl) {
  throw new Error('This suite is restricted to the exact shitreed-test Supabase URL');
}
const apiKey = process.env.TEST_SUPABASE_PUBLISHABLE_KEY;

async function request(path, { method = 'GET', accessToken, payload } = {}) {
  const headers = { apikey: apiKey };
  if (payload !== undefined) headers['content-type'] = 'application/json';
  if (accessToken) headers.authorization = 'Bearer ' + accessToken;
  const response = await fetch(fixedUrl + path, {
    method, headers, body: payload === undefined ? undefined : JSON.stringify(payload),
    signal: AbortSignal.timeout(15000),
  });
  const body = await response.json().catch(() => null);
  return { status: response.status, ok: response.ok, body };
}
function expect(value, label) {
  if (!value) throw new Error('FAILED: ' + label);
  console.log('PASS: ' + label);
}
async function signIn(prefix) {
  const response = await request('/auth/v1/token?grant_type=password', {
    method: 'POST',
    payload: {
      email: process.env['TEST_' + prefix + '_EMAIL'],
      password: process.env['TEST_' + prefix + '_PASSWORD'],
    },
  });
  // Deliberately never log response bodies, bearer tokens, email addresses or user IDs.
  expect(response.ok && typeof response.body?.access_token === 'string',
    prefix + ': Supabase issued real JWT (' + response.status + ')');
  const token = response.body.access_token;
  const who = await request('/auth/v1/user', { accessToken: token });
  expect(who.ok && typeof who.body?.id === 'string',
    prefix + ': JWT accepted by Auth server');
  return token;
}
async function rpc(name, token) {
  return request('/rest/v1/rpc/' + name, { method: 'POST', accessToken: token, payload: {} });
}
async function listOrders(token) {
  return request('/rest/v1/orders?select=id&limit=100', { accessToken: token });
}

try {
  const admin = await signIn('ADMIN');
  const merchant = await signIn('MERCHANT');
  const spare = await signIn('SPARE');

  const adminCheck = await rpc('shitreed_is_admin', admin);
  const merchantCheck = await rpc('shitreed_is_admin', merchant);
  const spareCheck = await rpc('shitreed_is_admin', spare);
  expect(adminCheck.ok && adminCheck.body === true, 'ADMIN: authorized by database');
  expect(merchantCheck.ok && merchantCheck.body === false, 'MERCHANT: cannot become admin');
  expect(spareCheck.ok && spareCheck.body === false, 'SPARE: cannot become admin');

  const roles = await Promise.all([
    rpc('shitreed_admin_role', admin),
    rpc('shitreed_admin_role', merchant),
    rpc('shitreed_admin_role', spare),
  ]);
  expect(roles[0].ok && roles[0].body === 'super_admin', 'ADMIN: super_admin role');
  expect(roles[1].ok && roles[1].body === null, 'MERCHANT: no admin role');
  expect(roles[2].ok && roles[2].body === null, 'SPARE: no admin role');

  const adminDashboard = await rpc('shitreed_admin_dashboard', admin);
  const merchantDashboard = await rpc('shitreed_admin_dashboard', merchant);
  const spareDashboard = await rpc('shitreed_admin_dashboard', spare);
  expect(adminDashboard.ok, 'ADMIN: admin dashboard RPC permitted');
  expect(!merchantDashboard.ok, 'MERCHANT: admin dashboard RPC denied');
  expect(!spareDashboard.ok, 'SPARE: admin dashboard RPC denied');

  const merchantContacts = await rpc('shitreed_my_store_contacts', merchant);
  const spareContacts = await rpc('shitreed_my_store_contacts', spare);
  expect(merchantContacts.ok && Array.isArray(merchantContacts.body) &&
    merchantContacts.body.length >= 1, 'MERCHANT: own store contact permitted');
  expect(spareContacts.ok && Array.isArray(spareContacts.body) &&
    spareContacts.body.length === 0, 'SPARE: other store contact hidden');

  const spareOrders = await listOrders(spare);
  expect(spareOrders.ok && Array.isArray(spareOrders.body) &&
    spareOrders.body.length === 0, 'SPARE: orders of other users hidden');

  const anonymousOrders = await listOrders();
  expect(anonymousOrders.ok && Array.isArray(anonymousOrders.body) &&
    anonymousOrders.body.length === 0, 'ANON: no orders visible');

  const anonymousAdmin = await rpc('shitreed_admin_dashboard');
  expect(!anonymousAdmin.ok, 'ANON: admin RPC denied');

  console.log('REAL JWT STAGING SMOKE TEST PASSED; no app data was changed.');
} catch (error) {
  // Only self-authored labels are displayed. Do not reveal HTTP bodies or secrets.
  console.error('JWT staging smoke test stopped: ' + error.message);
  process.exitCode = 1;
}
