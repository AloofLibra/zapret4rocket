#!/bin/sh

ORCH_DIR="${ORCH_DIR:-/opt/zapret2/extra_strats/cache/orchestra}"
ORCH_SCRIPT="${ORCH_SCRIPT:-$ORCH_DIR/orchestrator.sh}"
ORCH_ENABLED_FLAG="${ORCH_ENABLED_FLAG:-$ORCH_DIR/enabled}"
ORCH_LOCK_FILE="${ORCH_LOCK_FILE:-$ORCH_DIR/locked.tsv}"

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

orchestra_status_text() {
  if [ -x "$ORCH_SCRIPT" ]; then
    if command -v pgrep >/dev/null 2>&1; then
      if pgrep -f "$ORCH_SCRIPT run" >/dev/null 2>&1; then
        echo "Включен"
        return
      fi
    elif ps w | grep -F "$ORCH_SCRIPT run" | grep -v grep >/dev/null 2>&1; then
      echo "Включен"
      return
    fi
  fi
  if [ -f "$ORCH_ENABLED_FLAG" ]; then
    echo "Включен (не запущен)"
    return
  fi
  echo "Выключен"
}

zapret2_running() {
  pidof nfqws2 >/dev/null 2>&1
}
