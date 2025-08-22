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

Environment:
  TARGET            Upstream target (default: https://tsuk.claim.cards)
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

ensure_node() {
  command -v node >/dev/null || { echo "Node.js is required"; exit 1; }
  command -v npm >/dev/null || { echo "npm is required"; exit 1; }
}

install() {
  ensure_node
  (cd "$ROOT_DIR" && npm install)
  # Install Playwright browsers
  npx -y playwright install --with-deps || true
}

start() {
  ensure_node
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Already running with PID $(cat "$PID_FILE")"
    exit 0
  fi
  : >"$LOG_FILE"
  echo "Starting proxy-server.js (TARGET=${TARGET:-https://tsuk.claim.cards})..."
  (cd "$ROOT_DIR" && TARGET="${TARGET:-}" nohup node proxy-server.js >>"$LOG_FILE" 2>&1 & echo $! >"$PID_FILE")
  sleep 0.8
  status
}

start_server() {
  ensure_node
  : >"$LOG_FILE.server"
  echo "Starting server.js..."
  (cd "$ROOT_DIR" && nohup node server.js >>"$LOG_FILE.server" 2>&1 & echo $! >"$PID_FILE.server")
  sleep 0.8
  if kill -0 "$(cat "$PID_FILE.server")" 2>/dev/null; then
    echo "server.js running PID $(cat "$PID_FILE.server")"
  else
    echo "server.js failed to start. See $LOG_FILE.server"
  fi
}

start_mock() {
  ensure_node
  : >"$LOG_FILE_MOCK"
  echo "Starting mock upstream on 8081..."
  (cd "$ROOT_DIR" && nohup node scripts/mock-upstream.js >>"$LOG_FILE_MOCK" 2>&1 & echo $! >"$PID_FILE_MOCK")
  sleep 0.6
  if kill -0 "$(cat "$PID_FILE_MOCK")" 2>/dev/null; then
    echo ".mock.pid running PID $(cat "$PID_FILE_MOCK")"
  else
    echo "Mock failed to start. See $LOG_FILE_MOCK"
  fi
}

start_stack() {
  start_mock
  TARGET="http://localhost:8081" start
}

stop() {
  for f in "$PID_FILE" "$PID_FILE.server" "$PID_FILE_MOCK"; do
    if [[ -f "$f" ]]; then
      if kill -0 "$(cat "$f")" 2>/dev/null; then
        kill "$(cat "$f")" || true
        rm -f "$f"
        echo "Stopped $(basename "$f")"
      else
        rm -f "$f"
      fi
    fi
  done
}

status() {
  for f in "$PID_FILE" "$PID_FILE.server" "$PID_FILE_MOCK"; do
    if [[ -f "$f" ]] && kill -0 "$(cat "$f")" 2>/dev/null; then
      echo "$(basename "$f") running: PID $(cat "$f")"
    else
      echo "$(basename "$f") not running"
    fi
  done
}

logs() {
  tail -n 200 -f "$LOG_FILE" "$LOG_FILE.server" "$LOG_FILE_MOCK" 2>/dev/null || tail -n 200 -f "$LOG_FILE" 2>/dev/null || true
}

test_playwright() {
  ensure_node
  run_with_timeout "${TEST_TIMEOUT:-60}" node scripts/playwright.test.js
}

test_selenium() {
  ensure_node
  run_with_timeout "${TEST_TIMEOUT:-60}" node scripts/selenium.test.js
}

test_all() {
  echo "Running Playwright test..."
  test_playwright || exit $?
  echo "Waiting 3s before Selenium..."; sleep 3
  echo "Running Selenium test..."
  test_selenium || exit $?
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
  *) usage; exit 1 ;;

esac
