// Run with NODE_PATH pointing to an existing Playwright installation.
// Response stubs test page behavior only; they do not prove production email/auth.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');

(async () => {
  const browser = await chromium.launch({executablePath: process.env.CHROMIUM_PATH || '/snap/bin/chromium', headless: true, args: ['--no-sandbox']});
  try {
    for (const [suffix, status, body, expected] of [
      ['#token=test-token', 200, {verified: true}, 'Email verified.'],
      ['?token=test-token', 200, {verified: true}, 'Email verified.'],
      ['#token=test-token', 400, {error: {message: 'Invalid verification token'}}, 'invalid or has already been used'],
      ['#token=test-token', 400, {error: {message: 'Verification token has expired'}}, 'has expired'],
      ['#token=test-token', 503, {}, 'could not verify'],
      ['#token=test-token', 0, {}, 'could not reach'],
      ['', 200, {}, 'no verification token'],
    ]) {
      const page = await browser.newPage({viewport: {width: 375, height: 812}});
      let requests = 0;
      await page.route('https://verification.test/**', async route => {
        const request = route.request();
        const url = new URL(request.url());
        if (url.pathname === '/api/auth/verify-email') {
          requests++;
          assert.equal(request.method(), 'POST');
          assert.deepEqual(request.postDataJSON(), {token: 'test-token'});
          assert.equal(request.headers().referer, undefined);
          await new Promise(resolve => setTimeout(resolve, 150));
          if (!status) return route.abort();
          return route.fulfill({status, json: body});
        }
        const file = url.pathname === '/verify-email' ? 'static/verify-email.html' : `static${url.pathname}`;
        const contents = fs.readFileSync(path.join(root, file));
        return route.fulfill({body: contents, contentType: file.endsWith('.html') ? 'text/html' : file.endsWith('.js') ? 'application/javascript' : 'text/css'});
      });
      await page.goto(`https://verification.test/verify-email${suffix}`);
      if (suffix) await page.locator('#verification-status').filter({hasText: 'Verifying your email'}).waitFor();
      await page.locator('#verification-status').filter({hasText: expected}).waitFor();
      assert.equal(page.url(), 'https://verification.test/verify-email');
      assert.equal(requests, suffix ? 1 : 0);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
      if (status === 503 || status === 0) assert.equal(await page.locator('#verification-retry').isVisible(), true);
      await page.close();
    }
    console.log('PASS: 7 browser cases, token privacy, API contract, loading/results, mobile layout');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
