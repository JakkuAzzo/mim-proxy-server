#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const domain = process.argv[2];
if (!domain) {
  console.error('Usage: mirror-analyze <domain>');
  process.exit(1);
}

const root = path.join(__dirname, '..', 'mirror', domain);
if (!fs.existsSync(root)) {
  console.error('Mirror directory not found:', root);
  process.exit(2);
}

// Extendable pattern catalog
const patternCatalog = {
  currencyCall: /formatCurrency\([^)]*\)/g,
  zeroBalanceGBP: /£\s?0\.00/g,
  zeroBalanceUSD: /\$\s?0\.00/g,
  cardInfoPath: /cardInfo/gi,
  balanceWord: /balance/gi,
  giftCard: /gift\s*card/gi,
  amountPattern: /£\s?[0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2}/g,
  jsonBalanceKey: /"balance"\s*:\s*"?[0-9]/gi,
  priceClass: /class=["'][^"']*(?:price|amount|balance)[^"']*["']/gi,
  dataBalanceAttr: /data-(?:balance|amount)="[0-9.]+"/gi
};

const patterns = Object.entries(patternCatalog);

function scanFile(file) {
  const txt = fs.readFileSync(file, 'utf8');
  const hits = [];
  for (const [name, rx] of patterns) {
    const m = txt.match(rx);
    if (m) hits.push({ name, pattern: rx.toString(), count: m.length });
  }
  if (hits.length) return { file: path.relative(root, file), hits };
  return null;
}

function walk(dir, list = []) {
  for (const entry of fs.readdirSync(dir)) {
    const full = path.join(dir, entry);
    const st = fs.statSync(full);
    if (st.isDirectory()) walk(full, list);
    else if (/\.(?:html?|xhtml|php|asp|aspx|jsp)$/i.test(entry)) {
      const r = scanFile(full);
      if (r) list.push(r);
    }
  }
  return list;
}

const results = walk(root);
results.sort((a,b)=> b.hits.reduce((s,h)=>s+h.count,0) - a.hits.reduce((s,h)=>s+h.count,0));

// Suggest candidate proxy path: first file containing cardInfo or balance pattern
let candidatePath = null;
for (const r of results) {
  if (r.hits.some(h => ['cardInfoPath','balanceWord'].includes(h.name))) {
    candidatePath = '/' + r.file.replace(/index\.(html?|php|jsp)$/,'').replace(/\\/g,'/');
    if (!candidatePath.endsWith('/')) candidatePath = candidatePath;
    break;
  }
}

const summary = {
  domain,
  analyzedFiles: results.length,
  timestamp: new Date().toISOString(),
  candidatePath,
  topMatches: results.slice(0, 30),
  patterns: Object.keys(patternCatalog)
};

console.log(JSON.stringify(summary, null, 2));
