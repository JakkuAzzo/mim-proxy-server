const { chromium } = require('playwright');

(async () => {
  // Global safety timeout
  const kill = setTimeout(() => {
    console.error('Playwright: global timeout exceeded');
    process.exit(124);
  }, 45000);
  const target = process.env.TARGET || 'https://tsuk.claim.cards';
  const proxyUrl = process.env.PROXY || 'http://localhost:8080';
  const skipLanding = process.env.SKIP_LANDING === '1';

  const browser = await chromium.launch();
  const page = await browser.newPage();

  if (!skipLanding) {
    // Load landing page (not through proxy, you manually do captcha in real flows)
    try {
      await page.goto(`${target}/VYquSQXBmMnmYHnqyhmYW8uE?l=en_GB`, { waitUntil: 'domcontentloaded', timeout: 15000 });
    } catch (e) {
      console.warn('Playwright: landing page load failed (continuing):', e.message);
    }
  } else {
    console.log('Playwright: skipping landing page (SKIP_LANDING=1)');
  }

  // Rewrite form to point at our proxy
  await page.evaluate(() => {
    const form = document.querySelector('#landFrom');
    if (form) {
      form.action = 'http://localhost:8080/cardInfo';
      form.method = 'POST';
      // Ensure a couple of test fields exist
      const ensure = (name, val) => {
        let el = form.querySelector(`input[name="${name}"]`);
        if (!el) { el = document.createElement('input'); el.type='hidden'; el.name=name; form.appendChild(el); }
        el.value = val;
      };
      ensure('i', 'PW-123');
      ensure('l', 'en_GB');
    }
  });

  // Try to submit form (captcha may block this in live)
  try {
    await page.click('#landSubmit', { timeout: 2000 });
  } catch {}

  // Navigate directly to proxied card page as a fallback to test response rewrite
  await new Promise(r => setTimeout(r, 800));
  // Poll for proxy readiness and /cardInfo availability (local mock)
  let lastErr;
  for (let attempt = 1; attempt <= 5; attempt++) {
    try {
      // Rely on default wait (commit) to reduce flakiness with minimal HTML
      await page.goto(`${proxyUrl}/cardInfo`, { timeout: 8000 });
      lastErr = null;
      break;
    } catch (e) {
      lastErr = e;
      console.log(`Playwright: attempt ${attempt} to reach proxy failed: ${e.message}`);
      await new Promise(r => setTimeout(r, 1000));
    }
  }
  if (lastErr) throw lastErr;

  const content = await page.content();
  if (!content.includes("formatCurrency('GBP', '£', '1000.00'")) {
    console.error('Playwright: balance rewrite not detected');
    process.exit(1);
  }

  console.log('Playwright: OK - balance rewrite detected');
  await browser.close();
  clearTimeout(kill);
})();
