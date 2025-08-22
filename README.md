# Hack Server Toolkit

Utilities to run a local echo server (server.js) and a reverse proxy (proxy-server.js) that forwards to a target and rewrites the /cardInfo balance.

## Prerequisites
- Node.js 18+

## Quickstart
```bash
# Install deps and browsers for Playwright
./scripts/dev.sh install

# Start proxy (background)
./scripts/dev.sh start
# Optional: start echo server
./scripts/dev.sh start:server

# View status / logs
./scripts/dev.sh status
./scripts/dev.sh logs

# Run tests
./scripts/dev.sh test:playwright
./scripts/dev.sh test:selenium

# Stop
./scripts/dev.sh stop
```

## Env
- TARGET (default: https://tsuk.claim.cards) — upstream origin for proxy.

## Notes
- The proxy decompresses gzip/deflate/br to modify HTML and returns uncompressed content with corrected headers.
- Only /cardInfo HTML is modified; other routes stream through untouched.
# mim-proxy-server
