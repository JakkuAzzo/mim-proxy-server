const express = require('express');
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

// Helper to escape HTML
function escapeHtml(s){return String(s).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));}

// POST /cardInfo returns HTML
app.post('/cardInfo', (req, res) => {
  const payload = {
    method: req.method,
    path: req.originalUrl,
    query: req.query,
    body: req.body
  };
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.end(`<!doctype html><html><body>
    <h1>Posted to /cardInfo</h1>
    <pre>${escapeHtml(JSON.stringify(payload, null, 2))}</pre>
    <p><strong>Balance:</strong> £${req.body.bal || '0.00'}</p>
  </body></html>`);
});

// Quiet the favicon request
app.get('/favicon.ico', (req, res) => res.status(204).end());

// parse URL-encoded form posts
app.use(express.urlencoded({ extended: true }));
app.use(express.json());

// log everything
app.all('/', (req, res) => {
  console.log('\n--- Request ---');
  console.log(req.method, req.originalUrl);
  console.log('Headers:', req.headers);
  console.log('Query:', req.query);
  console.log('Body:', req.body);
  res.status(200).send({
    ok: true,
    method: req.method,
    url: req.originalUrl,
    query: req.query,
    body: req.body
  });
});

app.listen(8080, () => console.log('Listening on http://localhost:8080'));