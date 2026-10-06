// DOM event tests without a browser: button lifecycle, replies and safe rendering.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
class Node {
  constructor(tag, document) { this.tagName = tag; this.document = document; this.children = []; this.attributes = {}; this.listeners = {}; this.value = ''; this._text = ''; }
  setAttribute(key, value) { this.attributes[key] = value; }
  appendChild(child) { this.children.push(child); return child; }
  removeChild(child) { this.children.splice(this.children.indexOf(child), 1); }
  get firstChild() { return this.children[0]; }
  set textContent(value) { this._text = value; }
  get textContent() { return this._text + this.children.map(child => child.textContent).join(' '); }
  addEventListener(type, callback) { (this.listeners[type] ||= []).push(callback); }
  fire(type, extra = {}) { const event = {preventDefault() {}, target: this, ...extra}; for (const callback of this.listeners[type] || []) callback(event); }
  focus() { this.document.activeElement = this; }
}
function boot(readyState = 'complete') {
  const document = {readyState, listeners: {}, createElement(tag) { return new Node(tag, this); }, addEventListener: Node.prototype.addEventListener, fire: Node.prototype.fire};
  document.body = new Node('body', document); document.activeElement = document.body;
  const window = {};
  // Any accidental network or storage dependency must fail these tests.
  const context = {document, window, fetch() { throw Error('Unexpected network'); }, localStorage: {getItem() {throw Error('Storage unavailable');}}};
  vm.runInNewContext(fs.readFileSync('website/static/js/chat_assistant.js', 'utf8'), context);
  if (readyState === 'loading') document.fire('DOMContentLoaded');
  window.SecureWaveAssistant.init(); window.SecureWaveAssistant.init();
  assert.equal(document.body.children.length, 2, 'One widget after repeated init');
  return {document, window};
}
const {document} = boot(); boot('loading');
const [help, panel] = document.body.children;
const [header, messages, quick, form] = panel.children;
const [input] = form.children;
assert.equal(panel.hidden, true);
help.focus(); help.fire('click');
assert.equal(panel.hidden, false); assert.equal(help.attributes['aria-expanded'], 'true');
assert.equal(document.activeElement, input);
const ask = text => {input.value = text; form.fire('submit'); return messages.children.at(-1).textContent;};
assert.match(ask('How do I install?'), /DEB.*Ubuntu 24.04 ARM64/);
assert.match(ask('What does premium cost?'), /9\.99.*99\.99/);
assert.match(ask('I cannot login'), /sign in|Sign in/);
assert.match(ask('VPN fails to connect'), /installed SecureWave app/);
assert.match(ask('What about privacy?'), /not saved or sent/);
assert.match(ask('I need a human agent'), /not a live support agent/);
assert.match(ask('unrecognized question'), /contact support/);
const before = messages.children.length; ask('    '); assert.equal(messages.children.length, before);
for (const button of quick.children) {
  button.fire('click'); assert(messages.children.at(-1).textContent.length > 60);
}
ask('<img src=x onerror=alert(1)>');
assert(messages.children.at(-2).children[0]._text.includes('<img'));
assert.equal(messages.children.at(-2).children[0].children.length, 0, 'Question stays plain text');
document.fire('keydown', {key: 'Escape'});
assert.equal(panel.hidden, true); assert.equal(help.attributes['aria-expanded'], 'false'); assert.equal(document.activeElement, help);
help.fire('click'); header.children[1].fire('click'); assert.equal(panel.hidden, true);
for (const name of fs.readdirSync('website/static').filter(name => name.endsWith('.html'))) {
  const page = fs.readFileSync('website/static/' + name, 'utf8');
  assert.equal((page.match(/src="\/js\/chat_assistant\.js\?v=20261006-support" defer/g) || []).length, 1, name);
}
console.log('PASS: every page loads support; Help/close/Escape/focus; seven quick topics; typed answers; unknown/blank input; plain-text safety; storage-independent and duplicate-safe initialization.');
