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

discovery_runtime_progress_file() {
    local profile="$1"
    if type builder_webui_discovery_runtime_file >/dev/null 2>&1; then
        builder_webui_discovery_runtime_file "$profile"
    else
        printf '/opt/zapret2/extra_strats/cache/webui-builder/discovery-%s.runtime.json\n' "$profile"
    fi
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

discovery_recommendation_json_from_line() {
    local line="$1"
    local candidate_id profile strategy score elapsed verdict reason label family phase dns_state baseline_state tls12_ok tls13_ok long_get_ok failure_class confidence transport_ok
    IFS='|' read -r candidate_id profile strategy score elapsed verdict reason label family phase dns_state baseline_state tls12_ok tls13_ok long_get_ok failure_class confidence transport_ok <<EOF
$line
EOF
    [ -n "$candidate_id" ] || {
        printf 'null'
        return 1
    }
    printf '{"candidate":"%s","profile":%s,"strategy":"%s","score":%s,"elapsed_ms":%s,"result":"%s","reason":"%s","label":"%s","family":"%s","dns_state":"%s","baseline_state":"%s","tls12_ok":%s,"tls13_ok":%s,"long_get_ok":%s,"failure_class":"%s","confidence":%s,"transport_ok":%s}' \
        "$(discovery_json_escape "$candidate_id")" \
        "${profile:-0}" \
        "$(discovery_json_escape "$strategy")" \
        "${score:-0}" \
        "${elapsed:-0}" \
        "$(discovery_json_escape "$verdict")" \
        "$(discovery_json_escape "$reason")" \
        "$(discovery_json_escape "$label")" \
        "$(discovery_json_escape "$family")" \
        "$(discovery_json_escape "${dns_state:-unknown}")" \
        "$(discovery_json_escape "${baseline_state:-unknown}")" \
        "${tls12_ok:-0}" \
        "${tls13_ok:-0}" \
        "${long_get_ok:-0}" \
        "$(discovery_json_escape "${failure_class:-inconclusive}")" \
        "${confidence:-0}" \
        "${transport_ok:-false}"
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
    local tmp runtime_file
    tmp="$(mktemp "${TMPDIR:-/tmp}/discovery-state.XXXXXX")" || return 1
    cat > "$tmp" <<EOF
{"running":$([ "$status" = "running" ] && echo true || echo false),"profile":$profile,"status":"$(discovery_json_escape "$status")","message":"$(discovery_json_escape "$message")","updated_at":"$(discovery_now_iso)","session_id":"$(discovery_json_escape "$session_id")"}
EOF
    policy_write_from_file "$(discovery_phase_status_file "$session_id")" "$tmp"
    runtime_file="$(discovery_runtime_progress_file "$profile")"
    mkdir -p "$(dirname "$runtime_file")"
    cp "$tmp" "$runtime_file" 2>/dev/null || cat "$tmp" > "$runtime_file"
    rm -f "$tmp"
}

discovery_update_runtime_progress() {
    local session_id="$1"
    local profile="$2"
    local status="$3"
    local message="$4"
    local phase="$5"
    local tier="$6"
    local checked="$7"
    local total="$8"
    local results_file="$9"
    local tmp runtime_file top_json
    tmp="$(mktemp "${TMPDIR:-/tmp}/discovery-progress.XXXXXX")" || return 1
    top_json='[]'
    if [ -f "$results_file" ] && [ -s "$results_file" ]; then
        top_json="$(discovery_rank_results "$results_file" | head -n 3 | while IFS='|' read -r candidate_id _profile strategy score elapsed verdict reason label family _phase dns_state baseline_state tls12_ok tls13_ok long_get_ok failure_class confidence transport_ok; do
            builder_load_definition "$profile" "$candidate_id" >/dev/null 2>&1 || true
            discovery_result_json_line "$profile" "$candidate_id" "$strategy" "$label" "$verdict" "$score" "$elapsed" "$reason" "$dns_state" "$baseline_state" "$tls12_ok" "$tls13_ok" "$long_get_ok" "$failure_class" "$confidence" "$transport_ok"
        done | awk 'BEGIN{print "["} {if (NR>1) printf ","; printf "%s",$0} END{print "]"}')"
    fi
    cat > "$tmp" <<EOF
{"running":$([ "$status" = "running" ] && echo true || echo false),"profile":$profile,"status":"$(discovery_json_escape "$status")","message":"$(discovery_json_escape "$message")","updated_at":"$(discovery_now_iso)","session_id":"$(discovery_json_escape "$session_id")","phase":"$(discovery_json_escape "$phase")","tier":"$(discovery_json_escape "$tier")","checked":${checked:-0},"total":${total:-0},"top_results":$top_json}
EOF
    runtime_file="$(discovery_runtime_progress_file "$profile")"
    mkdir -p "$(dirname "$runtime_file")"
    mv "$tmp" "$runtime_file"
}

discovery_cancel_requested() {
    local profile="$1"
    local runtime_file
    runtime_file="$(discovery_runtime_progress_file "$profile")"
    [ -f "${runtime_file}.stop" ]
}

discovery_finalize_stopped_session() {
    local session_id="$1"
    local profile="$2"
    local target="$3"
    local host_json="$4"
    local cfg="$5"
    local backup_cfg="$6"
    local prev_locks="$7"
    local prev_active="$8"
    local tmp_phases="$9"
    local tmp_json_results="${10}"
    local tmp_results="${11}"
    printf ']' >> "$tmp_json_results"
    printf ']' >> "$tmp_phases"
    builder_restore_config_and_state "$cfg" "$backup_cfg" "$profile" "$prev_locks" "$prev_active"
    discovery_write_session_json "$session_id" "$profile" "$target" "$host_json" "$(cat "$tmp_phases")" "$(cat "$tmp_json_results")" "null" "stopped" "Discovery stopped"
    discovery_update_runtime_progress "$session_id" "$profile" "stopped" "Discovery stopped" "" "" 0 0 "$tmp_results"
    discovery_update_runtime_state "$session_id" "$profile" "stopped" "Discovery stopped"
    printf '%s' "$session_id" > "$(builder_last_session_file "$profile")"
    rm -f "$(discovery_runtime_progress_file "$profile").stop"
    if type builder_sync_webui_profile_cache >/dev/null 2>&1; then
        builder_sync_webui_profile_cache "$profile"
    fi
    rm -f "$tmp_results" "$tmp_json_results" "$tmp_phases"
    printf '%s\n' "$session_id"
}

discovery_phase_baseline() { :; }
discovery_phase_cached() { :; }
discovery_phase_family_scan() { :; }
discovery_phase_optimize() { :; }
discovery_phase_validate() { :; }

discovery_family_seen_success() {
    local results_file="$1"
    local family="$2"
    [ -f "$results_file" ] || return 1
    awk -F '|' -v family="$family" '
        ($6 == "valid" || $6 == "unstable") && $9 == family { found = 1 }
        END { exit found ? 0 : 1 }
    ' "$results_file"
}

discovery_candidate_should_run() {
    local profile="$1"
    local candidate_id="$2"
    local results_file="$3"
    local family
    builder_load_definition "$profile" "$candidate_id" || return 1
    family="${FAMILY:-}"
    case "$family" in
        fake_multisplit)
            discovery_family_seen_success "$results_file" "multisplit" && return 1
            ;;
        multisplit_fakeddisorder|fake_fakeddisorder)
            discovery_family_seen_success "$results_file" "fakeddisorder" && return 1
            ;;
        multisplit_fakedsplit|fake_fakedsplit)
            discovery_family_seen_success "$results_file" "fakedsplit" && return 1
            ;;
        fake_hostfakesplit)
            discovery_family_seen_success "$results_file" "hostfakesplit" && return 1
            ;;
        multisplit_multidisorder)
            discovery_family_seen_success "$results_file" "multidisorder" && return 1
            ;;
    esac
    return 0
}

discovery_candidate_tier() {
    local profile="$1"
    local candidate_id="$2"
    builder_load_definition "$profile" "$candidate_id" || return 1
    case ",${RISK_FLAGS:-}," in
        *,seqovl,*|*,md5,*)
            printf 'expensive_edge\n'
            return 0
            ;;
    esac
    case "${FAMILY:-}" in
        tcpseg|oob|syndata)
            printf 'cheap_basics\n'
            ;;
        multisplit|multidisorder|fakeddisorder|fakedsplit)
            printf 'split_core\n'
            ;;
        fake|hostfakesplit)
            printf 'fake_core\n'
            ;;
        fake_multisplit|multisplit_fakeddisorder|multisplit_fakedsplit|fake_fakeddisorder|fake_fakedsplit|fake_hostfakesplit)
            printf 'combos\n'
            ;;
        seqovl|multisplit_multidisorder)
            printf 'expensive_edge\n'
            ;;
        *)
            printf 'fake_core\n'
            ;;
    esac
}

discovery_success_count_for_tiers() {
    local profile="$1"
    local results_file="$2"
    local tiers_csv="$3"
    local candidate_id verdict tier count=0
    [ -f "$results_file" ] || {
        printf '0\n'
        return 0
    }
    while IFS='|' read -r candidate_id _profile _strategy _score _elapsed verdict _reason _label _family _phase _rest; do
        case "$verdict" in
            valid|unstable) ;;
            *) continue ;;
        esac
        tier="$(discovery_candidate_tier "$profile" "$candidate_id" 2>/dev/null || true)"
        case ",$tiers_csv," in
            *,"$tier",*) count=$((count + 1)) ;;
        esac
    done < "$results_file"
    printf '%s\n' "$count"
}

discovery_best_confidence_for_tiers() {
    local profile="$1"
    local results_file="$2"
    local tiers_csv="$3"
    local candidate_id verdict confidence tier best=0
    [ -f "$results_file" ] || {
        printf '0\n'
        return 0
    }
    while IFS='|' read -r candidate_id _profile _strategy _score _elapsed verdict _reason _label _family _phase _dns _baseline _tls12 _tls13 _long_get _failure confidence _transport; do
        case "$verdict" in
            valid|unstable) ;;
            *) continue ;;
        esac
        tier="$(discovery_candidate_tier "$profile" "$candidate_id" 2>/dev/null || true)"
        case ",$tiers_csv," in
            *,"$tier",*) ;;
            *) continue ;;
        esac
        case "${confidence:-0}" in
            ''|*[!0-9]*) confidence=0 ;;
        esac
        [ "$confidence" -gt "$best" ] && best="$confidence"
    done < "$results_file"
    printf '%s\n' "$best"
}

discovery_family_scan_tier_needed() {
    local profile="$1"
    local tier="$2"
    local results_file="$3"
    local core_success core_conf early_success
    case "$tier" in
        cheap_basics|split_core|fake_core)
            return 0
            ;;
        combos)
            core_success="$(discovery_success_count_for_tiers "$profile" "$results_file" "split_core,fake_core")"
            core_conf="$(discovery_best_confidence_for_tiers "$profile" "$results_file" "split_core,fake_core")"
            [ "${core_success:-0}" -lt 2 ] && return 0
            [ "${core_conf:-0}" -lt 80 ] && return 0
            return 1
            ;;
        expensive_edge)
            early_success="$(discovery_success_count_for_tiers "$profile" "$results_file" "cheap_basics,split_core,fake_core,combos")"
            core_conf="$(discovery_best_confidence_for_tiers "$profile" "$results_file" "cheap_basics,split_core,fake_core,combos")"
            [ "${early_success:-0}" -eq 0 ] && return 0
            [ "${core_conf:-0}" -lt 70 ] && return 0
            return 1
            ;;
    esac
    return 0
}

discovery_results_sort_key() {
    local candidate_id profile strategy score elapsed verdict reason label family phase rank
    local dns_state baseline_state tls12_ok tls13_ok long_get_ok failure_class confidence transport_ok
    while IFS='|' read -r candidate_id profile strategy score elapsed verdict reason label family phase dns_state baseline_state tls12_ok tls13_ok long_get_ok failure_class confidence transport_ok; do
        [ -n "$candidate_id" ] || continue
        rank=$((score + 0))
        case "$verdict" in
            valid) rank=$((rank + 220)) ;;
            unstable) rank=$((rank + 120)) ;;
        esac
        case "$phase" in
            validate) rank=$((rank + 500)) ;;
            cached) rank=$((rank + 250)) ;;
            family_scan) rank=$((rank + 80)) ;;
            optimize) rank=$((rank + 40)) ;;
        esac
        if builder_load_definition "$profile" "$candidate_id" >/dev/null 2>&1; then
            rank=$((rank + (${STABILITY_HINT:-0} * 20)))
            rank=$((rank - (${COST_SCORE:-0} * 18)))
            case ",${RISK_FLAGS:-}," in
                *,custom_blob,*) rank=$((rank - 70)) ;;
            esac
            case ",${RISK_FLAGS:-}," in
                *,seqovl,*) rank=$((rank - 90)) ;;
            esac
            case ",${RISK_FLAGS:-}," in
                *,md5,*) rank=$((rank - 70)) ;;
            esac
            case ",${RISK_FLAGS:-}," in
                *,high_repeat,*) rank=$((rank - 30)) ;;
            esac
            case ",${FEATURES:-}," in
                *,repeat3,*) rank=$((rank + 20)) ;;
            esac
            case ",${CAPABILITIES:-}," in
                *,multisplit,*) rank=$((rank + 100)) ;;
                *,fakeddisorder,*) rank=$((rank + 90)) ;;
                *,fake,*) rank=$((rank + 85)) ;;
                *,tcpseg,*) rank=$((rank + 65)) ;;
                *,syndata,*) rank=$((rank + 55)) ;;
                *,oob,*) rank=$((rank + 35)) ;;
            esac
            case "$family" in
                fake_multisplit) rank=$((rank + 140)) ;;
                multisplit_fakeddisorder) rank=$((rank + 120)) ;;
                fake_fakeddisorder) rank=$((rank + 95)) ;;
                hostfakesplit) rank=$((rank + 70)) ;;
                fake_hostfakesplit) rank=$((rank + 60)) ;;
                fake_fakedsplit) rank=$((rank + 45)) ;;
                multisplit_fakedsplit) rank=$((rank + 40)) ;;
                multisplit_multidisorder) rank=$((rank - 60)) ;;
            esac
        fi
        case "${elapsed:-0}" in
            ''|*[!0-9]*) ;;
            *) rank=$((rank - (elapsed / 25))) ;;
        esac
        case "${confidence:-0}" in
            ''|*[!0-9]*) confidence=0 ;;
        esac
        rank=$((rank + (confidence / 2)))
        case "$transport_ok" in
            true) rank=$((rank + 30)) ;;
        esac
        [ "${long_get_ok:-0}" -gt 0 ] 2>/dev/null && rank=$((rank + 35))
        case "$failure_class" in
            success) rank=$((rank + 40)) ;;
            transport_partial) rank=$((rank - 20)) ;;
            dns|baseline|transport_blocked|strategy_invalid) rank=$((rank - 60)) ;;
        esac
        printf "%08d|%s\n" "$rank" "$candidate_id|$profile|$strategy|$score|$elapsed|$verdict|$reason|$label|$family|$phase|${dns_state:-unknown}|${baseline_state:-unknown}|${tls12_ok:-0}|${tls13_ok:-0}|${long_get_ok:-0}|${failure_class:-inconclusive}|${confidence:-0}|${transport_ok:-false}"
    done
}

discovery_rank_results() {
    local results_file="$1"
    [ -f "$results_file" ] || return 1
    discovery_results_sort_key < "$results_file" | sort -t '|' -k1,1nr -k5,5nr -k6,6n | cut -d '|' -f2-
}

discovery_recommend_candidate() {
    local results_file="$1"
    local top_line
    top_line="$(discovery_rank_results "$results_file" | head -n 1)"
    [ -n "$top_line" ] || return 1
    printf '%s\n' "$top_line"
}

discovery_phase_candidates() {
    local profile="$1"
    local phase="$2"
    local tier_filter="${3:-}"
    local file priority
    for file in "$(builder_candidates_dir "$profile")"/*.env; do
        [ -f "$file" ] || continue
        # shellcheck disable=SC1090
        . "$file"
        [ "${PHASE:-family_scan}" = "$phase" ] || continue
        if [ -n "$tier_filter" ]; then
            [ "$(discovery_candidate_tier "$profile" "${CANDIDATE_ID:-}")" = "$tier_filter" ] || continue
        fi
        priority="${PRIORITY:-0}"
        printf '%s\t%s\n' "$priority" "$file"
    done | sort -t $'\t' -k1,1nr -k2,2
}

discovery_result_json_line() {
    local profile="$1"
    local candidate_id="$2"
    local strategy_num="$3"
    local label="$4"
    local verdict="$5"
    local score="$6"
    local elapsed="$7"
    local reason="$8"
    local dns_state="${9:-unknown}"
    local baseline_state="${10:-unknown}"
    local tls12_ok="${11:-0}"
    local tls13_ok="${12:-0}"
    local long_get_ok="${13:-0}"
    local failure_class="${14:-inconclusive}"
    local confidence="${15:-0}"
    local transport_ok="${16:-false}"
    printf '{"candidate":"%s","profile":%s,"strategy":"%s","score":%s,"elapsed_ms":%s,"result":"%s","reason":"%s","label":"%s","family":"%s","capabilities":"%s","features":"%s","risk_flags":"%s","diversity_key":"%s","dns_state":"%s","baseline_state":"%s","tls12_ok":%s,"tls13_ok":%s,"long_get_ok":%s,"failure_class":"%s","confidence":%s,"transport_ok":%s}' \
        "$(discovery_json_escape "$candidate_id")" \
        "$profile" \
        "$(discovery_json_escape "$strategy_num")" \
        "${score:-0}" \
        "${elapsed:-0}" \
        "$(discovery_json_escape "$verdict")" \
        "$(discovery_json_escape "$reason")" \
        "$(discovery_json_escape "$label")" \
        "$(discovery_json_escape "${FAMILY:-unknown}")" \
        "$(discovery_json_escape "${CAPABILITIES:-}")" \
        "$(discovery_json_escape "${FEATURES:-}")" \
        "$(discovery_json_escape "${RISK_FLAGS:-}")" \
        "$(discovery_json_escape "${DIVERSITY_KEY:-}")" \
        "$(discovery_json_escape "$dns_state")" \
        "$(discovery_json_escape "$baseline_state")" \
        "${tls12_ok:-0}" \
        "${tls13_ok:-0}" \
        "${long_get_ok:-0}" \
        "$(discovery_json_escape "$failure_class")" \
        "${confidence:-0}" \
        "${transport_ok:-false}"
}

discovery_test_phase() {
    local session_id="$1"
    local profile="$2"
    local target="$3"
    local host="$4"
    local phase="$5"
    local repeats="$6"
    local timeout="$7"
    local results_file="$8"
    local json_file="$9"
    local tier_filter="${10:-}"
    local rank_file candidate_file candidate_id strat_num score elapsed verdict reason label family
    local dns_state baseline_state tls12_ok tls13_ok long_get_ok failure_class confidence transport_ok
    local checked=0 total=0
    total="$(discovery_phase_candidates "$profile" "$phase" "$tier_filter" | wc -l | tr -d ' ')"
    while IFS=$'\t' read -r _priority candidate_file; do
        [ -f "$candidate_file" ] || continue
        if discovery_cancel_requested "$profile"; then
            return 130
        fi
        candidate_id="$(basename "$candidate_file" .env)"
        if ! discovery_candidate_should_run "$profile" "$candidate_id" "$results_file"; then
            continue
        fi
        builder_load_definition "$profile" "$candidate_id" || continue
        label="${LABEL:-$candidate_id}"
        family="$(builder_policy_family_id "${FAMILY:-unknown}")"
        strat_num="$(builder_apply_candidate "$profile" "$candidate_id" "temp" 2>/dev/null)" || continue
        IFS=$'\t' read -r score elapsed verdict reason _probed_target dns_state baseline_state tls12_ok tls13_ok long_get_ok failure_class confidence transport_ok <<EOF
$(builder_probe_target "$target" "$profile" "$candidate_id" "$host" "$repeats" "$timeout" "$phase")
EOF
        printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "$candidate_id" "$profile" "$strat_num" "${score:-0}" "${elapsed:-0}" \
            "$verdict" "$reason" "$label" "$family" "$phase" \
            "${dns_state:-unknown}" "${baseline_state:-unknown}" "${tls12_ok:-0}" "${tls13_ok:-0}" "${long_get_ok:-0}" \
            "${failure_class:-inconclusive}" "${confidence:-0}" "${transport_ok:-false}" >> "$results_file"
        builder_record_knowledge_entry "$profile" "$candidate_id" "${score:-0}" "${elapsed:-0}" "$verdict" "$phase" || true
        [ "$(wc -c < "$json_file")" -gt 1 ] && printf ',' >> "$json_file"
        discovery_result_json_line "$profile" "$candidate_id" "$strat_num" "$label" "$verdict" "${score:-0}" "${elapsed:-0}" "$reason" \
            "${dns_state:-unknown}" "${baseline_state:-unknown}" "${tls12_ok:-0}" "${tls13_ok:-0}" "${long_get_ok:-0}" \
            "${failure_class:-inconclusive}" "${confidence:-0}" "${transport_ok:-false}" >> "$json_file"
        checked=$((checked + 1))
        discovery_update_runtime_progress "$session_id" "$profile" "running" "Discovery is running" "$phase" "$tier_filter" "$checked" "$total" "$results_file"
    done < <(discovery_phase_candidates "$profile" "$phase" "$tier_filter")
}

discovery_test_family_scan_tiers() {
    local session_id="$1"
    local profile="$2"
    local target="$3"
    local host="$4"
    local repeats="$5"
    local timeout="$6"
    local results_file="$7"
    local json_file="$8"
    local tier
    for tier in cheap_basics split_core fake_core combos expensive_edge; do
        if discovery_cancel_requested "$profile"; then
            return 130
        fi
        discovery_family_scan_tier_needed "$profile" "$tier" "$results_file" || continue
        discovery_update_runtime_progress "$session_id" "$profile" "running" "Discovery is running" "family_scan" "$tier" 0 "$(discovery_phase_candidates "$profile" "family_scan" "$tier" | wc -l | tr -d ' ')" "$results_file"
        discovery_test_phase "$session_id" "$profile" "$target" "$host" "family_scan" "$repeats" "$timeout" "$results_file" "$json_file" "$tier" || return $?
    done
}

discovery_working_families() {
    local results_file="$1"
    local phases_filter="${2:-}"
    awk -F '|' -v phases="$phases_filter" '
        BEGIN {
            split(phases, allow, ",")
            for (i in allow) if (allow[i] != "") allowed[allow[i]] = 1
        }
        {
            if (length(phases) > 0 && !($10 in allowed)) next
            if ($6 != "valid" && $6 != "unstable") next
            if (!seen[$9]++) print $9 "|" $1
        }
    ' "$results_file"
}

discovery_generate_optimizations() {
    local profile="$1"
    local results_file="$2"
    local family candidate_id generated
    while IFS='|' read -r family candidate_id; do
        [ -n "$family" ] || continue
        generated=0
        if type builder_generate_feature_optimizations >/dev/null 2>&1; then
            generated="$(builder_generate_feature_optimizations "$profile" "$family" "$candidate_id" 2>/dev/null || echo 0)"
        fi
        case "$generated" in
            ''|*[!0-9]*) generated=0 ;;
        esac
        [ "$generated" -gt 0 ] || builder_generate_family_optimizations "$profile" "$family" "$candidate_id"
    done < <(discovery_working_families "$results_file" "cached,family_scan")
}

discovery_promote_validation_candidate() {
    local profile="$1"
    local candidate_id="$2"
    sed -i "s/^PHASE=.*/PHASE='validate'/" "$(builder_candidate_file "$profile" "$candidate_id")" 2>/dev/null || true
    sed -i "s/^PRIORITY=.*/PRIORITY='300'/" "$(builder_candidate_file "$profile" "$candidate_id")" 2>/dev/null || true
}

discovery_promote_validation_candidates() {
    local profile="$1"
    local results_file="$2"
    local count=0
    local candidate_id verdict diversity_key seen_keys selected_ids ranked_file
    ranked_file="$(mktemp "${TMPDIR:-/tmp}/discovery-rank.XXXXXX")"
    discovery_rank_results "$results_file" > "$ranked_file"
    while IFS='|' read -r candidate_id _profile _strategy _score _elapsed verdict _reason _label _family _phase _dns _baseline _tls12 _tls13 _long _failure _confidence _transport; do
        [ -n "$candidate_id" ] || continue
        case "$verdict" in
            valid|unstable) ;;
            *) continue ;;
        esac
        builder_load_definition "$profile" "$candidate_id" || continue
        diversity_key="${DIVERSITY_KEY:-$candidate_id}"
        case "|$seen_keys|" in
            *"|$diversity_key|"*) continue ;;
        esac
        discovery_promote_validation_candidate "$profile" "$candidate_id"
        seen_keys="${seen_keys}|${diversity_key}"
        selected_ids="${selected_ids}|${candidate_id}"
        count=$((count + 1))
        [ "$count" -ge 3 ] && break
    done < "$ranked_file"
    if [ "$count" -lt 3 ]; then
        while IFS='|' read -r candidate_id _profile _strategy _score _elapsed verdict _reason _label _family _phase _dns _baseline _tls12 _tls13 _long _failure _confidence _transport; do
            [ -n "$candidate_id" ] || continue
            case "$verdict" in
                valid|unstable) ;;
                *) continue ;;
            esac
            case "|$selected_ids|" in
                *"|$candidate_id|"*) continue ;;
            esac
            builder_load_definition "$profile" "$candidate_id" || continue
            discovery_promote_validation_candidate "$profile" "$candidate_id"
            selected_ids="${selected_ids}|${candidate_id}"
            count=$((count + 1))
            [ "$count" -ge 3 ] && break
        done < "$ranked_file"
    fi
    rm -f "$ranked_file"
}

discovery_run_session() {
    local session_id="$1"
    local profile="$2"
    local target="$3"
    local hosts_csv="$4"
    local cfg backup_cfg prev_locks prev_active host_json recommendation_json
    local tmp_results tmp_json_results tmp_phases

    builder_seed_profile_candidates "$profile" || return 1
    cfg="$(builder_current_config_file)"
    backup_cfg="$(mktemp)"
    if ! builder_policy_runtime_enabled "$profile"; then
        cp "$cfg" "$backup_cfg"
    else
        : > "$backup_cfg"
        builder_capture_runtime_state "$profile"
    fi
    prev_locks=""
    if ! builder_policy_runtime_enabled "$profile" && type orch_locked_get >/dev/null 2>&1; then
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
    host_json="$(printf '"%s"' "$(discovery_json_escape "$hosts_csv")")"

    discovery_update_runtime_state "$session_id" "$profile" "running" "Discovery is running"
    printf '[' > "$tmp_json_results"

    printf '[' > "$tmp_phases"
    printf '{"phase":"cached","status":"completed","finished_at":"%s"}' "$(discovery_now_iso)" >> "$tmp_phases"
    discovery_test_phase "$session_id" "$profile" "$target" "$hosts_csv" "cached" 2 4 "$tmp_results" "$tmp_json_results" || {
        [ "$?" -eq 130 ] || return 1
        discovery_finalize_stopped_session "$session_id" "$profile" "$target" "$host_json" "$cfg" "$backup_cfg" "$prev_locks" "$prev_active" "$tmp_phases" "$tmp_json_results" "$tmp_results"
        return 0
    }
    printf ',{"phase":"family_scan","status":"completed","finished_at":"%s"}' "$(discovery_now_iso)" >> "$tmp_phases"
    discovery_test_family_scan_tiers "$session_id" "$profile" "$target" "$hosts_csv" 2 4 "$tmp_results" "$tmp_json_results" || {
        [ "$?" -eq 130 ] || return 1
        discovery_finalize_stopped_session "$session_id" "$profile" "$target" "$host_json" "$cfg" "$backup_cfg" "$prev_locks" "$prev_active" "$tmp_phases" "$tmp_json_results" "$tmp_results"
        return 0
    }

    discovery_generate_optimizations "$profile" "$tmp_results"
    printf ',{"phase":"optimize","status":"completed","finished_at":"%s"}' "$(discovery_now_iso)" >> "$tmp_phases"
    discovery_test_phase "$session_id" "$profile" "$target" "$hosts_csv" "optimize" 2 5 "$tmp_results" "$tmp_json_results" || {
        [ "$?" -eq 130 ] || return 1
        discovery_finalize_stopped_session "$session_id" "$profile" "$target" "$host_json" "$cfg" "$backup_cfg" "$prev_locks" "$prev_active" "$tmp_phases" "$tmp_json_results" "$tmp_results"
        return 0
    }

    discovery_promote_validation_candidates "$profile" "$tmp_results"
    printf ',{"phase":"validate","status":"completed","finished_at":"%s"}' "$(discovery_now_iso)" >> "$tmp_phases"
    discovery_test_phase "$session_id" "$profile" "$target" "$hosts_csv" "validate" 3 6 "$tmp_results" "$tmp_json_results" || {
        [ "$?" -eq 130 ] || return 1
        discovery_finalize_stopped_session "$session_id" "$profile" "$target" "$host_json" "$cfg" "$backup_cfg" "$prev_locks" "$prev_active" "$tmp_phases" "$tmp_json_results" "$tmp_results"
        return 0
    }

    printf ']' >> "$tmp_json_results"
    printf ']' >> "$tmp_phases"

    builder_restore_config_and_state "$cfg" "$backup_cfg" "$profile" "$prev_locks" "$prev_active"
    recommendation_json="$(discovery_recommendation_json_from_line "$(discovery_recommend_candidate "$tmp_results")")"
    [ -n "$recommendation_json" ] || recommendation_json="null"
    discovery_write_session_json "$session_id" "$profile" "$target" "$host_json" "$(cat "$tmp_phases")" "$(cat "$tmp_json_results")" "$recommendation_json" "completed" "Discovery completed"
    discovery_update_runtime_state "$session_id" "$profile" "completed" "Discovery completed"
    printf '%s' "$session_id" > "$(builder_last_session_file "$profile")"
    rm -f "$(discovery_runtime_progress_file "$profile").stop"
    if type builder_sync_webui_profile_cache >/dev/null 2>&1; then
        builder_sync_webui_profile_cache "$profile"
    fi
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
