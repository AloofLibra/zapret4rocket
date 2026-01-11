#!/bin/sh
set -eu

STATE_DIR="/opt/zapret2/extra_strats/cache/orchestra"
PID_FILE="$STATE_DIR/orchestrator.pid"
LOG_FILE="$STATE_DIR/orchestrator.out"
LOCK_FILE="$STATE_DIR/locked.tsv"
LUA_LOCKED_FILE="/opt/zapret2/lua/locked.lua"
FAIL_FILE="$STATE_DIR/fails.tsv"
RUN_LOCK_DIR="$STATE_DIR/run.lock"

log() {
  printf "%s %s\n" "$(date +%Y-%m-%dT%H:%M:%S)" "$*" >> "$LOG_FILE"
}

ensure_files() {
  mkdir -p "$STATE_DIR"
  touch "$LOCK_FILE" "$LOG_FILE" "$FAIL_FILE"
}

write_locked_lua() {
  tmp="${LUA_LOCKED_FILE}.tmp"
  {
    cat <<'LUA'
local LOCKED_PATH = "__LOCKED_PATH__"
local last_load = 0
local cache_ttl = 2
local LOCKED_TLS = {}
local LOCKED_HTTP = {}
local LOCKED_UDP = {}

local function load_locked_tables()
  local now = os.time()
  if now and (now - last_load) < cache_ttl then return end
  last_load = now or 0
  LOCKED_TLS = {}
  LOCKED_HTTP = {}
  LOCKED_UDP = {}

  local f = io.open(LOCKED_PATH, "r")
  if not f then return end
  for line in f:lines() do
    if line ~= "" then
      local p1, p2, p3 = string.match(line, "^([^\t]+)\t([^\t]+)\t([^\t]+)$")
      if p1 then
        local profile = string.lower(p1)
        local proto = string.lower(p2)
        local strat = tonumber(p3)
        if strat then
          if proto == "http" then LOCKED_HTTP[profile] = strat
          elseif proto == "udp" then LOCKED_UDP[profile] = strat
          else LOCKED_TLS[profile] = strat end
        end
      else
        local p, s = string.match(line, "^([^\t]+)\t([^\t]+)$")
        if p and s then
          local strat = tonumber(s)
          if strat then LOCKED_TLS[string.lower(p)] = strat end
        end
      end
    end
  end
  f:close()
end

function locked_strategy_for_profile(profile, proto)
  if not profile then return nil end
  profile = string.lower(tostring(profile))
  proto = string.lower(tostring(proto or "tls"))
  load_locked_tables()
  if proto == "http" then return LOCKED_HTTP[profile] end
  if proto == "udp" then return LOCKED_UDP[profile] end
  return LOCKED_TLS[profile]
end

function desync_profile_key(desync)
  if desync.profile then return tostring(desync.profile) end
  if desync.profile_id then return tostring(desync.profile_id) end
  if desync.profileid then return tostring(desync.profileid) end
  if desync.profile_num then return tostring(desync.profile_num) end
  if desync.profile_name then return tostring(desync.profile_name) end
  if desync.arg and desync.arg.profile then return tostring(desync.arg.profile) end
  if desync.arg and desync.arg.key then return tostring(desync.arg.key) end
  if desync.func_instance then return tostring(desync.func_instance) end
  return "default"
end

function circular_locked(ctx, desync)
  orchestrate(ctx, desync)
  if not desync.track then
    DLOG_ERR("circular_locked: conntrack is missing but required")
    return
  end

  local hrec = automate_host_record(desync)
  if not hrec then
    DLOG("circular_locked: passing with no tampering")
    return
  end

  if not hrec.ctstrategy then
    local uniq = {}
    local n = 0
    for i, instance in pairs(desync.plan) do
      if instance.arg.strategy then
        n = tonumber(instance.arg.strategy)
        if not n or n < 1 then
          error("circular_locked: strategy number '"..tostring(instance.arg.strategy).."' is invalid")
        end
        uniq[tonumber(instance.arg.strategy)] = true
        if instance.arg.final then
          hrec.final = n
        end
      end
    end
    n = 0
    for i, v in pairs(uniq) do
      n = n + 1
    end
    if n ~= #uniq then
      error("circular_locked: strategies numbers must start from 1 and increment. gaps are not allowed.")
    end
    hrec.ctstrategy = n
  end

  if hrec.ctstrategy == 0 then
    error("circular_locked: add strategy=N tag argument to each following instance ! N must start from 1 and increment")
  end

  local proto = "tls"
  if desync.dis and desync.dis.udp then
    proto = "udp"
  elseif desync.l7payload == "http_req" or desync.l7payload == "http_reply" then
    proto = "http"
  end

  local profile = desync_profile_key(desync)
  local locked = locked_strategy_for_profile(profile, proto)
  if locked and locked >= 1 and locked <= hrec.ctstrategy then
    hrec.nstrategy = locked
    DLOG("circular_locked: locked strategy "..hrec.nstrategy.." profile="..profile)
  else
    hrec.nstrategy = 1
    DLOG("circular_locked: start from strategy 1 profile="..profile)
  end

  local verdict = VERDICT_PASS
  DLOG("circular_locked: current strategy "..hrec.nstrategy.." profile="..profile)
  while true do
    local instance = plan_instance_pop(desync)
    if not instance then break end
    if instance.arg.strategy and tonumber(instance.arg.strategy) == hrec.nstrategy then
      verdict = plan_instance_execute(desync, verdict, instance)
    end
  end

  return verdict
end
LUA
  } > "$tmp"
  sed -i "s|__LOCKED_PATH__|$LOCK_FILE|g" "$tmp"
  mv "$tmp" "$LUA_LOCKED_FILE"
}

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

kill_existing_runs() {
  if is_running; then
    kill "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null || true
    rm -f "$PID_FILE"
  fi
  rm -rf "$RUN_LOCK_DIR"

  if command -v pgrep >/dev/null 2>&1; then
    pgrep -f "$0 run" | while IFS= read -r pid; do
      [ -n "$pid" ] && [ "$pid" != "$$" ] && kill "$pid" 2>/dev/null || true
    done
    pgrep -f "$0 run" | while IFS= read -r pid; do
      [ -n "$pid" ] && [ "$pid" != "$$" ] && kill -9 "$pid" 2>/dev/null || true
    done
  else
    ps w | awk -v pat="$0 run" '$0 ~ pat {print $1}' | while IFS= read -r pid; do
      [ -n "$pid" ] && [ "$pid" != "$$" ] && kill "$pid" 2>/dev/null || true
    done
  fi
}

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
  write_locked_lua
}

lock_remove() {
  profile="$1"
  proto="$2"
  strat="$3"
  tmp="${LOCK_FILE}.tmp"
  awk -v pr="$profile" -v p="$proto" -v s="$strat" 'BEGIN{FS=OFS="\t"}{
    if (!($1==pr && $2==p && $3==s)) print
  }' "$LOCK_FILE" > "$tmp" && mv "$tmp" "$LOCK_FILE"
  write_locked_lua
}

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

clear_stale_lock() {
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

run_loop() {
  ensure_files
  write_locked_lua
  log "orchestrator: start"

  if ! mkdir "$RUN_LOCK_DIR" 2>/dev/null; then
    clear_stale_lock
    if ! mkdir "$RUN_LOCK_DIR" 2>/dev/null; then
      log "orchestrator: already running (lock held)"
      exit 0
    fi
  fi
  echo $$ > "$RUN_LOCK_DIR/pid"
  trap 'rm -rf "$RUN_LOCK_DIR"' EXIT INT TERM

  if command -v logread >/dev/null 2>&1; then
    log_source() { logread -f; }
  elif command -v journalctl >/dev/null 2>&1; then
    log_source() { journalctl -f -u zapret2; }
  else
    log "orchestrator: no syslog source found"
    exit 1
  fi

  current_host=""
  current_strategy=""
  current_proto="tls"
  current_profile=""

  log_source | while IFS= read -r line; do
    case "$line" in
      *"desync profile"*)
        profile="$(printf "%s\n" "$line" | sed -n "s/.*desync profile[[:space:]=:#]*//p")"
        profile="${profile%% *}"
        if [ -n "$profile" ]; then
          current_profile="$profile"
        fi
        ;;
      *"profile="*)
        profile="$(printf "%s\n" "$line" | sed -n "s/.*profile=\\([^ ]*\\).*/\\1/p")"
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
      *"LUA: circular: rotate strategy to "*|*"LUA: circular_locked: rotate strategy to "*)
        strat="$(printf "%s\n" "$line" | sed -n "s/.*rotate strategy to \\([0-9][0-9]*\\).*/\\1/p")"
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
  done
}

case "${1:-}" in
  start)
    ensure_files
    kill_existing_runs
    "$0" run >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    ;;
  stop)
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
    write_locked_lua
    ;;
  *)
    echo "Usage: $0 {start|stop|status|run|sync}"
    exit 1
    ;;
esac
