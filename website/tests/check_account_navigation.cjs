const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
async function check(session, fail = false, ok = true) {
  const protectedLinks = [{hidden: true}, {hidden: true}];
  const guestLinks = [{hidden: false}];
  let ready;
  const document = {
    cookie: '',
    addEventListener(type, callback) { if (type === 'DOMContentLoaded') ready = callback; },
    querySelector() {return null;},
    getElementById() {return null;},
    querySelectorAll(selector) {
      if (selector === '[data-auth-only]') return protectedLinks;
      if (selector === '[data-guest-only]') return guestLinks;
      return [];
    },
  };
  const requests = [];
  const fetch = async (url, options) => {
    requests.push({url, options});
    if (fail) throw Error('Offline');
    return {ok, json: async () => session};
  };
  vm.runInNewContext(fs.readFileSync('website/static/js/site.js', 'utf8'), {document, window: {addEventListener() {}}, fetch});
  ready();
  await new Promise(resolve => setImmediate(resolve));
  const authenticated = !fail && ok && session?.authenticated === true;
  assert(protectedLinks.every(link => link.hidden === !authenticated));
  assert.equal(guestLinks[0].hidden, authenticated);
  assert.equal(requests.length, 1);
  assert.equal(requests[0].url, '/api/auth/session');
  assert.equal(requests[0].options.credentials, 'include');
}
(async () => {
  await check({authenticated: false}); await check({authenticated: true});
  await check(null); await check({authenticated: 'true'});
  await check({}, true); await check({authenticated: true}, false, false);
  for (const name of fs.readdirSync('website/static').filter(name => name.endsWith('.html'))) {
    const page = fs.readFileSync('website/static/' + name, 'utf8');
    for (const link of page.matchAll(/<a\b[^>]*href="\/dashboard(?:\.html)?"[^>]*>/g)) {
      assert.match(link[0], /data-auth-only hidden/, name);
      assert.match(page, /src="\/js\/site.js\?v=20261006-account-nav"/, name);
    }
  }
  const login = fs.readFileSync('website/static/login.html', 'utf8');
  assert(!/class="(?:form-card|form-shell)/.test(login), 'No login card constraint');
  const form = login.match(/<form\b[^>]*data-auth="login"[^>]*>([\s\S]*?)<\/form>/)[1];
  assert.match(form, /data-form-message/); assert.match(form, /id="email"/); assert.match(form, /id="password"/);
  assert.match(login, /autocomplete="username"/); assert.match(login, /autocomplete="current-password"/);
  console.log('PASS: session-confirmed Dashboard visibility; guests, failed requests and invalid sessions stay hidden; all links gated; full-width open login form and existing auth bindings.');
})().catch(error => { console.error(error); process.exitCode = 1; });
