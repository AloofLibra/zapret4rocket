#!/bin/bash
. /opt/zapret2/webui/cgi-bin/_lib.sh

job_id="${1:-}"
mode="${2:-}"
profile="${3:-}"
target="${4:-}"

[ -n "$job_id" ] || exit 1
job_file="$(blockcheck_job_file "$job_id")"
BLOCKCHECK_PROGRESS_FILE="$job_file"
export BLOCKCHECK_PROGRESS_FILE

write_error() {
  cat > "$job_file" <<EOF
{"job_id":"$job_id","status":"error","error":"$(json_escape "$1")"}
EOF
  exit 1
}

case "$mode" in
  profile)
    blockcheck_run_profile_scan "$profile" || write_error "Не удалось выполнить проверку профиля"
    ;;
  custom)
    blockcheck_run_custom_scan "$target" "$profile" || write_error "Не удалось выполнить кастомную проверку"
    ;;
  *)
    write_error "Неизвестный режим"
    ;;
esac

cat > "$job_file" <<EOF
{"job_id":"$job_id","status":"completed","results":$(blockcheck_rows_json "$BLOCKCHECK_LAST_RUN_FILE"),"recommendation":$(blockcheck_last_json)}
EOF
