const express = require('express');
const app = express();

app.use(express.urlencoded({ extended: true }));
app.use(express.json());

// Simple mock of upstream /cardInfo that includes the original currency call
app.get('/cardInfo', (_req, res) => {
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.end(`<!doctype html>
  <html>
    <head><title>Tesco - Card Info</title></head>
    <body>
      <h1>Mock Upstream cardInfo</h1>
      <script>
        function formatCurrency(a,b,c,d){return b+" "+c}
        // The proxy should rewrite the next line to 1000.00
        formatCurrency('GBP', '£', '0.00', '{2}{3}');
      </script>
      <div id="balance">Balance: <span>£0.00</span></div>
    </body>
  </html>`);
});

app.all(/.*/, (req, res) => {
  res.status(200).json({ ok: true, path: req.path, method: req.method });
});

const port = process.env.MOCK_PORT ? Number(process.env.MOCK_PORT) : 8081;
app.listen(port, () => console.log(`Mock upstream listening on http://localhost:${port}`));
