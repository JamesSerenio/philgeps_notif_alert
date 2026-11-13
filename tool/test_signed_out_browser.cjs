// Flutter's Windows test server mishandles CanvasKit paths. Route these assets
// from the installed SDK before the test iframe loads; no SDK/app files change.
const { chromium } = require('playwright');
const { spawn } = require('node:child_process');
const fs = require('node:fs/promises');
const path = require('node:path');
const sdkRoot = path.resolve(process.env.FLUTTER_CANVASKIT_PATH || 'C:/flutter/bin/cache/flutter_web_sdk/canvaskit');
let browser, attaching, output = '';
const child = spawn(process.env.FLUTTER_BIN || 'C:/flutter/bin/flutter.bat', [
  'test', 'test/dashboard_scrape_test.dart', '--platform', 'chrome', '--no-pub',
  '--reporter', 'expanded', '--timeout', '45s', '--verbose',
], { shell: true, windowsHide: true, env: {
  ...process.env,
  CHROME_EXECUTABLE: process.env.CHROME_EXECUTABLE || 'C:/Program Files/Google/Chrome/Application/chrome.exe',
} });
async function attach(endpoint) {
  browser = await chromium.connectOverCDP(endpoint);
  await browser.contexts()[0].route('**/canvaskit/**', async route => {
    const relative = new URL(route.request().url()).pathname.split('/canvaskit/')[1];
    const file = path.resolve(sdkRoot, relative);
    if (!file.startsWith(sdkRoot + path.sep)) return route.abort();
    await route.fulfill({body:await fs.readFile(file), contentType:file.endsWith('.wasm') ? 'application/wasm' : 'text/javascript'});
  });
  console.log('Chrome connected; using installed local CanvasKit assets.');
}
function consume(data) {
  const text = data.toString();
  output = (output + text).slice(-50000);
  const endpoint = output.match(/DevTools listening on (ws:\/\/[^\s]+)/)?.[1];
  if (endpoint && !attaching) attaching = attach(endpoint).catch(error => {
    console.error(error.message); process.exitCode = 1;
  });
  for (const line of text.split('\n')) if (/\d\d:\d\d \+|All tests|EXCEPTION|TestFailure|Error:|failed|supabase_flutter/i.test(line)) console.log(line.trim());
}
child.stdout.on('data', consume);
child.stderr.on('data', consume);
child.on('error', error => { console.error(error.message); process.exitCode = 1; });
child.on('exit', async code => {
  if (attaching) await attaching;
  if (browser) await browser.close().catch(() => {});
  process.exitCode = code || process.exitCode || 0;
});
