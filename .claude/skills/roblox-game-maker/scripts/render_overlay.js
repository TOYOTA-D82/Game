// Renders shorts_overlay.html to a transparent 1080x1920 PNG.
// node render_overlay.js <overlay.html> <out.png> '<json: title, zh, tagline, search, sub, icon>'
const { chromium } = require('playwright');
(async () => {
  const [html, out, json] = process.argv.slice(2);
  const params = JSON.parse(json || '{}');
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1080, height: 1920 } });
  await page.goto('file://' + html);
  await page.evaluate((p) => {
    for (const id of ['title', 'zh', 'tagline', 'search', 'sub']) document.getElementById(id).innerHTML = p[id] || '';
    document.getElementById('icon').setAttribute('src', p.icon || '');
  }, params);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(400);
  await page.screenshot({ path: out, omitBackground: true });
  await browser.close();
})();
