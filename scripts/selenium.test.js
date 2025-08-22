const { Builder, By, until } = require('selenium-webdriver');
const chrome = require('selenium-webdriver/chrome');

(async function run() {
  const deadline = setTimeout(() => {
    console.error('Selenium: global timeout exceeded');
    process.exit(124);
  }, 45000);
  const target = process.env.TARGET || 'https://tsuk.claim.cards';
  const proxyUrl = process.env.PROXY || 'http://localhost:8080';
  const skipLanding = process.env.SKIP_LANDING === '1';

  const options = new chrome.Options();
  const driver = await new Builder().forBrowser('chrome').setChromeOptions(options).build();
  try {
    if (!skipLanding) {
      try {
        await driver.get(`${target}/VYquSQXBmMnmYHnqyhmYW8uE?l=en_GB`);
      } catch (e) {
        console.warn('Selenium: landing page load failed (continuing):', e.message);
      }
    } else {
      console.log('Selenium: skipping landing page (SKIP_LANDING=1)');
    }

    // Rewrite form to proxy endpoint
    await driver.executeScript(() => {
      const form = document.querySelector('#landFrom');
      if (form) {
        form.action = 'http://localhost:8080/cardInfo';
        form.method = 'POST';
      }
    });

    // Navigate to proxied card page to verify HTML rewrite
    await new Promise(r => setTimeout(r, 800));
    // Retry loop for proxy availability
    let success = false;
  for (let attempt = 1; attempt <= 5; attempt++) {
      try {
    await driver.get(`${proxyUrl}/cardInfo`);
        success = true;
        break;
      } catch (e) {
        console.log(`Selenium: attempt ${attempt} to reach proxy failed: ${e.message}`);
        await new Promise(r => setTimeout(r, 1000));
      }
    }
    if (!success) throw new Error('Selenium: could not reach proxy /cardInfo after retries');
    await driver.wait(until.titleContains('Tesco'), 8000).catch(() => {});

    const html = await driver.getPageSource();
    if (!html.includes("formatCurrency('GBP', '£', '1000.00'")) {
      console.error('Selenium: balance rewrite not detected');
      process.exit(1);
    }

    console.log('Selenium: OK - balance rewrite detected');
  } finally {
    clearTimeout(deadline);
    await driver.quit();
  }
})();
