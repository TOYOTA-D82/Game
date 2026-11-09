const { chromium } = require('playwright');
(async () => {
  const [w, h, out, ...times] = process.argv.slice(2);
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: +w, height: +h } });
  page.on('console', (m) => { if (m.type() === 'error') console.log('console:', m.text()); });
  page.on('pageerror', (e) => console.log('pageerror:', e.message));
  await page.goto(`http://127.0.0.1:8765/index.html?w=${w}&h=${h}`);
  await page.waitForFunction('window.READY === true', null, { timeout: 120000 });
  for (const t of times) {
    const t0 = Date.now();
    await page.evaluate((t) => window.renderAt(t), +t);
    await page.screenshot({ path: `${out}/still_${t}.png` });
    console.log('t', t, Date.now() - t0, 'ms');
  }
  await browser.close();
})();
