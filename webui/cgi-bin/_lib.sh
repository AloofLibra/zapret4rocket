#!/usr/bin/env bash

set -u

PATH="/opt/bin:/opt/sbin:$PATH"
export PATH

WEBUI_ROOT="/opt/zapret2/webui"
ZAPRET_ROOT="/opt/zapret2"
CONFIG_FILE="$ZAPRET_ROOT/config"
CONFIG_DEFAULT_FILE="$ZAPRET_ROOT/config.default"
ORCH_DIR="$ZAPRET_ROOT/extra_strats/cache/orchestra"
ORCH_SCRIPT="$ORCH_DIR/orchestrator.sh"
ORCH_LOCK_FILE="${ORCH_LOCK_FILE:-$ORCH_DIR/locked.tsv}"
BUILDER_CACHE_DIR="$ZAPRET_ROOT/extra_strats/cache/builder"
REGISTRY_CACHE_DIR="$ZAPRET_ROOT/extra_strats/cache/registry"
COMPILER_CACHE_DIR="$ZAPRET_ROOT/extra_strats/cache/compiler"
CONTROLPLANE_DIR="$ZAPRET_ROOT/controlplane"
WEBUI_BUILDER_DIR="$ZAPRET_ROOT/extra_strats/cache/webui-builder"
BUILDER_MODULE="$ZAPRET_ROOT/z2r_lib/strategy_builder.sh"

[ -f "$BUILDER_MODULE" ] && . "$BUILDER_MODULE"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; s/\n/\\n/g'
}

send_json() {
  local status="$1"
  local body="$2"
  printf 'Status: %s\r\n' "$status"
  printf 'Content-Type: application/json; charset=utf-8\r\n\r\n'
  printf '%s\n' "$body"
}

send_error() {
  local status="$1"
  local message="$2"
  send_json "$status" "{\"error\":\"$(json_escape "$message")\"}"
  exit 0
}

parse_params() {
  local raw="${QUERY_STRING:-}"
  if [ "${REQUEST_METHOD:-GET}" = "POST" ]; then
    raw="$(dd bs=1 count="${CONTENT_LENGTH:-0}" 2>/dev/null || true)"
  fi
  local part key value
  IFS='&' read -r -a parts <<< "$raw"
  for part in "${parts[@]}"; do
    key="${part%%=*}"
    value="${part#*=}"
    value="${value//+/ }"
    printf -v value '%b' "${value//%/\\x}"
    case "$key" in
      profile) PARAM_PROFILE="$value" ;;
      strategy) PARAM_STRATEGY="$value" ;;
      candidate) PARAM_CANDIDATE="$value" ;;
      candidate_id) PARAM_CANDIDATE_ID="$value" ;;
      candidate_key) PARAM_CANDIDATE_KEY="$value" ;;
      generated_id) PARAM_GENERATED_ID="$value" ;;
    esac
  done
}

json_file_or() {
  local file="$1"
  local fallback="$2"
  if [ -s "$file" ]; then
    cat "$file"
  else
    printf '%s' "$fallback"
  fi
}

first_existing_path() {
  local path
  for path in "$@"; do
    [ -e "$path" ] && { printf '%s\n' "$path"; return 0; }
  done
  return 1
}

first_executable_path() {
  local path
  for path in "$@"; do
    [ -x "$path" ] && { printf '%s\n' "$path"; return 0; }
  done
  return 1
}

webui_builder_catalog_file() {
  first_existing_path \
    "$BUILDER_CACHE_DIR/profile-catalog.json" \
    "$BUILDER_CACHE_DIR/profile_catalog.json" \
    "$REGISTRY_CACHE_DIR/profile-catalog.json" \
    "$REGISTRY_CACHE_DIR/profile_catalog.json" \
    "$REGISTRY_CACHE_DIR/profiles.json"
}

webui_builder_discovery_file() {
  first_existing_path \
    "$BUILDER_CACHE_DIR/discovery-results.json" \
    "$BUILDER_CACHE_DIR/discovery_results.json" \
    "$BUILDER_CACHE_DIR/candidates.json" \
    "$COMPILER_CACHE_DIR/discovery-results.json" \
    "$COMPILER_CACHE_DIR/discovery_results.json" \
    "$COMPILER_CACHE_DIR/candidates.json"
}

webui_builder_active_json_file() {
  first_existing_path \
    "$COMPILER_CACHE_DIR/active-generated.json" \
    "$COMPILER_CACHE_DIR/active_generated.json" \
    "$COMPILER_CACHE_DIR/current-generated.json" \
    "$COMPILER_CACHE_DIR/current_generated.json" \
    "$BUILDER_CACHE_DIR/active-generated.json" \
    "$BUILDER_CACHE_DIR/active_generated.json" \
    "$BUILDER_CACHE_DIR/current-generated.json" \
    "$BUILDER_CACHE_DIR/current_generated.json"
}

webui_builder_discovery_state_file() {
  first_existing_path \
    "$BUILDER_CACHE_DIR/discovery-state.json" \
    "$BUILDER_CACHE_DIR/discovery_state.json" \
    "$COMPILER_CACHE_DIR/discovery-state.json" \
    "$COMPILER_CACHE_DIR/discovery_state.json"
}

webui_builder_discovery_start_script() {
  first_executable_path \
    "$CONTROLPLANE_DIR/webui-discovery-start.sh" \
    "$CONTROLPLANE_DIR/discovery-start.sh" \
    "$CONTROLPLANE_DIR/builder-discovery-start.sh" \
    "$CONTROLPLANE_DIR/builder-discovery.sh" \
    "$ZAPRET_ROOT/builder/discovery-start.sh" \
    "$ZAPRET_ROOT/builder/discovery.sh"
}

webui_builder_apply_script() {
  first_executable_path \
    "$CONTROLPLANE_DIR/webui-apply-candidate.sh" \
    "$CONTROLPLANE_DIR/apply-candidate.sh" \
    "$CONTROLPLANE_DIR/builder-apply-candidate.sh" \
    "$CONTROLPLANE_DIR/builder-apply.sh" \
    "$ZAPRET_ROOT/builder/apply-candidate.sh" \
    "$ZAPRET_ROOT/builder/apply.sh"
}

webui_builder_has_runtime() {
  if type builder_profile_supported >/dev/null 2>&1; then
    return 0
  fi
  webui_builder_catalog_file >/dev/null 2>&1 ||
  webui_builder_discovery_file >/dev/null 2>&1 ||
  webui_builder_active_json_file >/dev/null 2>&1 ||
  webui_builder_discovery_state_file >/dev/null 2>&1 ||
  webui_builder_discovery_start_script >/dev/null 2>&1 ||
  webui_builder_apply_script >/dev/null 2>&1
}

webui_builder_catalog_json() {
  if type builder_profiles_json >/dev/null 2>&1; then
    printf '{"profiles":%s}' "$(builder_profiles_json)"
    return
  fi
  local file
  file="$(webui_builder_catalog_file || true)"
  if [ -n "$file" ]; then
    json_file_or "$file" '{"profiles":[]}'
  else
    printf '%s' '{"profiles":[]}'
  fi
}

webui_builder_discovery_json() {
  local runtime_file cache_file
  if [ -n "${PARAM_PROFILE:-}" ]; then
    runtime_file="$(webui_builder_discovery_runtime_file "$PARAM_PROFILE")"
    if webui_builder_discovery_running "$PARAM_PROFILE" && [ -s "$runtime_file" ]; then
      cat "$runtime_file"
      return
    fi
    cache_file="$(webui_builder_last_session_cache_file "$PARAM_PROFILE")"
    if [ -s "$cache_file" ]; then
      cat "$cache_file"
      return
    fi
  fi
  local file
  file="$(webui_builder_discovery_file || true)"
  if [ -n "$file" ]; then
    json_file_or "$file" '{"candidates":[]}'
  else
    printf '%s' '{"candidates":[]}'
  fi
}

webui_builder_active_json() {
  if type builder_active_json >/dev/null 2>&1; then
    builder_active_json
    return
  fi
  local file
  file="$(webui_builder_active_json_file || true)"
  if [ -n "$file" ]; then
    json_file_or "$file" '{"active":null}'
  else
    printf '%s' '{"active":null}'
  fi
}

webui_builder_discovery_state_json() {
  local file state_file
  if [ -n "${PARAM_PROFILE:-}" ] && webui_builder_discovery_running "${PARAM_PROFILE}"; then
    state_file="$(webui_builder_discovery_state_runtime_file "${PARAM_PROFILE}")"
    if [ -s "$state_file" ]; then
      cat "$state_file"
    else
      printf '{"running":true,"profile":%s,"status":"running","message":"Discovery is running"}' "${PARAM_PROFILE}"
    fi
    return
  fi
  if [ -n "${PARAM_PROFILE:-}" ]; then
    state_file="$(webui_builder_discovery_state_runtime_file "${PARAM_PROFILE}")"
    if [ -s "$state_file" ]; then
      cat "$state_file"
      return
    fi
    printf '{"running":false,"profile":%s,"status":"idle","message":"No active discovery"}' "${PARAM_PROFILE}"
    return
  fi
  file="$(webui_builder_discovery_state_file || true)"
  if [ -n "$file" ]; then
    json_file_or "$file" '{"running":false}'
  else
    printf '%s' '{"running":false}'
  fi
}

webui_builder_request_file() {
  local name="$1"
  mkdir -p "$WEBUI_BUILDER_DIR"
  printf '%s/%s.json\n' "$WEBUI_BUILDER_DIR" "$name"
}

webui_builder_discovery_pid_file() {
  local profile="${1:-}"
  mkdir -p "$WEBUI_BUILDER_DIR"
  printf '%s/discovery-%s.pid\n' "$WEBUI_BUILDER_DIR" "$profile"
}

webui_builder_discovery_log_file() {
  local profile="${1:-}"
  mkdir -p "$WEBUI_BUILDER_DIR"
  printf '%s/discovery-%s.log\n' "$WEBUI_BUILDER_DIR" "$profile"
}

webui_builder_discovery_state_runtime_file() {
  local profile="${1:-}"
  mkdir -p "$WEBUI_BUILDER_DIR"
  printf '%s/discovery-%s.state.json\n' "$WEBUI_BUILDER_DIR" "$profile"
}

webui_builder_candidates_cache_file() {
  local profile="${1:-}"
  mkdir -p "$WEBUI_BUILDER_DIR"
  printf '%s/builder-candidates-%s.json\n' "$WEBUI_BUILDER_DIR" "$profile"
}

webui_builder_last_session_cache_file() {
  local profile="${1:-}"
  mkdir -p "$WEBUI_BUILDER_DIR"
  printf '%s/last-session-%s.json\n' "$WEBUI_BUILDER_DIR" "$profile"
}

webui_builder_discovery_runtime_file() {
  local profile="${1:-}"
  mkdir -p "$WEBUI_BUILDER_DIR"
  printf '%s/discovery-%s.runtime.json\n' "$WEBUI_BUILDER_DIR" "$profile"
}

webui_builder_discovery_running() {
  local profile="${1:-}" pid_file pid
  pid_file="$(webui_builder_discovery_pid_file "$profile")"
  [ -s "$pid_file" ] || return 1
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null
}

webui_start_builder_discovery_async() {
  local profile="${1:-}" pid_file log_file state_file runtime_file started_at finished_at
  [[ "$profile" =~ ^[12]$ ]] || return 1
  if webui_builder_discovery_running "$profile"; then
    return 0
  fi
  pid_file="$(webui_builder_discovery_pid_file "$profile")"
  log_file="$(webui_builder_discovery_log_file "$profile")"
  state_file="$(webui_builder_discovery_state_runtime_file "$profile")"
  runtime_file="$(webui_builder_discovery_runtime_file "$profile")"
  started_at="$(date +%Y-%m-%dT%H:%M:%S%z)"
  rm -f "${runtime_file}.stop"
  cat > "$state_file" <<EOF
{"running":true,"profile":$profile,"status":"running","message":"Discovery is running","started_at":"$started_at"}
EOF
  cat > "$runtime_file" <<EOF
{"running":true,"profile":$profile,"status":"running","message":"Discovery is running","updated_at":"$started_at","phase":"queued","tier":"","checked":0,"total":0,"top_results":[]}
EOF
  nohup bash -lc ". \"$BUILDER_MODULE\"; if builder_run_discovery \"$profile\"; then finished_at=\$(date +%Y-%m-%dT%H:%M:%S%z); printf '%s\n' \"{\\\"running\\\":false,\\\"profile\\\":$profile,\\\"status\\\":\\\"completed\\\",\\\"message\\\":\\\"Discovery completed\\\",\\\"finished_at\\\":\\\"\$finished_at\\\"}\" > \"$state_file\"; else finished_at=\$(date +%Y-%m-%dT%H:%M:%S%z); printf '%s\n' \"{\\\"running\\\":false,\\\"profile\\\":$profile,\\\"status\\\":\\\"failed\\\",\\\"message\\\":\\\"Discovery failed\\\",\\\"finished_at\\\":\\\"\$finished_at\\\"}\" > \"$state_file\"; fi; rm -f \"$pid_file\"" >"$log_file" 2>&1 &
  echo $! > "$pid_file"
}

webui_stop_builder_discovery() {
  local profile="${1:-}" pid_file state_file runtime_file stopped_at pid
  [[ "$profile" =~ ^[12]$ ]] || return 1
  pid_file="$(webui_builder_discovery_pid_file "$profile")"
  state_file="$(webui_builder_discovery_state_runtime_file "$profile")"
  runtime_file="$(webui_builder_discovery_runtime_file "$profile")"
  stopped_at="$(date +%Y-%m-%dT%H:%M:%S%z)"
  : > "${runtime_file}.stop"
  if [ -s "$pid_file" ]; then
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  fi
  cat > "$state_file" <<EOF
{"running":false,"profile":$profile,"status":"stopped","message":"Discovery stopped","finished_at":"$stopped_at"}
EOF
  cat > "$runtime_file" <<EOF
{"running":false,"profile":$profile,"status":"stopped","message":"Discovery stopped","updated_at":"$stopped_at","phase":"","tier":"","checked":0,"total":0,"top_results":[]}
EOF
}

webui_write_builder_request() {
  local action="$1"
  local profile="${2:-}"
  local candidate="${3:-}"
  local file
  file="$(webui_builder_request_file "$action")"
  cat > "$file" <<EOF
{"action":"$(json_escape "$action")","profile":"$(json_escape "$profile")","candidate":"$(json_escape "$candidate")","timestamp":"$(date +%Y-%m-%dT%H:%M:%S%z)"}
EOF
  printf '%s\n' "$file"
}

webui_run_builder_discovery_start() {
  local script profile
  profile="${1:-}"
  script="$(webui_builder_discovery_start_script || true)"
  if [ -n "$script" ]; then
    Z2R_WEBUI_PROFILE="$profile" Z2R_PROFILE="$profile" "$script" "$profile"
    return $?
  fi
  return 1
}

webui_run_builder_apply_candidate() {
  local profile candidate script
  profile="${1:-}"
  candidate="${2:-}"
  script="$(webui_builder_apply_script || true)"
  if [ -n "$script" ]; then
    Z2R_WEBUI_PROFILE="$profile" \
    Z2R_PROFILE="$profile" \
    Z2R_WEBUI_CANDIDATE="$candidate" \
    Z2R_CANDIDATE="$candidate" \
    Z2R_CANDIDATE_ID="$candidate" \
    "$script" "$profile" "$candidate"
    return $?
  fi
  return 1
}

webui_builder_available_json() {
  if webui_builder_has_runtime; then
    printf 'true'
  else
    printf 'false'
  fi
}

webui_builder_catalog_source_json() {
  local file
  file="$(webui_builder_catalog_file || true)"
  printf '"%s"' "$(json_escape "$file")"
}

webui_builder_discovery_source_json() {
  local file
  file="$(webui_builder_discovery_file || true)"
  printf '"%s"' "$(json_escape "$file")"
}

webui_builder_active_source_json() {
  local file
  file="$(webui_builder_active_json_file || true)"
  printf '"%s"' "$(json_escape "$file")"
}

get_config_file() {
  if [ -f "$CONFIG_FILE" ]; then
    echo "$CONFIG_FILE"
  else
    echo "$CONFIG_DEFAULT_FILE"
  fi
}

set_zapret2_init() {
  if [ -f "$ZAPRET_ROOT/init.d/openwrt/zapret2" ]; then
    ZAPRET2_INIT="$ZAPRET_ROOT/init.d/openwrt/zapret2"
  else
    ZAPRET2_INIT="$ZAPRET_ROOT/init.d/sysv/zapret2"
  fi
}

hostlist_mode_text() {
  local cfg
  cfg="$(get_config_file)"
  if [ -f "$cfg" ]; then
    if grep -q '^MODE_FILTER=autohostlist' "$cfg"; then
      echo "авто"
      return
    fi
    if grep -q '^MODE_FILTER=hostlist' "$cfg"; then
      echo "по листам"
      return
    fi
  fi
  echo "неизвестно"
}

flowoffload_text() {
  local cfg
  cfg="$(get_config_file)"
  sed -n 's/^FLOWOFFLOAD=//p' "$cfg" 2>/dev/null | head -n1
}

fwtype_text() {
  local cfg
  cfg="$(get_config_file)"
  sed -n 's/^FWTYPE=//p' "$cfg" 2>/dev/null | head -n1
}

tls_blob_menu_text() {
  local cfg blob_file has_tls_maxru=0 has_tls_default=0
  cfg="$(get_config_file)"
  [ -f "$cfg" ] || { echo "неизвестно"; return; }

  if awk '
      /--filter-l7=tls/ || index($0, "--hostlist=/opt/zapret2/extra_strats/TCP_Discord.txt") {in_tls=1}
      in_tls && /^[[:space:]]*--new[[:space:]]*$/ {in_tls=0}
      in_tls && /--lua-desync=/ && /blob=maxru/ && $0 !~ /strategy=26/ {found=1}
      END {exit(found?0:1)}
    ' "$cfg"; then
    has_tls_maxru=1
  fi
  if awk '
      /--filter-l7=tls/ || index($0, "--hostlist=/opt/zapret2/extra_strats/TCP_Discord.txt") {in_tls=1}
      in_tls && /^[[:space:]]*--new[[:space:]]*$/ {in_tls=0}
      in_tls && /--lua-desync=/ && /blob=fake_default_tls/ && $0 !~ /strategy=26/ {found=1}
      END {exit(found?0:1)}
    ' "$cfg"; then
    has_tls_default=1
  fi

  if [ "$has_tls_default" -eq 1 ] && [ "$has_tls_maxru" -eq 0 ]; then
    echo "default"
    return
  fi
  if [ "$has_tls_default" -eq 1 ] && [ "$has_tls_maxru" -eq 1 ]; then
    echo "mixed"
    return
  fi

  blob_file="$(sed -n -E 's#.*--blob=maxru:@/opt/zapret2/files/fake/([^[:space:]]+).*#\1#p' "$cfg" | head -n1)"
  if [ -n "$blob_file" ]; then
    echo "$blob_file"
  else
    echo "неизвестно"
  fi
}

orchestra_status_text() {
  if [ -x "$ORCH_SCRIPT" ]; then
    if pgrep -f "$ORCH_SCRIPT run" >/dev/null 2>&1; then
      echo "Включен"
      return
    fi
  fi
  if [ -f "$ORCH_DIR/enabled" ]; then
    echo "Включен (не запущен)"
    return
  fi
  echo "Выключен"
}

zapret2_running() {
  pidof nfqws2 >/dev/null 2>&1
}

orch_locked_get() {
  local profile="$1"
  local proto="$2"
  [ -f "$ORCH_LOCK_FILE" ] || { echo "0"; return; }
  awk -v pr="$profile" -v p="$proto" 'BEGIN{FS="\t"}{
    if ($1==pr && $2==p && NF>=3) {print $3; found=1; exit}
    if ($1==pr && NF==2 && p=="tls") {print $2; found=1; exit}
  } END{if (!found) print 0}' "$ORCH_LOCK_FILE"
}

orch_locked_set() {
  local profile="$1"
  local proto="$2"
  local strategy="$3"
  local tmp="${ORCH_LOCK_FILE}.tmp"
  mkdir -p "$(dirname "$ORCH_LOCK_FILE")"
  touch "$ORCH_LOCK_FILE"
  awk -v pr="$profile" -v p="$proto" -v s="$strategy" 'BEGIN{FS=OFS="\t"}{
    if ($1==pr && (($2==p) || (NF==2 && p=="tls"))) {print pr,p,s; found=1; next}
    print
  } END{
    if (!found) print pr,p,s
  }' "$ORCH_LOCK_FILE" > "$tmp" && mv "$tmp" "$ORCH_LOCK_FILE"
}

orch_locked_clear() {
  local profile="$1"
  local proto="$2"
  local tmp="${ORCH_LOCK_FILE}.tmp"
  [ -f "$ORCH_LOCK_FILE" ] || return 0
  awk -v pr="$profile" -v p="$proto" 'BEGIN{FS=OFS="\t"}{
    if ($1==pr && (($2==p) || (NF==2 && p=="tls"))) next
    print
  }' "$ORCH_LOCK_FILE" > "$tmp" && mv "$tmp" "$ORCH_LOCK_FILE"
}

orch_max_strategy_for_profile() {
  local profile="$1"
  local cfg
  cfg="$(get_config_file)"
  [ -f "$cfg" ] || { echo "0"; return; }
  if [ "$profile" = "8" ]; then
    awk '
      BEGIN{inblk=0; max=0}
      /^[[:space:]]*#Z2R_FALLBACK_BEGIN/ {inblk=1; next}
      /^[[:space:]]*#Z2R_FALLBACK_END/ {inblk=0; exit}
      inblk {
        line=$0
        while (match(line, /strategy=[0-9]+/)) {
          num=substr(line, RSTART+9, RLENGTH-9)+0
          if (num>max) max=num
          line=substr(line, RSTART+RLENGTH)
        }
      }
      END{print max}
    ' "$cfg"
    return
  fi
  awk -v pid="$profile" '
    BEGIN{inopt=0; prof=1; max=0}
    /^NFQWS2_OPT="/ {inopt=1}
    inopt {
      if ($0 ~ /^--new/) {prof++}
      if (prof==pid) {
        line=$0
        while (match(line, /strategy=[0-9]+/)) {
          num=substr(line, RSTART+9, RLENGTH-9)+0
          if (num>max) max=num
          line=substr(line, RSTART+RLENGTH)
        }
      }
      if ($0 ~ /^"$/) {exit}
    }
    END{print max}
  ' "$cfg"
}

profile_proto() {
  case "$1" in
    1|2|3|4) echo "tls" ;;
    5|6) echo "udp" ;;
    *) echo "" ;;
  esac
}

profile_json() {
  local id="$1" label="$2" desc="$3" proto current max
  proto="$(profile_proto "$id")"
  current="$(orch_locked_get "$id" "$proto")"
  max="$(orch_max_strategy_for_profile "$id")"
  printf '{"profile":%s,"label":"%s","description":"%s","current_lock":"%s","max_strategy":%s}' \
    "$id" "$(json_escape "$label")" "$(json_escape "$desc")" "$(json_escape "$current")" "${max:-0}"
}

all_profiles_json() {
  printf '['
  profile_json 1 "YouTube TCP" "Основной TCP профиль для YouTube"
  printf ','
  profile_json 2 "Googlevideo" "Видео-домены YouTube"
  printf ','
  profile_json 3 "Blocked Sites" "Основные блокировки сайтов"
  printf ','
  profile_json 4 "Discord TCP" "TCP профиль Discord"
  printf ','
  profile_json 5 "YouTube QUIC" "UDP 443 для YouTube"
  printf ','
  profile_json 6 "Voice UDP" "Discord/STUN и голосовые сервисы"
  printf ']'
}

sync_orchestra() {
  if [ -x "$ORCH_SCRIPT" ]; then
    "$ORCH_SCRIPT" sync >/dev/null 2>&1 || true
  fi
}

restart_zapret2() {
  set_zapret2_init
  [ -f "$ZAPRET2_INIT" ] || return 1
  "$ZAPRET2_INIT" restart >/dev/null 2>&1
  if [ -x "$ORCH_SCRIPT" ] && [ -f "$ORCH_DIR/enabled" ]; then
    "$ORCH_SCRIPT" start >/dev/null 2>&1 || true
  fi
}

get_yt_cluster_domain() {
  local cluster_codename converted_name="" i=0 char idx b
  local letters_map_a="u z p k f a 5 0 v q l g b 6 1 w r m h c 7 2 x s n i d 8 3 y t o j e 9 4 -"
  local letters_map_b="0 1 2 3 4 5 6 7 8 9 a b c d e f g h i j k l m n o p q r s t u v w x y z -"

  cluster_codename="$(curl -s --max-time 2 "https://redirector.xn--ngstr-lra8j.com/report_mapping?di=no" | sed -n 's/.*=>[[:space:]]*\([^ (:)]*\).*/\1/p')"
  cluster_codename="$(curl -s --max-time 2 "https://redirector.xn--ngstr-lra8j.com/report_mapping?di=no" | sed -n 's/.*=>[[:space:]]*\([^ (:)]*\).*/\1/p')"
  [ -n "$cluster_codename" ] || { echo "rr1---sn-5goeenes.googlevideo.com"; return; }

  while [ $i -lt ${#cluster_codename} ]; do
    char="$(echo "$cluster_codename" | cut -c$((i+1)))"
    idx=1
    for a in $letters_map_a; do
      [ "$a" = "$char" ] && break
      idx=$((idx+1))
    done
    b="$(echo "$letters_map_b" | cut -d' ' -f "$idx")"
    converted_name="${converted_name}${b}"
    i=$((i+1))
  done
  echo "rr1---sn-${converted_name}.googlevideo.com"
}

check_one_target_json() {
  local label="$1"
  local target="$2"
  local tls12=0 tls13=0
  curl --tls-max 1.2 --max-time 1 -s -o /dev/null "$target" && tls12=1 || true
  curl --tlsv1.3 --max-time 1 -s -o /dev/null "$target" && tls13=1 || true
  printf '{"label":"%s","target":"%s","tls12":%s,"tls13":%s}' \
    "$(json_escape "$label")" "$(json_escape "$target")" "$tls12" "$tls13"
}

api_meta() {
  send_json "200 OK" "{\"profiles\":$(all_profiles_json)}"
}

api_status() {
  local running
  if zapret2_running; then running=true; else running=false; fi
  send_json "200 OK" "$(cat <<EOF
{"zapret2_running":$running,"orchestra_status":"$(json_escape "$(orchestra_status_text)")","hostlist_mode":"$(json_escape "$(hostlist_mode_text)")","fwtype":"$(json_escape "$(fwtype_text)")","flowoffload":"$(json_escape "$(flowoffload_text)")","tls_blob_mode":"$(json_escape "$(tls_blob_menu_text)")","profiles":$(all_profiles_json)}
EOF
)"
}

api_locks() {
  send_json "200 OK" "{\"profiles\":$(all_profiles_json)}"
}

api_set_lock() {
  parse_params
  [[ "${PARAM_PROFILE:-}" =~ ^[1-7]$ ]] || send_error "400 Bad Request" "Некорректный профиль"
  [[ "${PARAM_STRATEGY:-}" =~ ^[0-9]+$ ]] || send_error "400 Bad Request" "Некорректная стратегия"
  local max proto
  max="$(orch_max_strategy_for_profile "$PARAM_PROFILE")"
  [ "${PARAM_STRATEGY}" -ge 1 ] && [ "${PARAM_STRATEGY}" -le "${max:-0}" ] || send_error "400 Bad Request" "Стратегия вне диапазона"
  proto="$(profile_proto "$PARAM_PROFILE")"
  [ -n "$proto" ] || send_error "400 Bad Request" "Не удалось определить протокол профиля"
  orch_locked_set "$PARAM_PROFILE" "$proto" "$PARAM_STRATEGY"
  sync_orchestra
  send_json "200 OK" "{\"ok\":true}"
}

api_clear_lock() {
  parse_params
  [[ "${PARAM_PROFILE:-}" =~ ^[1-7]$ ]] || send_error "400 Bad Request" "Некорректный профиль"
  local proto
  proto="$(profile_proto "$PARAM_PROFILE")"
  [ -n "$proto" ] || send_error "400 Bad Request" "Не удалось определить протокол профиля"
  orch_locked_clear "$PARAM_PROFILE" "$proto"
  sync_orchestra
  send_json "200 OK" "{\"ok\":true}"
}

api_restart() {
  restart_zapret2 || send_error "500 Internal Server Error" "Не удалось перезапустить zapret2"
  send_json "200 OK" "{\"ok\":true}"
}

api_check() {
  local gv
  gv="$(get_yt_cluster_domain)"
  send_json "200 OK" "{\"results\":[
$(check_one_target_json "YouTube" "https://www.youtube.com/")
,$(check_one_target_json "Googlevideo" "https://${gv}")
,$(check_one_target_json "Blocked Sites" "https://meduza.io")
,$(check_one_target_json "Instagram" "https://www.instagram.com/")
]}"
}

api_builder_meta() {
  local profiles_json='[]'
  if type builder_profiles_json >/dev/null 2>&1; then
    profiles_json="$(builder_profiles_json)"
  fi
  send_json "200 OK" "$(cat <<EOF
{"available":$(webui_builder_available_json),"profiles":$profiles_json,"catalog_source":$(webui_builder_catalog_source_json),"catalog":$(webui_builder_catalog_json),"discovery_source":$(webui_builder_discovery_source_json),"discovery_state":$(webui_builder_discovery_state_json),"active_source":$(webui_builder_active_source_json),"active_generated":$(webui_builder_active_json)}
EOF
)"
}

api_builder_candidates() {
  parse_params
  [[ "${PARAM_PROFILE:-}" =~ ^[12]$ ]] || send_error "400 Bad Request" "Некорректный builder-профиль"
  if type builder_candidates_json >/dev/null 2>&1; then
    local last_session='{"profile":0,"session_id":"","results":[]}'
    if type builder_last_session_json >/dev/null 2>&1; then
      last_session="$(builder_last_session_json "$PARAM_PROFILE")"
    else
      last_session="{\"profile\":${PARAM_PROFILE},\"session_id\":\"\",\"results\":[]}"
    fi
    send_json "200 OK" "{\"profile\":${PARAM_PROFILE},\"candidates\":$(builder_candidates_json "$PARAM_PROFILE"),\"last_session\":${last_session}}"
    return
  fi
  send_json "200 OK" "{\"profile\":${PARAM_PROFILE},\"candidates\":[],\"last_session\":{\"profile\":${PARAM_PROFILE},\"session_id\":\"\",\"results\":[]}}"
}

api_discovery_results() {
  parse_params
  send_json "200 OK" "$(cat <<EOF
{"available":$(webui_builder_available_json),"source":$(webui_builder_discovery_source_json),"discovery_state":$(webui_builder_discovery_state_json),"results":$(webui_builder_discovery_json)}
EOF
)"
}

api_active_generated() {
  send_json "200 OK" "$(cat <<EOF
{"available":$(webui_builder_available_json),"source":$(webui_builder_active_source_json),"active_generated":$(webui_builder_active_json)}
EOF
)"
}

api_discovery_start() {
  parse_params
  local profile request_file
  profile="${PARAM_PROFILE:-}"
  if type builder_run_discovery >/dev/null 2>&1; then
    [[ "${profile:-}" =~ ^[12]$ ]] || send_error "400 Bad Request" "Некорректный builder-профиль"
    webui_start_builder_discovery_async "$profile" || send_error "500 Internal Server Error" "Не удалось запустить discovery"
    send_json "200 OK" "{\"ok\":true,\"started\":true,\"queued\":true,\"profile\":${profile},\"state\":{\"running\":true,\"profile\":${profile}}}"
    return
  fi
  if webui_run_builder_discovery_start "$profile" >/dev/null 2>&1; then
    send_json "200 OK" "{\"ok\":true,\"started\":true,\"queued\":false}"
    return
  fi
  request_file="$(webui_write_builder_request "discovery-start" "$profile" "")"
  send_json "200 OK" "{\"ok\":true,\"started\":false,\"queued\":true,\"request_file\":\"$(json_escape "$request_file")\"}"
}

api_apply_candidate() {
  parse_params
  local profile candidate request_file
  profile="${PARAM_PROFILE:-}"
  candidate="${PARAM_CANDIDATE_ID:-${PARAM_CANDIDATE_KEY:-${PARAM_CANDIDATE:-${PARAM_GENERATED_ID:-}}}}"
  [ -n "$candidate" ] || send_error "400 Bad Request" "Candidate is required"
  if type builder_apply_candidate >/dev/null 2>&1; then
    local strategy_num
    [[ "${profile:-}" =~ ^[12]$ ]] || send_error "400 Bad Request" "Некорректный builder-профиль"
    strategy_num="$(builder_apply_candidate "$profile" "$candidate" "persist")" || send_error "500 Internal Server Error" "Не удалось применить candidate"
    send_json "200 OK" "{\"ok\":true,\"applied\":true,\"queued\":false,\"strategy\":\"$(json_escape "$strategy_num")\",\"profiles\":$(all_profiles_json),\"candidates\":$(builder_candidates_json "$profile")}"
    return
  fi
  if webui_run_builder_apply_candidate "$profile" "$candidate" >/dev/null 2>&1; then
    send_json "200 OK" "{\"ok\":true,\"applied\":true,\"queued\":false}"
    return
  fi
  request_file="$(webui_write_builder_request "apply-candidate" "$profile" "$candidate")"
  send_json "200 OK" "{\"ok\":true,\"applied\":false,\"queued\":true,\"request_file\":\"$(json_escape "$request_file")\"}"
}

api_builder_candidates_cached() {
  parse_params
  [[ "${PARAM_PROFILE:-}" =~ ^[12]$ ]] || send_error "400 Bad Request" "Invalid builder profile"
  local cache_file
  cache_file="$(webui_builder_candidates_cache_file "$PARAM_PROFILE")"
  if [ -s "$cache_file" ]; then
    send_json "200 OK" "$(cat "$cache_file")"
    return
  fi
  api_builder_candidates
}

api_discovery_stop() {
  parse_params
  local profile
  profile="${PARAM_PROFILE:-}"
  [[ "${profile:-}" =~ ^[12]$ ]] || send_error "400 Bad Request" "Invalid builder profile"
  webui_stop_builder_discovery "$profile" || send_error "500 Internal Server Error" "Unable to stop discovery"
  send_json "200 OK" "{\"ok\":true,\"stopped\":true,\"profile\":${profile}}"
}
