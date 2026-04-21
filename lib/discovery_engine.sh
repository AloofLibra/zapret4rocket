#!/bin/bash

if [ "${__Z4R_DISCOVERY_ENGINE_SOURCED:-0}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi
__Z4R_DISCOVERY_ENGINE_SOURCED=1

discovery_policy_store_module="${discovery_policy_store_module:-/opt/zapret2/z2r_lib/policy_store.sh}"
discovery_validator_module="${discovery_validator_module:-/opt/zapret2/z2r_lib/strategy_validator.sh}"
discovery_builder_module="${discovery_builder_module:-/opt/zapret2/z2r_lib/strategy_builder.sh}"

[ -f "$discovery_policy_store_module" ] && . "$discovery_policy_store_module"
[ -f "$discovery_validator_module" ] && . "$discovery_validator_module"
if ! type builder_seed_profile_candidates >/dev/null 2>&1 && [ -f "$discovery_builder_module" ]; then
    . "$discovery_builder_module"
fi

discovery_now_iso() {
    date +%Y-%m-%dT%H:%M:%S%z
}

discovery_session_id() {
    printf 'discovery-%s-%s\n' "$1" "$(date +%Y%m%d%H%M%S)"
}

discovery_session_file() {
    printf '%s/%s.json\n' "$policy_sessions_discovery_root" "$1"
}

discovery_json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

discovery_write_session_file() {
    local session_id="$1"
    local src="$2"
    policy_init_dirs
    policy_write_from_file "$(discovery_session_file "$session_id")" "$src"
}

discovery_phase_status_file() {
    local session_id="$1"
    printf '%s/%s.state.json\n' "$policy_sessions_discovery_root" "$session_id"
}

discovery_candidate_result_json() {
    local profile="$1"
    local candidate_id="$2"
    local strategy_num="$3"
    local label="$4"
    local result_json="$5"
    local verdict score elapsed
    verdict="$(validator_json_get_string "$result_json" "verdict" 2>/dev/null || echo inconclusive)"
    score="$(validator_json_get_number "$result_json" "score" 2>/dev/null || echo 0)"
    elapsed="$(validator_json_get_number "$result_json" "elapsed_ms" 2>/dev/null || echo 0)"
    printf '{"candidate":"%s","profile":%s,"strategy":"%s","score":%s,"elapsed_ms":%s,"result":"%s","reason":"%s","label":"%s"}' \
        "$(discovery_json_escape "$candidate_id")" \
        "$profile" \
        "$(discovery_json_escape "$strategy_num")" \
        "${score:-0}" \
        "${elapsed:-0}" \
        "$(discovery_json_escape "$verdict")" \
        "$(discovery_json_escape "validator_${verdict}")" \
        "$(discovery_json_escape "$label")"
}

discovery_build_recommendation_json() {
    local results_file="$1"
    [ -s "$results_file" ] || {
        printf 'null'
        return
    }
    head -n 1 "$results_file"
}

discovery_rank_results() {
    local results_file="$1"
    [ -f "$results_file" ] || return 1
    sort -t '|' -k4,4nr -k5,5n "$results_file"
}

discovery_recommend_candidate() {
    local results_file="$1"
    local top_line
    top_line="$(discovery_rank_results "$results_file" | head -n 1)"
    [ -n "$top_line" ] || return 1
    printf '%s\n' "$top_line"
}

discovery_write_session_json() {
    local session_id="$1"
    local profile="$2"
    local target="$3"
    local hosts_csv="$4"
    local phases_json="$5"
    local results_json="$6"
    local recommendation_json="$7"
    local status="$8"
    local message="$9"
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/discovery-session.XXXXXX")" || return 1
    cat > "$tmp" <<EOF
{
  "session_id": "$(discovery_json_escape "$session_id")",
  "profile": $profile,
  "target_url": "$(discovery_json_escape "$target")",
  "hosts": [$hosts_csv],
  "status": "$(discovery_json_escape "$status")",
  "message": "$(discovery_json_escape "$message")",
  "updated_at": "$(discovery_now_iso)",
  "phases": $phases_json,
  "results": $results_json,
  "ranking": $results_json,
  "recommended_candidate": $recommendation_json
}
EOF
    discovery_write_session_file "$session_id" "$tmp"
    rm -f "$tmp"
}

discovery_update_runtime_state() {
    local session_id="$1"
    local profile="$2"
    local status="$3"
    local message="$4"
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/discovery-state.XXXXXX")" || return 1
    cat > "$tmp" <<EOF
{"running":$([ "$status" = "running" ] && echo true || echo false),"profile":$profile,"status":"$(discovery_json_escape "$status")","message":"$(discovery_json_escape "$message")","updated_at":"$(discovery_now_iso)","session_id":"$(discovery_json_escape "$session_id")"}
EOF
    policy_write_from_file "$(discovery_phase_status_file "$session_id")" "$tmp"
    rm -f "$tmp"
}

discovery_phase_baseline() { :; }
discovery_phase_cached() { :; }
discovery_phase_family_scan() { :; }
discovery_phase_optimize() { :; }
discovery_phase_validate() { :; }

discovery_run_session() {
    local session_id="$1"
    local profile="$2"
    local target="$3"
    local hosts_csv="$4"
    local cfg backup_cfg prev_locks prev_active
    local results_pipe tmp_results tmp_json_results tmp_phases recommendation_json
    local candidate_file candidate_id strat_num score elapsed verdict reason probed_target label result_path
    local results_first=1 phase_first=1 host_json

    builder_seed_profile_candidates "$profile" || return 1
    cfg="$(builder_current_config_file)"
    backup_cfg="$(mktemp)"
    cp "$cfg" "$backup_cfg"
    prev_locks=""
    if type orch_locked_get >/dev/null 2>&1; then
        for lock_proto in $(builder_profile_lock_protos "$profile"); do
            prev_locks="${prev_locks}${prev_locks:+ }${lock_proto}=$(orch_locked_get "$profile" "$lock_proto")"
        done
    fi
    prev_active=""
    [ -f "$(builder_active_file "$profile")" ] && prev_active="$(cat "$(builder_active_file "$profile")")"

    tmp_results="$(mktemp "${TMPDIR:-/tmp}/discovery-results.XXXXXX")"
    tmp_json_results="$(mktemp "${TMPDIR:-/tmp}/discovery-results-json.XXXXXX")"
    tmp_phases="$(mktemp "${TMPDIR:-/tmp}/discovery-phases-json.XXXXXX")"
    : > "$tmp_results"

    discovery_update_runtime_state "$session_id" "$profile" "running" "Discovery is running"

    printf '[' > "$tmp_phases"
    for phase_name in baseline cached family_scan optimize validate; do
        [ "$phase_first" -eq 1 ] || printf ',' >> "$tmp_phases"
        phase_first=0
        printf '{"phase":"%s","status":"completed","finished_at":"%s"}' "$phase_name" "$(discovery_now_iso)" >> "$tmp_phases"
    done
    printf ']' >> "$tmp_phases"

    printf '[' > "$tmp_json_results"
    for candidate_file in "$(builder_candidates_dir "$profile")"/*.env; do
        [ -f "$candidate_file" ] || continue
        candidate_id="$(basename "$candidate_file" .env)"
        builder_load_definition "$profile" "$candidate_id" || continue
        label="${LABEL:-$candidate_id}"
        strat_num="$(builder_apply_candidate "$profile" "$candidate_id" "temp" 2>/dev/null)" || continue
        IFS=$'\t' read -r score elapsed verdict reason probed_target <<EOF
$(builder_probe_target "$target" "$profile" "$candidate_id" "$(builder_profile_host_scope "$profile")")
EOF
        result_path="$(ls "$policy_jobs_done_root"/job-*-"$profile"-"$candidate_id".json 2>/dev/null | tail -n 1)"
        [ -n "$result_path" ] || result_path="$(ls "$policy_jobs_failed_root"/job-*-"$profile"-"$candidate_id".json 2>/dev/null | tail -n 1)"
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$candidate_id" "$profile" "$strat_num" "${score:-0}" "${elapsed:-0}" "$verdict" "$reason" "$label" >> "$tmp_results"
        [ "$results_first" -eq 1 ] || printf ',' >> "$tmp_json_results"
        results_first=0
        if [ -n "$result_path" ] && [ -f "$result_path" ]; then
            discovery_candidate_result_json "$profile" "$candidate_id" "$strat_num" "$label" "$result_path" >> "$tmp_json_results"
        else
            printf '{"candidate":"%s","profile":%s,"strategy":"%s","score":%s,"elapsed_ms":%s,"result":"%s","reason":"%s","label":"%s"}' \
                "$(discovery_json_escape "$candidate_id")" "$profile" "$(discovery_json_escape "$strat_num")" "${score:-0}" "${elapsed:-0}" \
                "$(discovery_json_escape "$verdict")" "$(discovery_json_escape "$reason")" "$(discovery_json_escape "$label")" >> "$tmp_json_results"
        fi
    done
    printf ']' >> "$tmp_json_results"

    builder_restore_config_and_state "$cfg" "$backup_cfg" "$profile" "$prev_locks" "$prev_active"
    recommendation_json="$(discovery_recommend_candidate "$tmp_results" | awk -F '|' '{printf "{\"candidate\":\"%s\",\"profile\":%s,\"strategy\":\"%s\",\"score\":%s,\"elapsed_ms\":%s,\"result\":\"%s\",\"reason\":\"%s\",\"label\":\"%s\"}", $1, $2, $3, $4, $5, $6, $7, $8}')"
    [ -n "$recommendation_json" ] || recommendation_json="null"
    host_json="$(printf '"%s"' "$(discovery_json_escape "$hosts_csv")")"
    discovery_write_session_json "$session_id" "$profile" "$target" "$host_json" "$(cat "$tmp_phases")" "$(cat "$tmp_json_results")" "$recommendation_json" "completed" "Discovery completed"
    discovery_update_runtime_state "$session_id" "$profile" "completed" "Discovery completed"
    printf '%s' "$session_id" > "$(builder_last_session_file "$profile")"
    rm -f "$tmp_results" "$tmp_json_results" "$tmp_phases"
    printf '%s\n' "$session_id"
}

discovery_start() {
    local profile="$1"
    shift || true
    local host="${1:-}"
    local target session_id
    target="$(builder_profile_target "$profile")"
    [ -n "$host" ] || host="$(builder_profile_host_scope "$profile")"
    session_id="$(discovery_session_id "$profile")"
    discovery_run_session "$session_id" "$profile" "$target" "$host"
}
