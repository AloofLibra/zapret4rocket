#!/bin/bash

validator_policy_store_module="${validator_policy_store_module:-/opt/zapret2/z2r_lib/policy_store.sh}"
validator_netcheck_module="${validator_netcheck_module:-/opt/zapret2/z2r_lib/netcheck.sh}"
validator_snapshot_settle_sec="${validator_snapshot_settle_sec:-4}"

[ -f "$validator_policy_store_module" ] && . "$validator_policy_store_module"
[ -f "$validator_netcheck_module" ] && . "$validator_netcheck_module"

validator_json_compact() {
    tr -d '\r\n\t' < "$1" | sed 's/[[:space:]]\+/ /g'
}

validator_json_get_string() {
    local file="$1"
    local key="$2"
    local raw data
    raw="$(validator_json_compact "$file")"
    data="${raw#*\"$key\"}"
    [ "$data" != "$raw" ] || return 1
    data="${data#*:}"
    data="$(printf '%s' "$data" | sed 's/^ *//')"
    data="${data#\"}"
    printf '%s' "${data%%\"*}"
}

validator_json_get_number() {
    local file="$1"
    local key="$2"
    local raw data
    raw="$(validator_json_compact "$file")"
    data="${raw#*\"$key\"}"
    [ "$data" != "$raw" ] || return 1
    data="${data#*:}"
    data="$(printf '%s' "$data" | sed 's/^ *//')"
    printf '%s' "$data" | sed -n 's/^\(-\{0,1\}[0-9][0-9.]*\).*$/\1/p'
}

validator_json_get_bool() {
    local file="$1"
    local key="$2"
    local raw data
    raw="$(validator_json_compact "$file")"
    data="${raw#*\"$key\"}"
    [ "$data" != "$raw" ] || return 1
    data="${data#*:}"
    data="$(printf '%s' "$data" | sed 's/^ *//')"
    case "$data" in
        true*) printf 'true' ;;
        false*) printf 'false' ;;
        *) return 1 ;;
    esac
}

validator_json_get_array_csv() {
    local file="$1"
    local key="$2"
    local raw data array
    raw="$(validator_json_compact "$file")"
    data="${raw#*\"$key\"}"
    [ "$data" != "$raw" ] || return 1
    data="${data#*:}"
    array="$(printf '%s' "$data" | sed -n 's/^[^[]*\[\([^]]*\)\].*$/\1/p')"
    printf '%s' "$array" | sed 's/"//g; s/, */,/g'
}

validator_json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

validator_now_iso() {
    date +%Y-%m-%dT%H:%M:%S%z
}

validator_probe_tls12() {
    local url="$1"
    local repeats="${2:-1}"
    local timeout="${3:-5}"
    local ok=0 i=1 code
    while [ "$i" -le "$repeats" ]; do
        code="$(curl --tls-max 1.2 --max-time "$timeout" -sS -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo 000)"
        case "$code" in
            000) : ;;
            *) ok=$((ok + 1)) ;;
        esac
        i=$((i + 1))
    done
    printf '%s\n' "$ok"
}

validator_probe_tls13() {
    local url="$1"
    local repeats="${2:-1}"
    local timeout="${3:-5}"
    local ok=0 i=1 code
    while [ "$i" -le "$repeats" ]; do
        code="$(curl --tlsv1.3 --max-time "$timeout" -sS -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo 000)"
        case "$code" in
            000) : ;;
            *) ok=$((ok + 1)) ;;
        esac
        i=$((i + 1))
    done
    printf '%s\n' "$ok"
}

validator_probe_quic() {
    local url="$1"
    local repeats="${2:-1}"
    local timeout="${3:-5}"
    local ok=0 i=1
    while [ "$i" -le "$repeats" ]; do
        curl --http3-only --max-time "$timeout" -fsS -o /dev/null "$url" >/dev/null 2>&1 && ok=$((ok + 1)) || true
        i=$((i + 1))
    done
    printf '%s\n' "$ok"
}

validator_probe_long_get() {
    local url="$1"
    local repeats="${2:-1}"
    local timeout="${3:-5}"
    local ok=0 i=1 code
    while [ "$i" -le "$repeats" ]; do
        code="$(curl --max-time "$timeout" -sS -A "Mozilla/5.0" -o /dev/null -w '%{http_code}' "${url}?z2r_probe=$(date +%s)$i" 2>/dev/null || echo 000)"
        case "$code" in
            000) : ;;
            *) ok=$((ok + 1)) ;;
        esac
        i=$((i + 1))
    done
    printf '%s\n' "$ok"
}

validator_dns_check() {
    local host="$1"
    case "$host" in
        *.*) ;;
        *)
            printf 'unknown\n'
            return
            ;;
    esac
    if command -v getent >/dev/null 2>&1; then
        getent hosts "$host" >/dev/null 2>&1 && printf 'ok\n' || printf 'fail\n'
        return
    fi
    if command -v nslookup >/dev/null 2>&1; then
        nslookup "$host" >/dev/null 2>&1 && printf 'ok\n' || printf 'fail\n'
        return
    fi
    printf 'unknown\n'
}

validator_ip_block_check() {
    local host="$1"
    local resolved=""
    if command -v getent >/dev/null 2>&1; then
        resolved="$(getent hosts "$host" 2>/dev/null | awk 'NR==1{print $1}')"
    elif command -v nslookup >/dev/null 2>&1; then
        resolved="$(nslookup "$host" 2>/dev/null | awk '/^Address: /{print $2; exit}')"
    fi
    [ -n "$resolved" ] && printf 'ok\n' || printf 'unknown\n'
}

validator_baseline() {
    local reference_url="$1"
    local repeats="${2:-1}"
    local timeout="${3:-5}"
    local ok
    ok="$(validator_probe_long_get "$reference_url" "$repeats" "$timeout")"
    [ "${ok:-0}" -gt 0 ] && printf 'ok\n' || printf 'fail\n'
}

validator_build_verdict() {
    local result_dir="$1"
    local tls12_ok tls13_ok long_get_ok dns_state ip_state baseline_state quic_ok verdict

    tls12_ok="$(cat "$result_dir/tls12.ok" 2>/dev/null || echo 0)"
    tls13_ok="$(cat "$result_dir/tls13.ok" 2>/dev/null || echo 0)"
    long_get_ok="$(cat "$result_dir/long_get.ok" 2>/dev/null || echo 0)"
    dns_state="$(cat "$result_dir/dns_check.state" 2>/dev/null || echo unknown)"
    ip_state="$(cat "$result_dir/ip_block_check.state" 2>/dev/null || echo unknown)"
    baseline_state="$(cat "$result_dir/baseline.state" 2>/dev/null || echo unknown)"
    quic_ok="$(cat "$result_dir/quic.ok" 2>/dev/null || echo 0)"

    verdict="inconclusive"
    if [ "$dns_state" = "fail" ]; then
        verdict="dns_poisoned"
    elif [ "$baseline_state" = "fail" ]; then
        verdict="transport_blocked"
    elif [ "$tls12_ok" -gt 0 ] && [ "$tls13_ok" -gt 0 ] && [ "$long_get_ok" -gt 0 ]; then
        verdict="valid"
    elif [ "$tls12_ok" -gt 0 ] || [ "$tls13_ok" -gt 0 ] || [ "$quic_ok" -gt 0 ]; then
        verdict="unstable"
    elif [ "$ip_state" = "ok" ] && [ "$dns_state" = "ok" ]; then
        verdict="invalid"
    fi

    printf '%s\n' "$verdict"
}

validator_result_score() {
    local verdict="$1"
    case "$verdict" in
        valid) echo 3000 ;;
        unstable) echo 2000 ;;
        inconclusive) echo 1000 ;;
        dns_poisoned|transport_blocked|invalid) echo 0 ;;
        *) echo 0 ;;
    esac
}

validator_transport_ok() {
    local tls12_ok="${1:-0}"
    local tls13_ok="${2:-0}"
    local long_get_ok="${3:-0}"
    local quic_ok="${4:-0}"
    if [ "${tls12_ok:-0}" -gt 0 ] || [ "${tls13_ok:-0}" -gt 0 ] || [ "${long_get_ok:-0}" -gt 0 ] || [ "${quic_ok:-0}" -gt 0 ]; then
        printf 'true\n'
    else
        printf 'false\n'
    fi
}

validator_failure_class() {
    local verdict="$1"
    local dns_state="$2"
    local baseline_state="$3"
    local transport_ok="$4"
    case "$verdict" in
        valid) printf 'success\n' ;;
        unstable)
            if [ "$transport_ok" = "true" ]; then
                printf 'transport_partial\n'
            else
                printf 'unstable_unknown\n'
            fi
            ;;
        dns_poisoned)
            printf 'dns\n'
            ;;
        transport_blocked)
            if [ "$baseline_state" = "fail" ]; then
                printf 'baseline\n'
            else
                printf 'transport_blocked\n'
            fi
            ;;
        invalid)
            if [ "$dns_state" = "ok" ]; then
                printf 'strategy_invalid\n'
            else
                printf 'invalid_unknown\n'
            fi
            ;;
        *)
            printf 'inconclusive\n'
            ;;
    esac
}

validator_confidence() {
    local verdict="$1"
    local tls12_ok="${2:-0}"
    local tls13_ok="${3:-0}"
    local long_get_ok="${4:-0}"
    local dns_state="$5"
    local baseline_state="$6"
    local confidence=35
    [ "${tls12_ok:-0}" -gt 0 ] && confidence=$((confidence + 15))
    [ "${tls13_ok:-0}" -gt 0 ] && confidence=$((confidence + 20))
    [ "${long_get_ok:-0}" -gt 0 ] && confidence=$((confidence + 20))
    [ "$dns_state" = "ok" ] && confidence=$((confidence + 5))
    [ "$baseline_state" = "ok" ] && confidence=$((confidence + 5))
    case "$verdict" in
        valid) confidence=$((confidence + 15)) ;;
        unstable) confidence=$((confidence - 5)) ;;
        dns_poisoned|transport_blocked) confidence=20 ;;
        invalid) confidence=25 ;;
        *) confidence=30 ;;
    esac
    [ "$confidence" -lt 0 ] && confidence=0
    [ "$confidence" -gt 100 ] && confidence=100
    printf '%s\n' "$confidence"
}

validator_target_from_job() {
    local job_json="$1"
    local target_url host profile
    target_url="$(validator_json_get_string "$job_json" "target_url" 2>/dev/null || true)"
    [ -n "$target_url" ] && { printf '%s\n' "$target_url"; return 0; }
    host="$(validator_json_get_array_csv "$job_json" "hosts" 2>/dev/null | cut -d',' -f1)"
    [ -n "$host" ] && { printf 'https://%s/\n' "$host"; return 0; }
    profile="$(validator_json_get_number "$job_json" "profile" 2>/dev/null || true)"
    case "$profile" in
        1) printf 'https://www.youtube.com/\n' ;;
        2)
            if type get_yt_cluster_domain >/dev/null 2>&1; then
                printf 'https://%s\n' "$(get_yt_cluster_domain)"
            else
                printf 'https://rr1---sn-5goeenes.googlevideo.com\n'
            fi
            ;;
        *) return 1 ;;
    esac
}

validator_tmp_backup_file() {
    mktemp "${TMPDIR:-/tmp}/validator-state.XXXXXX"
}

validator_backup_state_file() {
    local src="$1"
    local backup="$2"
    if [ -f "$src" ]; then
        cp "$src" "$backup"
    else
        : > "$backup"
    fi
}

validator_restore_state_file() {
    local backup="$1"
    local dst="$2"
    if [ -s "$backup" ]; then
        policy_write_from_file "$dst" "$backup"
    else
        rm -f "$dst"
    fi
}

validator_apply_candidate_runtime_state() {
    local job_json="$1"
    local profile="$2"
    local candidate_id="$3"
    local host="$4"
    local backup_profile="$5"
    local backup_domain="$6"
    local profile_state_file domain_state_file state_tmp

    profile_state_file="$policy_state_profiles_root/$profile.json"
    domain_state_file=""
    [ -n "$host" ] && domain_state_file="$policy_state_domains_root/$(printf '%s' "$host" | tr 'A-Z' 'a-z' | tr '/:\\ ' '_').json"

    validator_backup_state_file "$profile_state_file" "$backup_profile"
    if [ -n "$domain_state_file" ]; then
        validator_backup_state_file "$domain_state_file" "$backup_domain"
    else
        : > "$backup_domain"
    fi

    state_tmp="$(mktemp "${TMPDIR:-/tmp}/validator-apply.XXXXXX")" || return 1
    cat > "$state_tmp" <<EOF
{
  "profile": $profile,
  "mode": "validator_testing",
  "active_candidate_id": "$(validator_json_escape "$candidate_id")",
  "active_family_id": "",
  "status": "testing",
  "confidence": 0.5,
  "pending_job_id": "$(validator_json_escape "$(validator_json_get_string "$job_json" "job_id" 2>/dev/null || echo "")")",
  "fallback_chain": [],
  "last_validated_at": "$(validator_now_iso)",
  "source": "validator_preflight"
}
EOF
    policy_write_profile_state "$profile" "$state_tmp"

    if [ -n "$domain_state_file" ] && [ -n "$host" ]; then
        cat > "$state_tmp" <<EOF
{
  "host": "$(validator_json_escape "$host")",
  "group_key": "$(validator_json_escape "$host")",
  "profile": $profile,
  "active_candidate_id": "$(validator_json_escape "$candidate_id")",
  "status": "testing",
  "confidence": 0.5,
  "blocked_candidates": [],
  "unstable_candidates": [],
  "last_success_at": "",
  "last_failure_at": ""
}
EOF
        policy_write_domain_state "$(printf '%s' "$host" | tr 'A-Z' 'a-z' | tr '/:\\ ' '_')" "$state_tmp"
    fi

    rm -f "$state_tmp"
    policy_rebuild_runtime_snapshot >/dev/null 2>&1 || true
}

validator_restore_runtime_state() {
    local profile="$1"
    local host="$2"
    local backup_profile="$3"
    local backup_domain="$4"
    local profile_state_file domain_state_file

    profile_state_file="$policy_state_profiles_root/$profile.json"
    domain_state_file=""
    [ -n "$host" ] && domain_state_file="$policy_state_domains_root/$(printf '%s' "$host" | tr 'A-Z' 'a-z' | tr '/:\\ ' '_').json"

    validator_restore_state_file "$backup_profile" "$profile_state_file"
    if [ -n "$domain_state_file" ]; then
        validator_restore_state_file "$backup_domain" "$domain_state_file"
    fi
    policy_rebuild_runtime_snapshot >/dev/null 2>&1 || true
}

validator_validate_candidate() {
    local job_json="$1"
    local result_dir result_json
    local job_id profile candidate_id source repeats timeout target_url reference_url host dns_host
    local check_tls12 check_tls13 check_quic check_long_get check_dns check_ip check_baseline
    local started_at finished_at elapsed_ms
    local tls12_ok=0 tls13_ok=0 quic_ok=0 long_get_ok=0 dns_state="unknown" ip_state="unknown" baseline_state="unknown"
    local verdict score transport_ok failure_class confidence
    local backup_profile backup_domain

    job_id="$(validator_json_get_string "$job_json" "job_id" 2>/dev/null || echo "")"
    profile="$(validator_json_get_number "$job_json" "profile" 2>/dev/null || echo 0)"
    candidate_id="$(validator_json_get_string "$job_json" "candidate_id" 2>/dev/null || echo "")"
    source="$(validator_json_get_string "$job_json" "source" 2>/dev/null || echo "unknown")"
    repeats="$(validator_json_get_number "$job_json" "repeats" 2>/dev/null || echo 1)"
    timeout="$(validator_json_get_number "$job_json" "timeout_sec" 2>/dev/null || echo 5)"
    target_url="$(validator_target_from_job "$job_json" 2>/dev/null || echo "")"
    reference_url="$(validator_json_get_string "$job_json" "reference_url" 2>/dev/null || echo "https://example.com/")"
    host="$(validator_json_get_array_csv "$job_json" "hosts" 2>/dev/null | cut -d',' -f1)"
    dns_host="$(validator_json_get_string "$job_json" "dns_host" 2>/dev/null || echo "")"
    [ -n "$dns_host" ] || dns_host="$host"

    check_tls12="$(validator_json_get_bool "$job_json" "tls12" 2>/dev/null || echo false)"
    check_tls13="$(validator_json_get_bool "$job_json" "tls13" 2>/dev/null || echo false)"
    check_quic="$(validator_json_get_bool "$job_json" "quic" 2>/dev/null || echo false)"
    check_long_get="$(validator_json_get_bool "$job_json" "long_get" 2>/dev/null || echo false)"
    check_dns="$(validator_json_get_bool "$job_json" "dns_check" 2>/dev/null || echo false)"
    check_ip="$(validator_json_get_bool "$job_json" "ip_block_check" 2>/dev/null || echo false)"
    check_baseline="$(validator_json_get_bool "$job_json" "baseline" 2>/dev/null || echo false)"

    [ -n "$job_id" ] || return 1
    result_dir="$(mktemp -d "${TMPDIR:-/tmp}/validator-result.XXXXXX")" || return 1
    result_json="$result_dir/result.json"
    started_at="$(validator_now_iso)"
    backup_profile="$(validator_tmp_backup_file)" || return 1
    backup_domain="$(validator_tmp_backup_file)" || {
        rm -f "$backup_profile"
        return 1
    }
    validator_apply_candidate_runtime_state "$job_json" "$profile" "$candidate_id" "$host" "$backup_profile" "$backup_domain" || {
        rm -rf "$result_dir"
        rm -f "$backup_profile" "$backup_domain"
        return 1
    }
    # Temporary workaround: nfqws caches runtime_snapshot.lua in Lua for a few seconds.
    # Give policy-state cache time to expire before probing, otherwise validation may
    # hit the previously active candidate and produce false positives.
    sleep "$validator_snapshot_settle_sec"
    if [ -n "$target_url" ]; then
        date +%s%3N > "$result_dir/start.ms" 2>/dev/null || date +%s000 > "$result_dir/start.ms"
        [ "$check_tls12" = "true" ] && tls12_ok="$(validator_probe_tls12 "$target_url" "$repeats" "$timeout")"
        [ "$check_tls13" = "true" ] && tls13_ok="$(validator_probe_tls13 "$target_url" "$repeats" "$timeout")"
        [ "$check_quic" = "true" ] && quic_ok="$(validator_probe_quic "$target_url" "$repeats" "$timeout")"
        [ "$check_long_get" = "true" ] && long_get_ok="$(validator_probe_long_get "$target_url" "$repeats" "$timeout")"
    fi
    [ "$check_dns" = "true" ] && [ -n "$dns_host" ] && dns_state="$(validator_dns_check "$dns_host")"
    [ "$check_ip" = "true" ] && [ -n "$host" ] && ip_state="$(validator_ip_block_check "$host")"
    [ "$check_baseline" = "true" ] && baseline_state="$(validator_baseline "$reference_url" "$repeats" "$timeout")"
    validator_restore_runtime_state "$profile" "$host" "$backup_profile" "$backup_domain"
    rm -f "$backup_profile" "$backup_domain"
    finished_at="$(validator_now_iso)"
    date +%s%3N > "$result_dir/end.ms" 2>/dev/null || date +%s000 > "$result_dir/end.ms"
    elapsed_ms=$(( $(cat "$result_dir/end.ms") - $(cat "$result_dir/start.ms") ))

    printf '%s' "$tls12_ok" > "$result_dir/tls12.ok"
    printf '%s' "$tls13_ok" > "$result_dir/tls13.ok"
    printf '%s' "$quic_ok" > "$result_dir/quic.ok"
    printf '%s' "$long_get_ok" > "$result_dir/long_get.ok"
    printf '%s' "$dns_state" > "$result_dir/dns_check.state"
    printf '%s' "$ip_state" > "$result_dir/ip_block_check.state"
    printf '%s' "$baseline_state" > "$result_dir/baseline.state"

    verdict="$(validator_build_verdict "$result_dir")"
    score="$(validator_result_score "$verdict")"
    transport_ok="$(validator_transport_ok "$tls12_ok" "$tls13_ok" "$long_get_ok" "$quic_ok")"
    failure_class="$(validator_failure_class "$verdict" "$dns_state" "$baseline_state" "$transport_ok")"
    confidence="$(validator_confidence "$verdict" "$tls12_ok" "$tls13_ok" "$long_get_ok" "$dns_state" "$baseline_state")"

    cat > "$result_json" <<EOF
{
  "job_id": "$(validator_json_escape "$job_id")",
  "type": "validate_candidate",
  "profile": $profile,
  "candidate_id": "$(validator_json_escape "$candidate_id")",
  "source": "$(validator_json_escape "$source")",
  "target_url": "$(validator_json_escape "$target_url")",
  "host": "$(validator_json_escape "$host")",
  "dns_host": "$(validator_json_escape "$dns_host")",
  "started_at": "$(validator_json_escape "$started_at")",
  "finished_at": "$(validator_json_escape "$finished_at")",
  "elapsed_ms": ${elapsed_ms:-0},
  "verdict": "$(validator_json_escape "$verdict")",
  "score": ${score:-0},
  "failure_class": "$(validator_json_escape "$failure_class")",
  "confidence": ${confidence:-0},
  "transport_ok": $transport_ok,
  "dns_state": "$(validator_json_escape "$dns_state")",
  "baseline_state": "$(validator_json_escape "$baseline_state")",
  "ip_state": "$(validator_json_escape "$ip_state")",
  "tls12_ok": ${tls12_ok:-0},
  "tls13_ok": ${tls13_ok:-0},
  "long_get_ok": ${long_get_ok:-0},
  "quic_ok": ${quic_ok:-0},
  "checks": {
    "tls12": { "ok": ${tls12_ok:-0}, "enabled": $check_tls12 },
    "tls13": { "ok": ${tls13_ok:-0}, "enabled": $check_tls13 },
    "long_get": { "ok": ${long_get_ok:-0}, "enabled": $check_long_get },
    "dns_check": { "state": "$(validator_json_escape "$dns_state")", "enabled": $check_dns },
    "ip_block_check": { "state": "$(validator_json_escape "$ip_state")", "enabled": $check_ip },
    "baseline": { "state": "$(validator_json_escape "$baseline_state")", "enabled": $check_baseline },
    "quic": { "ok": ${quic_ok:-0}, "enabled": $check_quic }
  }
}
EOF
    printf '%s\n' "$result_json"
}
