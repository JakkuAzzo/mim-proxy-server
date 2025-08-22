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
- PROXY_PATH (default: /cardInfo) — path prefix intercepted by proxy.
- REWRITE_FIND / REWRITE_REPLACE / REWRITE_IS_REGEX=1 — optional on-the-fly HTML replacement.
- BALANCE_FROM / BALANCE_TO — simple string substitutions in HTML.
- TEST_TIMEOUT (seconds) — per test script shell timeout wrapper.

## Domain Recon & Automation (Permission Required)

The toolkit can (with your explicit authorization for the target) perform a lightweight scan, mirror the site, analyze mirrored HTML for candidate rewrite targets, and then launch the proxy against that domain.

Commands:

```bash
./scripts/dev.sh domain:scan example.com        # nmap -Pn -p 80,443
./scripts/dev.sh domain:mirror example.com      # httrack depth=3 mirror -> mirror/example.com
./scripts/dev.sh domain:analyze example.com     # analyze mirrored HTML; suggests candidate path
./scripts/dev.sh domain:prep                    # interactive end-to-end flow
```

Interactive flow steps (domain:prep):

1. nmap reachability (ports 80,443 by default)
2. httrack mirror (depth 3; adjustable via HTTRACK_DEPTH env) into mirror/`<domain>`
3. Analyze (pattern catalog: currencyCall, zeroBalanceGBP, balanceWord, cardInfoPath, giftCard, amountPattern, jsonBalanceKey, priceClass, dataBalanceAttr)
4. Offer suggested path (candidatePath) for PROXY_PATH
5. Offer rewrite pattern selection or custom
6. Optionally start proxy with selected env vars and run tests
7. Emit JSON report: reports/`<domain>`-`<timestamp>`.json

### Adjustable Scan / Mirror Depth

Environment variables for tuning:

```bash
NMAP_PORTS="80,443,8080,8443"   # override default port list
NMAP_OPTS="-Pn"                 # extra nmap flags (appended)
HTTRACK_DEPTH=4                  # override default depth (3)
```

### Non-Interactive (CI) Mode

Use environment flags plus domain:prep:CI to skip prompts (or run domain:prep with CI=1):

Example CI invocation (assumes permission):

```bash
CI=1 DOMAIN=example.com PROXY_PATH=/cardInfo \
REWRITE_FIND="formatCurrency('GBP', '£', '0.00', '{2}{3}')" \
REWRITE_REPLACE="formatCurrency('GBP', '£', '1000.00', '{2}{3}')" \
./scripts/dev.sh domain:prep
```

Behavior in CI mode:

- Skips interactive questions
- Uses provided DOMAIN / PROXY_PATH / rewrite envs
- Performs scan, mirror, analyze
- Starts proxy & runs test_all automatically if RUN_TESTS=1
- Generates report JSON as usual

Minimal example (auto path selection, run tests):

```bash
CI=1 DOMAIN=example.com RUN_TESTS=1 ./scripts/dev.sh domain:prep
```

Generated report structure:

```json
{
	"domain": "example.com",
	"timestamp": "20250101-120000",
	"candidatePath": "/cardInfo",
	"rewrite": { "find": "...", "replace": "...", "isRegex": "0" },
	"analysis": { ...mirror analysis summary... },
	"testResult": "passed|failed|skipped"
}
```

## Notes

- The proxy decompresses gzip/deflate/br to modify HTML and returns uncompressed content with corrected headers.
- Only /cardInfo HTML is modified; other routes stream through untouched.
- Dynamic rewrites can be layered via env vars; see Env section.

# mim-proxy-server

i originally made this because i found a gift card generator and postman didn't work so i wondered if i can mangle the requests via proxy. Turns out you can pretty easily. So i built this tool for safe ethical testing of developer domains :)

# mim-proxy-server
