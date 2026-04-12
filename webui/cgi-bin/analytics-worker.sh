#!/bin/bash
. /opt/zapret2/webui/cgi-bin/_lib.sh

job_id="${1:-}"
mode="${2:-}"
profile="${3:-}"
target="${4:-}"
use_last="${5:-0}"

[ -n "$job_id" ] || exit 1
job_file="$(analytics_job_file "$job_id")"
ANALYTICS_PROGRESS_FILE="$job_file"
export ANALYTICS_PROGRESS_FILE

write_error() {
  cat > "$job_file" <<EOF
{"job_id":"$job_id","status":"error","error":"$(json_escape "$1")"}
EOF
  exit 1
}

report_file="$(analytics_run_report "$mode" "$profile" "$target" "" "$use_last")" || write_error "Не удалось собрать аналитический отчёт"
[ -f "$report_file" ] || write_error "Файл отчёта не был создан"

cat > "$job_file" <<EOF
{"job_id":"$job_id","status":"completed","report":$(cat "$report_file")}
EOF
