// Dependency-free DOM behavior tests; these do not replace real-browser layout QA.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../static/js/chat_assistant.js'), 'utf8');

function setup({ blocked = false, stored = null } = {}) {
  let active;
  class Element {
    constructor(tag) { this.tag = tag; this.children = []; this.attrs = {}; this.events = {}; this.classList = { add() {}, remove() {} }; }
    appendChild(child) { this.children.push(child); return child; }
    setAttribute(k, v) { this.attrs[k] = v; if (k === 'hidden') this.hidden = true; }
    getAttribute(k) { return this.attrs[k]; }
    set innerHTML(value) { assert.equal(value, ''); this.children = []; }
    addEventListener(k, fn) { (this.events[k] ||= []).push(fn); }
    fire(k, event = {}) { for (const fn of this.events[k] || []) fn(event); }
    focus() { active = this; }
  }
  const document = new Element('document');
  document.body = new Element('body');
  document.readyState = 'complete';
  document.createElement = tag => new Element(tag);
  document.createTextNode = text => ({ textContent: text });
  const localStorage = {
    getItem() { if (blocked) throw Error('Storage blocked'); return stored; },
    setItem(key, value) { if (blocked) throw Error('Storage blocked'); stored = value; },
  };
  const window = { location: {} };
  vm.runInNewContext(source, { document, window, localStorage });
  const all = () => { const walk = e => [e, ...(e.children || []).flatMap(walk)]; return walk(document.body); };
  const byClass = name => all().find(e => (e.className || '').split(' ').includes(name));
  const click = text => { const e = all().find(e => e.tag === 'button' && e.textContent === text); assert.ok(e, text); e.fire('click'); };
  return { window, document, all, byClass, click, storage: () => stored, active: () => active };
}

test('initialization is idempotent and survives restricted or corrupt storage', () => {
  for (const options of [{ blocked: true }, { stored: '{bad' }, { stored: '{"version":1,"messages":[null]}' }, {}]) {
    const app = setup(options);
    assert.equal(app.window.SecureWaveAssistant.init(), app.window.SecureWaveAssistant.init());
    assert.equal(app.all().filter(e => e.className === 'sw-chat-fab').length, 1);
    assert.equal(app.byClass('sw-chat-panel').hidden, true);
  }
});

test('open, close and Escape preserve accessible state and focus', () => {
  const app = setup();
  app.byClass('sw-chat-fab').fire('click');
  assert.equal(app.byClass('sw-chat-panel').hidden, false);
  assert.equal(app.byClass('sw-chat-fab').attrs['aria-expanded'], 'true');
  assert.equal(app.active(), app.byClass('sw-chat-close'));
  app.document.fire('keydown', { key: 'Escape' });
  assert.equal(app.byClass('sw-chat-panel').hidden, true);
  assert.equal(app.active(), app.byClass('sw-chat-fab'));
});

test('help topics navigate to the existing downloads page', () => {
  const app = setup();
  app.click('Download and installation');
  app.click('Download and installation');
  assert.equal(app.window.location.href, '/download.html');
});

test('external help triggers and Enter work without sending a network request', () => {
  const app = setup();
  let prevented = false;
  app.document.fire('click', {
    target: { closest: () => ({ getAttribute: () => 'general' }) },
    preventDefault() { prevented = true; },
  });
  assert.equal(prevented, true);
  assert.equal(app.byClass('sw-chat-panel').hidden, false);
  app.byClass('sw-chat-input').value = 'WireGuard connection';
  app.byClass('sw-chat-input').fire('keydown', { key: 'Enter', preventDefault() {} });
  assert.ok(app.all().some(e => (e.textContent || '').includes('Review diagnostics')));
  assert.equal(app.byClass('sw-chat-input').value, '');
});

test('freeform and legacy conversation text are not persisted', () => {
  const app = setup({ stored: JSON.stringify({ version: 1, step: 0, answers: {}, messages: [{ role: 'user', text: 'legacy-private-text' }] }) });
  assert.ok(!app.storage().includes('legacy-private-text'));
  app.byClass('sw-chat-input').value = 'private-text login issue';
  app.byClass('sw-chat-send').fire('click');
  assert.ok(app.all().some(e => (e.textContent || '').includes('Check your email')));
  app.click('Help topics');
  app.click('Choose a plan');
  app.click('Browsing / email');
  assert.ok(!app.storage().includes('private-text'));
  assert.deepEqual(JSON.parse(app.storage()).messages, []);
});
