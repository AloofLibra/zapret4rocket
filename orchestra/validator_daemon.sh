#!/bin/bash
set -eu

BASE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")"/.. && pwd)"
POLICY_STORE_MODULE="${POLICY_STORE_MODULE:-$BASE_DIR/lib/policy_store.sh}"
VALIDATOR_MODULE="${VALIDATOR_MODULE:-$BASE_DIR/lib/strategy_validator.sh}"

[ -f "$POLICY_STORE_MODULE" ] && . "$POLICY_STORE_MODULE"
[ -f "$VALIDATOR_MODULE" ] && . "$VALIDATOR_MODULE"

validator_domain_file_name() {
  printf '%s' "$1" | tr 'A-Z' 'a-z' | tr '/:\\ ' '_'
}

validator_write_json_atomic() {
  dst="$1"
  body="$2"
  tmp="$(mktemp "${TMPDIR:-/tmp}/validator-json.XXXXXX")"
  printf '%s\n' "$body" > "$tmp"
  policy_write_from_file "$dst" "$tmp"
  rm -f "$tmp"
}

validator_catalog_family_id() {
  profile="$1"
  candidate_id="$2"
  lua_file="$policy_catalog_profiles_root/$profile.lua"
  if [ -f "$lua_file" ]; then
    awk -v cid="$candidate_id" '
      index($0, "[\"" cid "\"]") { in_block=1; next }
      in_block && /family_id = "/ {
        line=$0
        sub(/^.*family_id = "/, "", line)
        sub(/".*$/, "", line)
        print line
        exit
      }
      in_block && /^    },?$/ { in_block=0 }
    ' "$lua_file"
    return
  fi
  printf '%s\n' ""
}

validator_claim_next_job() {
  policy_claim_job
}

validator_execute_job() {
  job_path="$1"
  validator_validate_candidate "$job_path"
}

validator_update_states_from_result() {
  result_json="$1"
  job_json="$2"
  profile="$(validator_json_get_number "$result_json" "profile" 2>/dev/null || echo 0)"
  candidate_id="$(validator_json_get_string "$result_json" "candidate_id" 2>/dev/null || echo "")"
  verdict="$(validator_json_get_string "$result_json" "verdict" 2>/dev/null || echo inconclusive)"
  score="$(validator_json_get_number "$result_json" "score" 2>/dev/null || echo 0)"
  finished_at="$(validator_json_get_string "$result_json" "finished_at" 2>/dev/null || echo "")"
  host="$(validator_json_get_string "$result_json" "host" 2>/dev/null || echo "")"
  profile_state_file="$(mktemp "${TMPDIR:-/tmp}/profile-state.XXXXXX")"

  active_family_id="$(validator_catalog_family_id "$profile" "$candidate_id")"
  confidence="0.20"
  status="testing"
  case "$verdict" in
    valid) status="known_good"; confidence="0.95" ;;
    unstable) status="unstable"; confidence="0.50" ;;
    dns_poisoned|transport_blocked|invalid) status="suspect"; confidence="0.10" ;;
    inconclusive) status="testing"; confidence="0.30" ;;
  esac

  cat > "$profile_state_file" <<EOF
{
  "profile": $profile,
  "mode": "manual_fixed",
  "active_candidate_id": "$(validator_json_escape "$candidate_id")",
  "active_family_id": "$(validator_json_escape "$active_family_id")",
  "status": "$(validator_json_escape "$status")",
  "confidence": $confidence,
  "pending_job_id": "",
  "fallback_chain": [],
  "last_validated_at": "$(validator_json_escape "$finished_at")",
  "source": "validator_daemon"
}
EOF
  policy_write_profile_state "$profile" "$profile_state_file"
  rm -f "$profile_state_file"

  if [ -n "$host" ]; then
    host_key="$(validator_domain_file_name "$host")"
    domain_tmp="$(mktemp "${TMPDIR:-/tmp}/domain-state.XXXXXX")"
    last_success=""
    last_failure=""
    [ "$verdict" = "valid" ] && last_success="$finished_at"
    [ "$verdict" != "valid" ] && last_failure="$finished_at"
    cat > "$domain_tmp" <<EOF
{
  "host": "$(validator_json_escape "$host")",
  "group_key": "profile_${profile}",
  "profile": $profile,
  "active_candidate_id": "$(validator_json_escape "$candidate_id")",
  "status": "$(validator_json_escape "$status")",
  "confidence": $confidence,
  "blocked_candidates": [],
  "unstable_candidates": [],
  "last_success_at": "$(validator_json_escape "$last_success")",
  "last_failure_at": "$(validator_json_escape "$last_failure")"
}
EOF
    policy_write_domain_state "$host_key" "$domain_tmp"
    rm -f "$domain_tmp"
  fi

  policy_rebuild_runtime_snapshot >/dev/null 2>&1 || true
  policy_log_event "validator_result" "$(cat "$result_json")" >/dev/null 2>&1 || true
}

validator_apply_result() {
  job_path="$1"
  result_json="$2"
  validator_update_states_from_result "$result_json" "$job_path"
  policy_finish_job "$job_path" "$result_json"
}

validator_daemon_run() {
  mode="${1:-once}"
  policy_init_dirs
  while :; do
    job_path="$(validator_claim_next_job 2>/dev/null || true)"
    if [ -z "${job_path:-}" ]; then
      [ "$mode" = "loop" ] || return 0
      sleep 2
      continue
    fi
    if result_json="$(validator_execute_job "$job_path" 2>/dev/null)"; then
      validator_apply_result "$job_path" "$result_json"
    else
      failed_tmp="$(mktemp "${TMPDIR:-/tmp}/validator-failed.XXXXXX")"
      cat > "$failed_tmp" <<EOF
{
  "job_id": "$(validator_json_get_string "$job_path" "job_id" 2>/dev/null || echo "")",
  "verdict": "inconclusive",
  "error": "validator_execute_job_failed",
  "finished_at": "$(validator_now_iso)"
}
EOF
      policy_fail_job "$job_path" "$failed_tmp"
      rm -f "$failed_tmp"
    fi
    [ "$mode" = "loop" ] || return 0
  done
}

case "${1:-}" in
  run) validator_daemon_run "${2:-loop}" ;;
  once|"") validator_daemon_run once ;;
  *) echo "usage: $0 [run [loop|once]]" >&2; exit 1 ;;
esac
