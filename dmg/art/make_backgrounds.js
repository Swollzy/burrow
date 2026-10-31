// Renders the DMG window backgrounds (640x400 plus @2x) with Playwright:
//   node dmg/art/make_backgrounds.js
// Finder draws icon labels in dark text, so the background stays light.
// Icon centres must match make-dmg.sh: app (170,165), Applications (470,165), readme (320,300).
const { chromium } = require('playwright');
const path = require('path');

const apps = {
  Burrow: { accent: '#C98A2E', title: 'Drag Burrow to Applications' },
};

const page = (a) => `<!doctype html><html><body style="margin:0">
<svg xmlns="http://www.w3.org/2000/svg" width="640" height="400" viewBox="0 0 640 400">
  <rect width="640" height="400" fill="#F5F3EF"/>
  <text x="320" y="56" text-anchor="middle" font-family="-apple-system, Helvetica, Arial, sans-serif"
        font-size="20" font-weight="600" fill="#2A2C31">${a.title}</text>
  <g fill="none" stroke="${a.accent}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round">
    <path d="M250 165 H384"/>
    <path d="M366 145 L390 165 L366 185"/>
  </g>
  <text x="320" y="392" text-anchor="middle" font-family="-apple-system, Helvetica, Arial, sans-serif"
        font-size="12" fill="#6B6E75">First time opening it? The Read Me explains the one-time "Open Anyway" step.</text>
</svg></body></html>`;

(async () => {
  const browser = await chromium.launch();
  for (const [name, a] of Object.entries(apps)) {
    for (const scale of [1, 2]) {
      const ctx = await browser.newContext({ viewport: { width: 640, height: 400 }, deviceScaleFactor: scale });
      const p = await ctx.newPage();
      await p.setContent(page(a));
      const file = path.join(__dirname, `${name}-bg${scale === 2 ? '@2x' : ''}.png`);
      await p.screenshot({ path: file, clip: { x: 0, y: 0, width: 640, height: 400 } });
      await ctx.close();
    }
  }
  await browser.close();
})();
