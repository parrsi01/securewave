const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync('website/static/js/downloads.js', 'utf8');
const manifest = JSON.parse(fs.readFileSync('website/static/downloads/manifest.json', 'utf8'));
const context = {document: {addEventListener() {}}, navigator: {userAgent: ''}};
vm.createContext(context); vm.runInContext(source, context);
for (const [ua, platform, arch, expected] of [
 ['Mozilla Linux aarch64', 'linux', 'arm64', true],
 ['Mozilla Linux x86_64', 'linux', 'x64', false],
 ['Mozilla Windows NT 10.0', 'windows', 'x64', false],
 ['Mozilla iPhone', 'ios', 'arm64', false],
 ['Mozilla Android aarch64', 'android', 'arm64', false],
 ['Mozilla Macintosh', 'macos', 'x64', false],
 ['', 'unknown', 'unknown', false],
]) {
 context.navigator.userAgent = ua;
 const detected = context.detectClientPlatform();
 assert.equal(detected.platform, platform); assert.equal(detected.architecture, arch);
 assert.equal(!!context.bestDownloadForPlatform(manifest.downloads, platform, arch), expected);
}
const card = context.renderCard(manifest.downloads[0]);
assert.match(card, /v1\.0\.0/); assert.match(card, /securewave-vpn_1\.0\.0_arm64\.deb/);
assert(!card.includes('4.0.0'));
console.log('Download selector: seven platform/architecture cases passed.');
