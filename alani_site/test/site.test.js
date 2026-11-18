import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { server } from '../server.js';

let root;
before(async () => {
  await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
  root='http://127.0.0.1:'+server.address().port;
});
after(async () => {await new Promise(resolve=>server.close(resolve));});

test('health endpoint returns named independent store', async () => {
  const response=await fetch(root+'/api/health');
  assert.equal(response.status,200);
  const body=await response.json();
  assert.equal(body.service,'alani-natural-store');
});
test('website and protected admin shell exist', async () => {
  const homepage=await fetch(root+'/');
  assert.equal(homepage.status,200);
  assert.match(await homepage.text(),/السيد إبراهيم العاني/);
  const admin=await fetch(root+'/admin');
  assert.equal(admin.status,200);
  assert.match(await admin.text(),/تسجيل دخول مالك المتجر/);
});
test('admin APIs require a user token', async () => {
  const response=await fetch(root+'/api/admin/overview');
  assert.equal(response.status,401);
});
test('unknown paths do not expose files', async () => {
  const response=await fetch(root+'/../../.env');
  assert.equal(response.status,404);
});
test('wrong methods are rejected', async () => {
  const response=await fetch(root+'/site.js',{method:'POST'});
  assert.equal(response.status,405);
});
test('unconfigured checkout is not accepting orders', async () => {
  const response=await fetch(root+'/api/order',{
    method:'POST',headers:{'content-type':'application/json'},
    body:'{}'
  });
  assert.equal(response.status,503);
});

test('StoreKing-inspired storefront layout has accessible sections', async () => {
  const html = await (await fetch(root+'/')).text();
  assert.match(html,/id="promo-carousel"/);
  assert.equal((html.match(/data-promo-slide/g) || []).length,3);
  assert.equal((html.match(/data-category="/g) || []).length,4);
  assert.match(html,/class="mobile-shop-nav"/);
  assert.match(html,/id="video-grid"/);
  assert.match(html,/id="recipe-grid"/);
  const css = await (await fetch(root+'/site.css')).text();
  assert.match(css,/--pine:\s*#01BE5F/i);
  assert.match(css,/\.category-strip\s+a/);
});
