#!/bin/sh
set -eu

STATE_DIR="/opt/zapret2/extra_strats/cache/orchestra"
PID_FILE="$STATE_DIR/orchestrator.pid"
LOG_FILE="$STATE_DIR/orchestrator.out"
LOCK_FILE="$STATE_DIR/locked.tsv"
LUA_LOCKED_FILE="/opt/zapret2/lua/locked.lua"
FAIL_FILE="$STATE_DIR/fails.tsv"
RUN_LOCK_DIR="$STATE_DIR/run.lock"
LOGREAD_PID_FILE="$STATE_DIR/logread.pid"
LOGREAD_FILTER="LUA:|desync profile|hostname:|payload_type=|l7payload=|l7proto=|proto=udp| : desync"

# Логируем строку с timestamp в файл оркестратора.
log() {
  printf "%s %s\n" "$(date +%Y-%m-%dT%H:%M:%S)" "$*" >> "$LOG_FILE"
}

# Создаем папку состояния и нужные файлы, если их нет.
ensure_files() {
  mkdir -p "$STATE_DIR"
  touch "$LOCK_FILE" "$LOG_FILE" "$FAIL_FILE"
}

# Проверяем наличие locked.lua по ожидаемому пути.
ensure_locked_lua() {
  if [ ! -f "$LUA_LOCKED_FILE" ]; then
    log "orchestrator: missing locked.lua at $LUA_LOCKED_FILE"
    return 1
  fi
  return 0
}

# Проверяем, запущен ли процесс оркестратора.
is_running() {
  if [ -f "$PID_FILE" ]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    rm -f "$PID_FILE"
  fi
  return 1
}

# Останавливаем существующие запуски и очищаем состояние.
kill_existing_runs() {
  target="orchestrator.sh run"

  if [ -f "$PID_FILE" ]; then
    old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      kill "$old_pid" 2>/dev/null || true
      sleep 1
      kill -9 "$old_pid" 2>/dev/null || true
    fi
  fi

  if command -v pgrep >/dev/null 2>&1; then
    pgrep -f "$target" | while IFS= read -r pid; do
      [ -n "$pid" ] && [ "$pid" != "$$" ] && kill "$pid" 2>/dev/null || true
    done
    sleep 1
    pgrep -f "$target" | while IFS= read -r pid; do
      [ -n "$pid" ] && [ "$pid" != "$$" ] && kill -9 "$pid" 2>/dev/null || true
    done
  else
    ps w | awk -v pat="$target" '$0 ~ pat {print $1}' | while IFS= read -r pid; do
      [ -n "$pid" ] && [ "$pid" != "$$" ] && kill "$pid" 2>/dev/null || true
    done
    sleep 1
    ps w | awk -v pat="$target" '$0 ~ pat {print $1}' | while IFS= read -r pid; do
      [ -n "$pid" ] && [ "$pid" != "$$" ] && kill -9 "$pid" 2>/dev/null || true
    done
  fi

  rm -rf "$RUN_LOCK_DIR"
  rm -f "$PID_FILE"

  if [ -f "$LOGREAD_PID_FILE" ]; then
    lrpid="$(cat "$LOGREAD_PID_FILE" 2>/dev/null || true)"
    if [ -n "$lrpid" ] && kill -0 "$lrpid" 2>/dev/null; then
      kill "$lrpid" 2>/dev/null || true
      sleep 1
      kill -9 "$lrpid" 2>/dev/null || true
    fi
    rm -f "$LOGREAD_PID_FILE"
  fi

  ps w | grep -F "logread -f -e $LOGREAD_FILTER" | grep -v grep | awk '{print $1}' | while IFS= read -r pid; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  done
}

# Добавляем фиксацию стратегии для профиля/протокола.
lock_add() {
  profile="$1"
  proto="$2"
  strat="$3"
  tmp="${LOCK_FILE}.tmp"
  awk -v pr="$profile" -v p="$proto" -v s="$strat" 'BEGIN{FS=OFS="\t"}{
    if ($1==pr && $2==p && $3==s) found=1
    print
  } END{
    if (!found) print pr,p,s
  }' "$LOCK_FILE" > "$tmp" && mv "$tmp" "$LOCK_FILE"
}

# Удаляем фиксацию стратегии для профиля/протокола.
lock_remove() {
  profile="$1"
  proto="$2"
  strat="$3"
  tmp="${LOCK_FILE}.tmp"
  awk -v pr="$profile" -v p="$proto" -v s="$strat" 'BEGIN{FS=OFS="\t"}{
    if (!($1==pr && $2==p && $3==s)) print
  }' "$LOCK_FILE" > "$tmp" && mv "$tmp" "$LOCK_FILE"
}

# Записываем информацию о фейле в лог.
log_fail() {
  profile="$1"
  proto="$2"
  host="$3"
  strat="$4"
  reason="$5"
  printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$(date +%Y-%m-%dT%H:%M:%S)" \
    "${profile:-unknown}" \
    "${proto:-unknown}" \
    "${host:-unknown}" \
    "${strat:-unknown}" \
    "${reason:-fail}" >> "$FAIL_FILE"
}

# Удаляем зависший run.lock, если pid не живой.
clear_stale_run_lock() {
  if [ -d "$RUN_LOCK_DIR" ]; then
    lock_pid=""
    if [ -f "$RUN_LOCK_DIR/pid" ]; then
      lock_pid="$(cat "$RUN_LOCK_DIR/pid" 2>/dev/null || true)"
    fi
    if [ -z "$lock_pid" ] || ! kill -0 "$lock_pid" 2>/dev/null; then
      rm -rf "$RUN_LOCK_DIR"
    fi
  fi
}

# Основной цикл: читаем лог и фиксируем события/ошибки.
run_loop() {
  ensure_files
  ensure_locked_lua || exit 1
  log "orchestrator: start"

  if ! mkdir "$RUN_LOCK_DIR" 2>/dev/null; then
    clear_stale_run_lock
    if ! mkdir "$RUN_LOCK_DIR" 2>/dev/null; then
      log "orchestrator: already running (lock held)"
      exit 0
    fi
  fi
  echo $$ > "$RUN_LOCK_DIR/pid"

  log_fifo="$STATE_DIR/orchestrator.logpipe"
  rm -f "$log_fifo"
  mkfifo "$log_fifo"
  if command -v logread >/dev/null 2>&1; then
    logread -f -e "$LOGREAD_FILTER" > "$log_fifo" &
    log_source_pid=$!
    echo "$log_source_pid" > "$LOGREAD_PID_FILE"
  elif command -v journalctl >/dev/null 2>&1; then
    journalctl -f -u zapret2 > "$log_fifo" &
    log_source_pid=$!
    echo "$log_source_pid" > "$LOGREAD_PID_FILE"
  else
    log "orchestrator: no syslog source found (idle mode)"
    log_source_pid=""
  fi

  cleanup_run() {
    if [ -n "${log_source_pid:-}" ]; then
      kill "$log_source_pid" 2>/dev/null || true
    fi
    rm -f "$log_fifo"
    rm -rf "$RUN_LOCK_DIR"
    rm -f "$LOGREAD_PID_FILE"
  }
  trap 'cleanup_run' EXIT INT TERM

  current_host=""
  current_strategy=""
  current_proto="tls"
  current_profile=""

  if [ -z "${log_source_pid:-}" ]; then
    while true; do
      sleep 60
    done
  fi

  while IFS= read -r line; do
    case "$line" in
      *"desync profile"*)
        profile="$(printf "%s\n" "$line" | sed -n "s/.*desync profile[[:space:]=:#]*//p")"
        profile="${profile%% *}"
        if [ -n "$profile" ]; then
          current_profile="$profile"
        fi
        ;;
      *"LUA: automate: host record key"*)
        host="$(printf "%s\n" "$line" | sed -n "s/.*autostate\\.[^.]*\\.//; s/'$//p")"
        if [ -n "$host" ]; then
          current_host="$(printf "%s\n" "$host" | tr 'A-Z' 'a-z')"
        fi
        ;;
      *"hostname:"*)
        host="$(printf "%s\n" "$line" | sed -n "s/.*hostname:[[:space:]]*//p")"
        host="${host%% *}"
        if [ -n "$host" ]; then
          current_host="$(printf "%s\n" "$host" | tr 'A-Z' 'a-z')"
        fi
        ;;
      *"payload_type=tls_client_hello"*|*"payload_type=tls"*|*"l7payload=tls"*|*"l7proto=tls"*)
        current_proto="tls"
        ;;
      *"payload_type=http_req"*|*"payload_type=http_reply"*|*"l7payload=http"*|*"l7proto=http"*)
        current_proto="http"
        ;;
      *"payload_type=quic_initial"*|*"l7proto=quic"*|*"proto=udp"*|*" udp "*)
        current_proto="udp"
        ;;
      *"LUA: circular: current strategy "*|*"LUA: circular_locked: current strategy "*)
        strat="$(printf "%s\n" "$line" | sed -n "s/.*current strategy \\([0-9][0-9]*\\).*/\\1/p")"
        if [ -n "$strat" ]; then
          current_strategy="$strat"
        fi
        ;;
      *"LUA: automate: failure detected"*|*"LUA: standard_failure_detector: retransmission "*)
        if [ -n "$current_host" ] || [ -n "$current_profile" ] || [ -n "$current_strategy" ]; then
          log_fail "$current_profile" "$current_proto" "$current_host" "$current_strategy" "failure"
        fi
        ;;
    esac
  done < "$log_fifo"
}

case "${1:-}" in
  start)
    ensure_files
    kill_existing_runs
    sleep 1
    "$0" run >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    ;;
  stop)
    kill_existing_runs
    if is_running; then
      kill "$(cat "$PID_FILE")" 2>/dev/null || true
      rm -f "$PID_FILE"
    fi
    ;;
  status)
    if is_running; then
      exit 0
    fi
    exit 1
    ;;
  run)
    run_loop
    ;;
  sync)
    ensure_files
    ensure_locked_lua || exit 1
    ;;
  *)
    echo "Usage: $0 {start|stop|status|run|sync}"
    exit 1
    ;;
esac
