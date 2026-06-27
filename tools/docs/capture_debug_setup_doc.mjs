import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';

const [, , htmlPath, pngPath] = process.argv;

if (!htmlPath || !pngPath) {
  console.error('usage: capture_debug_setup_doc.mjs <input.html> <output.png>');
  process.exit(2);
}

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({
  viewport: { width: 1280, height: 1600 },
  deviceScaleFactor: 1
});

await page.goto(pathToFileURL(htmlPath).href);
await page.screenshot({ path: pngPath, fullPage: true });
await browser.close();

