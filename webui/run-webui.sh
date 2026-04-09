#!/bin/bash

set -eu

WEBUI_ROOT="/opt/zapret2/webui"
WEBUI_WWW="$WEBUI_ROOT/www"
WEBUI_CGI="$WEBUI_ROOT/cgi-bin"
WEBUI_RUN="$WEBUI_ROOT/run"
PID_FILE="$WEBUI_RUN/webui.pid"
LOG_FILE="$WEBUI_RUN/webui.log"
PORT="${WEBUI_PORT:-17682}"

ensure_dirs() {
  mkdir -p "$WEBUI_RUN"
}

has_busybox_httpd() {
  if ! command -v busybox >/dev/null 2>&1; then
    return 1
  fi
  busybox --list 2>/dev/null | grep -qx 'httpd'
}

detect_server() {
  if command -v uhttpd >/dev/null 2>&1; then
    echo "uhttpd"
    return
  fi
  if has_busybox_httpd; then
    echo "busybox"
    return
  fi
  echo "none"
}

is_running() {
  [ -f "$PID_FILE" ] || return 1
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null
}

run_server() {
  local server
  server="$(detect_server)"
  case "$server" in
    uhttpd)
      exec uhttpd -f -p "0.0.0.0:${PORT}" -h "$WEBUI_WWW" -x /cgi-bin
      ;;
    busybox)
      exec busybox httpd -f -p "0.0.0.0:${PORT}" -h "$WEBUI_WWW"
      ;;
    *)
      echo "No supported web server found" >&2
      exit 1
      ;;
  esac
}

start_server() {
  ensure_dirs
  if is_running; then
    echo "already running"
    return 0
  fi
  nohup "$0" run >>"$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  sleep 1
  if ! is_running; then
    echo "failed to start"
    return 1
  fi
  echo "started"
}

stop_server() {
  if is_running; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    sleep 1
    if is_running; then
      kill -9 "$(cat "$PID_FILE")" 2>/dev/null || true
    fi
  fi
  rm -f "$PID_FILE"
  echo "stopped"
}

status_server() {
  if is_running; then
    echo "running:$(detect_server):${PORT}"
  else
    echo "stopped:$(detect_server):${PORT}"
  fi
}

print_urls() {
  local hostname ip
  hostname="$(hostname 2>/dev/null || echo localhost)"
  echo "http://127.0.0.1:${PORT}"
  echo "http://localhost:${PORT}"
  echo "http://${hostname}:${PORT}"
  for ip in $(hostname -I 2>/dev/null || true); do
    echo "http://${ip}:${PORT}"
  done
}

case "${1:-}" in
  run)
    run_server
    ;;
  start)
    start_server
    ;;
  stop)
    stop_server
    ;;
  restart)
    stop_server
    start_server
    ;;
  status)
    status_server
    ;;
  urls)
    print_urls
    ;;
  *)
    echo "usage: $0 {run|start|stop|restart|status|urls}" >&2
    exit 1
    ;;
esac
