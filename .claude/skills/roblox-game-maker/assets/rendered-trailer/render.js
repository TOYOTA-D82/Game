const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const [w, h, out, fps] = process.argv.slice(2);
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: +w, height: +h } });
  page.on('pageerror', (e) => console.log('pageerror:', e.message));
  await page.goto(`http://127.0.0.1:8765/index.html?w=${w}&h=${h}`);
  await page.waitForFunction('window.READY === true', null, { timeout: 120000 });
  const dur = await page.evaluate(() => window.DURATION);
  const n = Math.round(dur * +fps);
  const t0 = Date.now();
  for (let i = 0; i < n; i++) {
    await page.evaluate((t) => window.renderAt(t), i / +fps);
    await page.screenshot({ path: `${out}/f${String(i).padStart(5, '0')}.jpg`, type: 'jpeg', quality: 93 });
    if (i % 90 === 0) console.log(`frame ${i}/${n} ${((Date.now() - t0) / 1000).toFixed(0)}s`);
  }
  console.log(`DONE ${n} frames in ${((Date.now() - t0) / 1000).toFixed(0)}s`);
  await browser.close();
})().catch((e) => { console.log('ERROR', e.message); process.exit(1); });
