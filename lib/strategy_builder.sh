#!/bin/bash

if [ "${__Z4R_STRATEGY_BUILDER_SOURCED:-0}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi
__Z4R_STRATEGY_BUILDER_SOURCED=1

builder_root="${builder_root:-/opt/zapret2/extra_strats/cache/builder}"
builder_profiles_root="$builder_root/profiles"
builder_sessions_root="$builder_root/sessions"
builder_repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
builder_policy_store_module="${builder_policy_store_module:-/opt/zapret2/z2r_lib/policy_store.sh}"
builder_validator_module="${builder_validator_module:-/opt/zapret2/z2r_lib/strategy_validator.sh}"
builder_validator_daemon="${builder_validator_daemon:-/opt/zapret2/extra_strats/cache/orchestra/validator_daemon.sh}"
builder_discovery_engine_module="${builder_discovery_engine_module:-/opt/zapret2/z2r_lib/discovery_engine.sh}"
builder_webui_runtime_root="${builder_webui_runtime_root:-/opt/zapret2/extra_strats/cache/webui-builder}"

[ -f "$builder_policy_store_module" ] && . "$builder_policy_store_module"
[ -f "$builder_validator_module" ] && . "$builder_validator_module"
[ -f "$builder_discovery_engine_module" ] && . "$builder_discovery_engine_module"

builder_init_dirs() {
    mkdir -p "$builder_profiles_root" "$builder_sessions_root"
}

builder_profile_supported() {
    case "$1" in
        1|2) return 0 ;;
        *) return 1 ;;
    esac
}

builder_profile_proto() {
    case "$1" in
        1|2) echo "tls" ;;
        *) echo "" ;;
    esac
}

builder_profile_lock_protos() {
    case "$1" in
        1) echo "tls http" ;;
        2) echo "tls" ;;
        *) echo "" ;;
    esac
}

builder_profile_label() {
    case "$1" in
        1) echo "YouTube TCP" ;;
        2) echo "Googlevideo" ;;
        *) echo "Unknown" ;;
    esac
}

builder_profile_target() {
    case "$1" in
        1) echo "https://www.youtube.com/" ;;
        2)
            if type get_yt_cluster_domain >/dev/null 2>&1; then
                echo "https://$(get_yt_cluster_domain)"
            else
                echo "https://rr1---sn-5goeenes.googlevideo.com"
            fi
            ;;
        *) echo "" ;;
    esac
}

builder_profile_host_scope() {
    case "$1" in
        1) echo "profile_yt" ;;
        2) echo "googlevideo.com" ;;
        *) echo "profile" ;;
    esac
}

builder_profile_dns_host() {
    case "$1" in
        1) echo "youtube.com" ;;
        2)
            if type get_yt_cluster_domain >/dev/null 2>&1; then
                get_yt_cluster_domain
            else
                echo "rr1---sn-5goeenes.googlevideo.com"
            fi
            ;;
        *) echo "" ;;
    esac
}

builder_profile_dir() {
    printf '%s/profile_%s\n' "$builder_profiles_root" "$1"
}

builder_candidates_dir() {
    printf '%s/candidates\n' "$(builder_profile_dir "$1")"
}

builder_active_file() {
    printf '%s/active.env\n' "$(builder_profile_dir "$1")"
}

builder_last_session_file() {
    printf '%s/last_session\n' "$(builder_profile_dir "$1")"
}

builder_candidate_file() {
    printf '%s/%s.env\n' "$(builder_candidates_dir "$1")" "$2"
}

builder_webui_candidates_cache_file() {
    printf '%s/builder-candidates-%s.json\n' "$builder_webui_runtime_root" "$1"
}

builder_webui_last_session_cache_file() {
    printf '%s/last-session-%s.json\n' "$builder_webui_runtime_root" "$1"
}

builder_webui_discovery_runtime_file() {
    printf '%s/discovery-%s.runtime.json\n' "$builder_webui_runtime_root" "$1"
}

builder_current_config_file() {
    if [ -f /opt/zapret2/config ]; then
        echo "/opt/zapret2/config"
    elif [ -f /opt/zapret2/config.default ]; then
        echo "/opt/zapret2/config.default"
    elif [ -f "$builder_repo_root/config.default" ]; then
        echo "$builder_repo_root/config.default"
    else
        echo "/opt/zapret2/config.default"
    fi
}

builder_escape_env() {
    printf "%s" "$1" | sed "s/'/'\"'\"'/g"
}

builder_json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

builder_policy_candidate_id() {
    printf 'p%s-%s\n' "$1" "$2"
}

builder_policy_catalog_json_file() {
    printf '%s/catalog.json\n' "$(builder_profile_dir "$1")"
}

builder_policy_catalog_lua_file() {
    printf '%s/catalog.lua\n' "$(builder_profile_dir "$1")"
}

builder_policy_profile_state_json_file() {
    printf '%s/policy-state.json\n' "$(builder_profile_dir "$1")"
}

builder_knowledge_file() {
    printf '%s/discovery-knowledge.tsv\n' "$(builder_profile_dir "$1")"
}

builder_runtime_backup_dir() {
    printf '%s/runtime-backup\n' "$(builder_profile_dir "$1")"
}

builder_policy_runtime_enabled() {
    local profile="$1"
    if ! builder_profile_supported "$profile"; then
        return 1
    fi
    type policy_write_profile_state >/dev/null 2>&1 || return 1
    type policy_rebuild_runtime_snapshot >/dev/null 2>&1 || return 1
    case "$profile" in
        1|2) return 0 ;;
        *) return 1 ;;
    esac
}

builder_candidate_count() {
    local profile="$1"
    local count=0
    local file=""
    for file in "$(builder_candidates_dir "$profile")"/*.env; do
        [ -f "$file" ] || continue
        count=$((count + 1))
    done
    printf '%s\n' "$count"
}

builder_next_candidate_id() {
    local profile="$1"
    local count
    count="$(builder_candidate_count "$profile")"
    printf 'c%02d\n' $((count + 1))
}

builder_candidate_signature() {
    local step1="${1:-}"
    local step2="${2:-}"
    local step3="${3:-}"
    printf '%s|%s|%s\n' "$step1" "$step2" "$step3"
}

builder_find_candidate_by_signature() {
    local profile="$1"
    local target_sig="$2"
    local file sig
    for file in "$(builder_candidates_dir "$profile")"/*.env; do
        [ -f "$file" ] || continue
        # shellcheck disable=SC1090
        . "$file"
        sig="$(builder_candidate_signature "${STEP1:-}" "${STEP2:-}" "${STEP3:-}")"
        if [ "$sig" = "$target_sig" ]; then
            basename "$file" .env
            return 0
        fi
    done
    return 1
}

builder_reset_profile_candidates() {
    local profile="$1"
    mkdir -p "$(builder_candidates_dir "$profile")"
    rm -f "$(builder_candidates_dir "$profile")"/*.env
}

builder_humanize_step() {
    local step="$1"
    local rest
    case "${step%%:*}" in
        tcpseg)
            case "$step" in
                *pos=0,midsld*) printf 'tcpseg midsld' ;;
                *pos=0,1*) printf 'tcpseg 0,1' ;;
                *pos=0,method+2*) printf 'tcpseg method+2' ;;
                *) printf 'tcpseg' ;;
            esac
            ;;
        fake)
            rest="${step#*:}"
            case "$rest" in
                *tcp_ts=-1500*) printf 'fake ts-1500' ;;
                *tcp_ts=-1000*) printf 'fake ts-1000' ;;
                *tcp_ts=-500*) printf 'fake ts-500' ;;
                *tcp_seq=-3000*) printf 'fake seq-3000' ;;
                *) printf 'fake' ;;
            esac
            ;;
        multisplit)
            case "$step" in
                *pos=1,midsld*) printf 'multisplit midsld' ;;
                *pos=1,sniext+1*) printf 'multisplit sniext+1' ;;
                *pos=1,sniext+4*) printf 'multisplit sniext+4' ;;
                *pos=host+1*) printf 'multisplit host+1' ;;
                *pos=1,endsld*) printf 'multisplit endsld' ;;
                *pos=2*nodrop*) printf 'multisplit pos2 nodrop' ;;
                *seqovl=666*) printf 'multisplit seqovl' ;;
                *) printf 'multisplit' ;;
            esac
            ;;
        fakeddisorder)
            case "$step" in
                *pos=sniext+4*) printf 'fakeddisorder sniext+4' ;;
                *pos=sniext+1*) printf 'fakeddisorder sniext+1' ;;
                *pos=endsld*) printf 'fakeddisorder endsld' ;;
                *pos=midsld*) printf 'fakeddisorder midsld' ;;
                *) printf 'fakeddisorder' ;;
            esac
            ;;
        fakedsplit) printf 'fakedsplit' ;;
        hostfakesplit)
            case "$step" in
                *midhost=midsld*) printf 'hostfakesplit midhost' ;;
                *nofake1*) printf 'hostfakesplit nofake1' ;;
                *nofake2*) printf 'hostfakesplit nofake2' ;;
                *tcp_md5*) printf 'hostfakesplit md5' ;;
                *ip_autottl=5,3-20*) printf 'hostfakesplit autottl' ;;
                *tcp_ack=-66000*) printf 'hostfakesplit ack' ;;
                *) printf 'hostfakesplit' ;;
            esac
            ;;
        multidisorder) printf 'multidisorder' ;;
        syndata) printf 'syndata' ;;
        oob) printf 'oob' ;;
        drop) printf 'drop' ;;
        *) printf '%s' "${step%%:*}" ;;
    esac
}

builder_guess_label() {
    local step1="${1:-}"
    local step2="${2:-}"
    local step3="${3:-}"
    local label=""
    local step=""
    for step in "$step1" "$step2" "$step3"; do
        [ -n "$step" ] || continue
        label="${label}${label:+ + }$(builder_humanize_step "$step")"
    done
    printf '%s\n' "$label"
}

builder_csv_normalize() {
    printf '%s' "$1" | tr ',' '\n' | sed '/^$/d' | awk '
        !seen[$0]++ {
            out = out (out ? "," : "") $0
        }
        END {
            printf "%s", out
        }
    '
}

builder_csv_merge() {
    local merged=""
    local item=""
    local value=""
    for value in "$@"; do
        [ -n "$value" ] || continue
        local oldifs="$IFS"
        IFS=','
        for item in $value; do
            [ -n "$item" ] || continue
            merged="${merged}${merged:+,}${item}"
        done
        IFS="$oldifs"
    done
    builder_csv_normalize "$merged"
}

builder_step_features() {
    local step="$1"
    local op="${step%%:*}"
    local features="$op"
    case "$step" in
        *blob=fake_default_tls*|*blob=fake_tls*) features="$(builder_csv_merge "$features" "fake_payload")" ;;
        *blob=custom*|*seqovl_pattern=custom*) features="$(builder_csv_merge "$features" "custom_payload")" ;;
        *blob=0x1603*) features="$(builder_csv_merge "$features" "short_tls_blob")" ;;
    esac
    case "$step" in
        *tcp_md5*) features="$(builder_csv_merge "$features" "md5")" ;;
        *seqovl=*|*seqovl_pattern=*) features="$(builder_csv_merge "$features" "seqovl")" ;;
        *disorder_after*) features="$(builder_csv_merge "$features" "disorder_after")" ;;
        *tcp_ts=*|*tcp_ts_up*) features="$(builder_csv_merge "$features" "ts")" ;;
        *tcp_seq=*) features="$(builder_csv_merge "$features" "badseq")" ;;
        *tcp_ack=*) features="$(builder_csv_merge "$features" "badack")" ;;
        *autottl*) features="$(builder_csv_merge "$features" "autottl")" ;;
        *repeats=2*) features="$(builder_csv_merge "$features" "repeat2")" ;;
        *repeats=3*) features="$(builder_csv_merge "$features" "repeat3")" ;;
        *repeats=*) features="$(builder_csv_merge "$features" "repeatN")" ;;
        *sniext+4*) features="$(builder_csv_merge "$features" "sniext4")" ;;
        *sniext+1*) features="$(builder_csv_merge "$features" "sniext1")" ;;
        *host+1*) features="$(builder_csv_merge "$features" "host1")" ;;
        *midsld*) features="$(builder_csv_merge "$features" "midsld")" ;;
        *endsld*) features="$(builder_csv_merge "$features" "endsld")" ;;
        *pos=2:nodrop*) features="$(builder_csv_merge "$features" "pos2_nodrop")" ;;
        *midhost=midsld*) features="$(builder_csv_merge "$features" "midhost")" ;;
        *nofake1*) features="$(builder_csv_merge "$features" "nofake1")" ;;
        *nofake2*) features="$(builder_csv_merge "$features" "nofake2")" ;;
        *wssize:wsize=1:scale=6*) features="$(builder_csv_merge "$features" "wssize")" ;;
        *tls_mod=*) features="$(builder_csv_merge "$features" "tls_mod")" ;;
    esac
    printf '%s\n' "$features"
}

builder_family_capabilities() {
    case "$1" in
        tcpseg) echo "tcpseg" ;;
        oob) echo "oob" ;;
        fake) echo "fake" ;;
        multisplit) echo "multisplit" ;;
        fakedsplit) echo "fakedsplit" ;;
        fakeddisorder) echo "fakeddisorder" ;;
        hostfakesplit) echo "hostfakesplit" ;;
        multidisorder) echo "multidisorder" ;;
        syndata) echo "syndata" ;;
        seqovl) echo "seqovl" ;;
        fake_multisplit) echo "fake,multisplit" ;;
        multisplit_fakeddisorder) echo "multisplit,fakeddisorder" ;;
        multisplit_fakedsplit) echo "multisplit,fakedsplit" ;;
        multisplit_multidisorder) echo "multisplit,multidisorder" ;;
        fake_fakeddisorder) echo "fake,fakeddisorder" ;;
        fake_fakedsplit) echo "fake,fakedsplit" ;;
        fake_hostfakesplit) echo "fake,hostfakesplit" ;;
        *) echo "$(builder_policy_family_id "$1")" ;;
    esac
}

builder_family_requirements() {
    case "$1" in
        tcpseg|oob|fake|multisplit|fakedsplit|fakeddisorder|hostfakesplit|multidisorder|syndata|seqovl) echo "" ;;
        fake_multisplit) echo "fake,multisplit" ;;
        multisplit_fakeddisorder) echo "multisplit,fakeddisorder" ;;
        multisplit_fakedsplit) echo "multisplit,fakedsplit" ;;
        multisplit_multidisorder) echo "multisplit,multidisorder" ;;
        fake_fakeddisorder) echo "fake,fakeddisorder" ;;
        fake_fakedsplit) echo "fake,fakedsplit" ;;
        fake_hostfakesplit) echo "fake,hostfakesplit" ;;
        *) echo "" ;;
    esac
}

builder_candidate_features() {
    local family="$1"
    shift
    local features=""
    local step=""
    features="$(builder_csv_merge "$features" "$family" "$(builder_family_capabilities "$family")")"
    for step in "$@"; do
        [ -n "$step" ] || continue
        features="$(builder_csv_merge "$features" "$(builder_step_features "$step")")"
    done
    printf '%s\n' "$features"
}

builder_candidate_risk_flags() {
    local blob_mode="$1"
    local repeats="$2"
    shift 2
    local risk=""
    local step=""
    [ "$blob_mode" = "custom" ] && risk="$(builder_csv_merge "$risk" "custom_blob")"
    case "$repeats" in
        ''|0|1|2) ;;
        *) risk="$(builder_csv_merge "$risk" "high_repeat")" ;;
    esac
    for step in "$@"; do
        [ -n "$step" ] || continue
        case "$step" in
            *seqovl=*|*seqovl_pattern=*) risk="$(builder_csv_merge "$risk" "seqovl")" ;;
            *tcp_md5*) risk="$(builder_csv_merge "$risk" "md5")" ;;
            *blob=custom*|*seqovl_pattern=custom*) risk="$(builder_csv_merge "$risk" "custom_blob")" ;;
        esac
    done
    [ -n "${4:-}" ] && [ -n "${5:-}" ] && risk="$(builder_csv_merge "$risk" "complex_chain")"
    printf '%s\n' "$risk"
}

builder_candidate_cost_score() {
    local blob_mode="$1"
    local repeats="$2"
    shift 2
    local score=0
    local step=""
    case "$blob_mode" in
        custom) score=$((score + 2)) ;;
        fake_default_tls|fake_tls) score=$((score + 1)) ;;
    esac
    case "$repeats" in
        ''|0|1) ;;
        2) score=$((score + 1)) ;;
        *) score=$((score + 2)) ;;
    esac
    for step in "$@"; do
        [ -n "$step" ] || continue
        score=$((score + 1))
        case "$step" in
            *seqovl=*|*seqovl_pattern=*) score=$((score + 1)) ;;
            *autottl*) score=$((score + 1)) ;;
        esac
    done
    [ "$score" -gt 5 ] && score=5
    printf '%s\n' "$score"
}

builder_candidate_stability_hint() {
    case "$1" in
        fake|multisplit) echo "4" ;;
        fake_multisplit) echo "5" ;;
        hostfakesplit|fakeddisorder|multisplit_fakeddisorder) echo "3" ;;
        fakedsplit|multisplit_fakedsplit) echo "2" ;;
        multidisorder|multisplit_multidisorder) echo "1" ;;
        tcpseg|oob|syndata) echo "2" ;;
        fake_fakeddisorder|fake_fakedsplit|fake_hostfakesplit) echo "3" ;;
        seqovl) echo "1" ;;
        *) echo "2" ;;
    esac
}

builder_candidate_diversity_key() {
    local family="$1"
    local capabilities="$2"
    local core=""
    case ",$capabilities," in
        *,fake,*) core="fake" ;;
    esac
    case ",$capabilities," in
        *,multisplit,*) core="${core}${core:+_}multisplit" ;;
        *,fakeddisorder,*) core="${core}${core:+_}fakeddisorder" ;;
        *,hostfakesplit,*) core="${core}${core:+_}hostfakesplit" ;;
        *,fakedsplit,*) core="${core}${core:+_}fakedsplit" ;;
        *,multidisorder,*) core="${core}${core:+_}multidisorder" ;;
        *,tcpseg,*) core="${core}${core:+_}tcpseg" ;;
        *,oob,*) core="${core}${core:+_}oob" ;;
        *,syndata,*) core="${core}${core:+_}syndata" ;;
        *,seqovl,*) core="${core}${core:+_}seqovl" ;;
    esac
    [ -n "$core" ] || core="$(builder_policy_family_id "$family")"
    printf '%s|%s\n' "$(builder_policy_family_id "$family")" "$core"
}

builder_csv_has() {
    case ",$1," in
        *",$2,"*) return 0 ;;
    esac
    return 1
}

builder_candidate_anchor_pos() {
    local features="$1"
    if builder_csv_has "$features" "sniext4"; then
        echo "sniext+4"
    elif builder_csv_has "$features" "sniext1"; then
        echo "sniext+1"
    elif builder_csv_has "$features" "endsld"; then
        echo "endsld"
    elif builder_csv_has "$features" "midsld"; then
        echo "midsld"
    else
        echo ""
    fi
}

builder_candidate_anchor_multisplit_pos() {
    local features="$1"
    if builder_csv_has "$features" "pos2_nodrop"; then
        echo "2:nodrop"
    else
        echo "1"
    fi
}

builder_candidate_anchor_ts() {
    local step
    for step in "${STEP1:-}" "${STEP2:-}" "${STEP3:-}"; do
        case "$step" in
            *tcp_ts=*)
                printf '%s\n' "$step" | sed -n 's/.*tcp_ts=\(-\?[0-9][0-9]*\).*/\1/p'
                return 0
                ;;
        esac
    done
    printf '%s\n' "-1000"
}

builder_candidate_anchor_seq() {
    local step
    for step in "${STEP1:-}" "${STEP2:-}" "${STEP3:-}"; do
        case "$step" in
            *tcp_seq=*)
                printf '%s\n' "$step" | sed -n 's/.*tcp_seq=\(-\?[0-9][0-9]*\).*/\1/p'
                return 0
                ;;
        esac
    done
    printf '%s\n' "-3000"
}

builder_candidate_anchor_blob() {
    if [ -n "${BLOB_MODE:-}" ]; then
        printf '%s\n' "$BLOB_MODE"
    else
        printf '%s\n' "fake_default_tls"
    fi
}

builder_register_candidate() {
    local profile="$1"
    local family="$2"
    local blob_mode="$3"
    local position_params="$4"
    local tcp_modifiers="$5"
    local repeats="$6"
    local constraints="$7"
    local phase="$8"
    local priority="$9"
    local origin="${10}"
    local parent="${11}"
    local step1="${12}"
    local step2="${13}"
    local step3="${14}"
    local label="${15:-}"
    local capabilities="${16:-}"
    local requires="${17:-}"
    local features="${18:-}"
    local risk_flags="${19:-}"
    local cost_score="${20:-}"
    local stability_hint="${21:-}"
    local diversity_key="${22:-}"
    local candidate_id sig existing

    [ -n "$step1" ] || return 1
    sig="$(builder_candidate_signature "$step1" "$step2" "$step3")"
    existing="$(builder_find_candidate_by_signature "$profile" "$sig" 2>/dev/null || true)"
    if [ -n "$existing" ]; then
        printf '%s\n' "$existing"
        return 0
    fi

    candidate_id="$(builder_next_candidate_id "$profile")"
    [ -n "$label" ] || label="$(builder_guess_label "$step1" "$step2" "$step3")"
    [ -n "$capabilities" ] || capabilities="$(builder_family_capabilities "$family")"
    [ -n "$requires" ] || requires="$(builder_family_requirements "$family")"
    [ -n "$features" ] || features="$(builder_candidate_features "$family" "$step1" "$step2" "$step3")"
    [ -n "$risk_flags" ] || risk_flags="$(builder_candidate_risk_flags "$blob_mode" "$repeats" "$step1" "$step2" "$step3")"
    [ -n "$cost_score" ] || cost_score="$(builder_candidate_cost_score "$blob_mode" "$repeats" "$step1" "$step2" "$step3")"
    [ -n "$stability_hint" ] || stability_hint="$(builder_candidate_stability_hint "$family")"
    capabilities="$(builder_csv_normalize "$capabilities")"
    requires="$(builder_csv_normalize "$requires")"
    features="$(builder_csv_normalize "$features")"
    risk_flags="$(builder_csv_normalize "$risk_flags")"
    [ -n "$diversity_key" ] || diversity_key="$(builder_candidate_diversity_key "$family" "$capabilities")"
    builder_write_definition "$profile" "$candidate_id" "$family" "$label" "$blob_mode" \
        "$position_params" "$tcp_modifiers" "$repeats" "$constraints" \
        "$(printf '%s,%s,%s' "$step1" "$step2" "$step3" | sed 's/,,*/,/g; s/,$//; s/^,//')" \
        "$step1" "$step2" "$step3" "$capabilities" "$requires" "$features" \
        "$risk_flags" "$cost_score" "$stability_hint" "$diversity_key"
    cat >> "$(builder_candidate_file "$profile" "$candidate_id")" <<EOF
PHASE='$(builder_escape_env "$phase")'
PRIORITY='$(builder_escape_env "$priority")'
PARENT='$(builder_escape_env "$parent")'
FEATURE_SIGNATURE='$(builder_escape_env "$sig")'
EOF
    printf '%s\n' "$candidate_id"
}

builder_generate_cached_candidates() {
    local profile="$1"
    local knowledge_file
    local family blob_mode position_params tcp_modifiers repeats constraints desync_steps step1 step2 step3 label score elapsed verdict phase capabilities requires features risk_flags cost_score stability_hint diversity_key
    local oldifs

    knowledge_file="$(builder_knowledge_file "$profile")"
    [ -f "$knowledge_file" ] || return 0

    oldifs="$IFS"
    while IFS=$'\t' read -r family blob_mode position_params tcp_modifiers repeats constraints desync_steps step1 step2 step3 label score elapsed verdict phase capabilities requires features risk_flags cost_score stability_hint diversity_key; do
        [ -n "$family" ] || continue
        case "$verdict" in
            valid|unstable) ;;
            *) continue ;;
        esac
        builder_register_candidate "$profile" \
            "$family" "$blob_mode" "$position_params" "$tcp_modifiers" "$repeats" \
            "$constraints" "cached" "200" "learned" "" \
            "$step1" "$step2" "$step3" "$label" "$capabilities" "$requires" "$features" \
            "$risk_flags" "$cost_score" "$stability_hint" "$diversity_key" >/dev/null
    done < "$knowledge_file"
    IFS="$oldifs"
}

builder_generate_feature_optimizations() {
    local profile="$1"
    local family="$2"
    local base_candidate="$3"
    local anchor_pos="" anchor_multi="" anchor_blob="" anchor_ts="" anchor_seq="" generated=0

    builder_load_definition "$profile" "$base_candidate" || return 1
    anchor_pos="$(builder_candidate_anchor_pos "${FEATURES:-}")"
    anchor_multi="$(builder_candidate_anchor_multisplit_pos "${FEATURES:-}")"
    anchor_blob="$(builder_candidate_anchor_blob)"
    anchor_ts="$(builder_candidate_anchor_ts)"
    anchor_seq="$(builder_candidate_anchor_seq)"

    case "$family" in
        fake_multisplit)
            [ -n "$anchor_pos" ] || anchor_pos="midsld"
            builder_register_candidate "$profile" "$family" "$anchor_blob" "1,$anchor_pos" "tcp_ts=$anchor_ts" "${REPEATS:-2}" \
                "tls_client_hello" "optimize" "125" "generated" "$base_candidate" \
                "fake:blob=$anchor_blob:tcp_ts=$anchor_ts:repeats=${REPEATS:-2}" \
                "multisplit:pos=1,$anchor_pos" "" \
                "Feature anchor fake + multisplit $anchor_pos ts$anchor_ts" >/dev/null
            generated=$((generated + 1))
            if [ "$anchor_ts" != "-500" ]; then
                builder_register_candidate "$profile" "$family" "$anchor_blob" "1,$anchor_pos" "tcp_ts=-500" "${REPEATS:-2}" \
                    "tls_client_hello" "optimize" "124" "generated" "$base_candidate" \
                    "fake:blob=$anchor_blob:tcp_ts=-500:repeats=${REPEATS:-2}" \
                    "multisplit:pos=1,$anchor_pos" "" \
                    "Feature anchor fake + multisplit $anchor_pos ts-500" >/dev/null
                generated=$((generated + 1))
            fi
            if [ "$anchor_ts" != "-1500" ]; then
                builder_register_candidate "$profile" "$family" "$anchor_blob" "1,$anchor_pos" "tcp_ts=-1500" "${REPEATS:-2}" \
                    "tls_client_hello" "optimize" "123" "generated" "$base_candidate" \
                    "fake:blob=$anchor_blob:tcp_ts=-1500:repeats=${REPEATS:-2}" \
                    "multisplit:pos=1,$anchor_pos" "" \
                    "Feature anchor fake + multisplit $anchor_pos ts-1500" >/dev/null
                generated=$((generated + 1))
            fi
            ;;
        multisplit_fakeddisorder)
            [ -n "$anchor_pos" ] || anchor_pos="midsld"
            builder_register_candidate "$profile" "$family" "$anchor_blob" "$anchor_multi|$anchor_pos" "tcp_ts=$anchor_ts" "" \
                "tls_client_hello" "optimize" "122" "generated" "$base_candidate" \
                "multisplit:blob=$anchor_blob:tcp_ts=$anchor_ts:pos=$anchor_multi" \
                "fakeddisorder:pos=$anchor_pos:tcp_ts=$anchor_ts" "" \
                "Feature anchor multisplit + fakeddisorder $anchor_pos ts$anchor_ts" >/dev/null
            generated=$((generated + 1))
            ;;
        multisplit_fakedsplit)
            [ -n "$anchor_pos" ] || anchor_pos="midsld"
            builder_register_candidate "$profile" "$family" "$anchor_blob" "$anchor_multi|$anchor_pos" "tcp_seq=$anchor_seq" "" \
                "tls_client_hello" "optimize" "121" "generated" "$base_candidate" \
                "multisplit:blob=$anchor_blob:tcp_seq=$anchor_seq:pos=$anchor_multi" \
                "fakedsplit:pos=$anchor_pos:tcp_seq=$anchor_seq" "" \
                "Feature anchor multisplit + fakedsplit $anchor_pos seq$anchor_seq" >/dev/null
            generated=$((generated + 1))
            ;;
        fake_fakeddisorder)
            [ -n "$anchor_pos" ] || anchor_pos="midsld"
            builder_register_candidate "$profile" "$family" "$anchor_blob" "$anchor_pos" "tcp_ts=$anchor_ts" "${REPEATS:-2}" \
                "tls_client_hello" "optimize" "120" "generated" "$base_candidate" \
                "fake:blob=$anchor_blob:tcp_ts=$anchor_ts:repeats=${REPEATS:-2}" \
                "fakeddisorder:pos=$anchor_pos:tcp_ts=$anchor_ts" "" \
                "Feature anchor fake + fakeddisorder $anchor_pos ts$anchor_ts" >/dev/null
            generated=$((generated + 1))
            ;;
        fake_fakedsplit)
            [ -n "$anchor_pos" ] || anchor_pos="midsld"
            builder_register_candidate "$profile" "$family" "$anchor_blob" "$anchor_pos" "tcp_seq=$anchor_seq" "${REPEATS:-2}" \
                "tls_client_hello" "optimize" "119" "generated" "$base_candidate" \
                "fake:blob=$anchor_blob:tcp_seq=$anchor_seq:repeats=${REPEATS:-2}" \
                "fakedsplit:pos=$anchor_pos:tcp_seq=$anchor_seq" "" \
                "Feature anchor fake + fakedsplit $anchor_pos seq$anchor_seq" >/dev/null
            generated=$((generated + 1))
            ;;
        hostfakesplit)
            if builder_csv_has "${FEATURES:-}" "autottl"; then
                builder_register_candidate "$profile" "$family" "" "" "tcp_ack=-66000:tcp_ts_up:ip_autottl=5,3-20:ip6_autottl=5,3-20" "" \
                    "tls_client_hello" "optimize" "120" "generated" "$base_candidate" \
                    "hostfakesplit:tcp_ack=-66000:tcp_ts_up:ip_autottl=5,3-20:ip6_autottl=5,3-20" \
                    "" "" \
                    "Feature anchor hostfakesplit autottl" >/dev/null
                generated=$((generated + 1))
            fi
            if builder_csv_has "${FEATURES:-}" "badack" || builder_csv_has "${FEATURES:-}" "ts"; then
                builder_register_candidate "$profile" "$family" "" "" "disorder_after:tcp_ack=-66000:tcp_ts_up" "" \
                    "tls_client_hello" "optimize" "119" "generated" "$base_candidate" \
                    "hostfakesplit:disorder_after:tcp_ack=-66000:tcp_ts_up" \
                    "" "" \
                    "Feature anchor hostfakesplit disorder_after" >/dev/null
                generated=$((generated + 1))
            fi
            ;;
        fake_hostfakesplit)
            builder_register_candidate "$profile" "$family" "$anchor_blob" "" "tcp_ack=-66000:tcp_ts_up" "${REPEATS:-2}" \
                "tls_client_hello" "optimize" "118" "generated" "$base_candidate" \
                "fake:blob=$anchor_blob:tcp_ts=$anchor_ts:repeats=${REPEATS:-2}" \
                "hostfakesplit:disorder_after:midhost=midsld:tcp_ack=-66000:tcp_ts_up:repeats=${REPEATS:-2}" "" \
                "Feature anchor fake + hostfakesplit midhost" >/dev/null
            generated=$((generated + 1))
            ;;
    esac

    printf '%s\n' "$generated"
}

builder_generate_family_optimizations() {
    local profile="$1"
    local family="$2"
    local base_candidate="$3"

    case "$family" in
        fake_multisplit)
            builder_register_candidate "$profile" "$family" "fake_default_tls" "1,midsld" "tcp_ts=-500" "2" \
                "tls_client_hello" "optimize" "120" "generated" "$base_candidate" \
                "fake:blob=fake_default_tls:tcp_ts=-500:repeats=2" \
                "multisplit:pos=1,midsld" "" \
                "Fake + multisplit midsld ts-500" >/dev/null
            builder_register_candidate "$profile" "$family" "fake_default_tls" "1,midsld" "tcp_ts=-1500" "2" \
                "tls_client_hello" "optimize" "119" "generated" "$base_candidate" \
                "fake:blob=fake_default_tls:tcp_ts=-1500:repeats=2" \
                "multisplit:pos=1,midsld" "" \
                "Fake + multisplit midsld ts-1500" >/dev/null
            builder_register_candidate "$profile" "$family" "fake_default_tls" "1,sniext+1" "tcp_ts=-1000" "2" \
                "tls_client_hello" "optimize" "118" "generated" "$base_candidate" \
                "fake:blob=fake_default_tls:tcp_ts=-1000:repeats=2" \
                "multisplit:pos=1,sniext+1" "" \
                "Fake + multisplit sniext+1 ts-1000" >/dev/null
            builder_register_candidate "$profile" "$family" "fake_default_tls" "1,endsld" "tcp_ts=-1000" "2" \
                "tls_client_hello" "optimize" "117" "generated" "$base_candidate" \
                "fake:blob=fake_default_tls:tcp_ts=-1000:repeats=2" \
                "multisplit:pos=1,endsld" "" \
                "Fake + multisplit endsld ts-1000" >/dev/null
            builder_register_candidate "$profile" "$family" "fake_default_tls" "1,midsld" "tcp_ts=-1000" "3" \
                "tls_client_hello" "optimize" "116" "generated" "$base_candidate" \
                "fake:blob=fake_default_tls:tcp_ts=-1000:repeats=3" \
                "multisplit:pos=1,midsld" "" \
                "Fake + multisplit midsld ts-1000 x3" >/dev/null
            ;;
        multisplit_fakeddisorder)
            builder_register_candidate "$profile" "$family" "fake_default_tls" "2:nodrop|midsld" "tcp_ts=-1000" "" \
                "tls_client_hello" "optimize" "115" "generated" "$base_candidate" \
                "multisplit:blob=fake_default_tls:tcp_ts=-1000:pos=2:nodrop" \
                "fakeddisorder:pos=midsld:tcp_ts=-1000" "" \
                "Multisplit + fakeddisorder midsld ts-1000" >/dev/null
            builder_register_candidate "$profile" "$family" "fake_default_tls" "2:nodrop|sniext+1" "tcp_ts=-1000" "" \
                "tls_client_hello" "optimize" "114" "generated" "$base_candidate" \
                "multisplit:blob=fake_default_tls:tcp_ts=-1000:pos=2:nodrop" \
                "fakeddisorder:pos=sniext+1:tcp_ts=-1000" "" \
                "Multisplit + fakeddisorder sniext+1 ts-1000" >/dev/null
            builder_register_candidate "$profile" "$family" "fake_default_tls" "2:nodrop|endsld" "tcp_ts=-1000" "" \
                "tls_client_hello" "optimize" "113" "generated" "$base_candidate" \
                "multisplit:blob=fake_default_tls:tcp_ts=-1000:pos=2:nodrop" \
                "fakeddisorder:pos=endsld:tcp_ts=-1000" "" \
                "Multisplit + fakeddisorder endsld ts-1000" >/dev/null
            ;;
        hostfakesplit)
            builder_register_candidate "$profile" "$family" "" "" "tcp_ack=-66000:tcp_ts_up:ip_autottl=5,3-20:ip6_autottl=5,3-20" "" \
                "tls_client_hello" "optimize" "112" "generated" "$base_candidate" \
                "hostfakesplit:tcp_ack=-66000:tcp_ts_up:ip_autottl=5,3-20:ip6_autottl=5,3-20" \
                "" "" \
                "Hostfakesplit ack ts_up autottl" >/dev/null
            builder_register_candidate "$profile" "$family" "" "" "disorder_after:tcp_ack=-66000:tcp_ts_up" "" \
                "tls_client_hello" "optimize" "111" "generated" "$base_candidate" \
                "hostfakesplit:disorder_after:tcp_ack=-66000:tcp_ts_up" \
                "" "" \
                "Hostfakesplit disorder_after ack ts_up" >/dev/null
            ;;
        multisplit_fakedsplit)
            builder_register_candidate "$profile" "$family" "fake_default_tls" "2:nodrop|midsld" "tcp_ts=-1000" "" \
                "tls_client_hello" "optimize" "110" "generated" "$base_candidate" \
                "multisplit:blob=fake_default_tls:tcp_ts=-1000:pos=2:nodrop" \
                "fakedsplit:pos=midsld:tcp_ts=-1000" "" \
                "Multisplit + fakedsplit midsld ts-1000" >/dev/null
            ;;
        fake_fakeddisorder)
            builder_register_candidate "$profile" "$family" "fake_default_tls" "midsld" "tcp_ts=-1000" "2" \
                "tls_client_hello" "optimize" "109" "generated" "$base_candidate" \
                "fake:blob=fake_default_tls:tcp_ts=-1000:repeats=2" \
                "fakeddisorder:pos=midsld:tcp_ts=-1000" "" \
                "Fake + fakeddisorder midsld ts-1000" >/dev/null
            builder_register_candidate "$profile" "$family" "fake_default_tls" "sniext+4" "tcp_ts=-1000" "2" \
                "tls_client_hello" "optimize" "108" "generated" "$base_candidate" \
                "fake:blob=fake_default_tls:tcp_ts=-1000:repeats=2" \
                "fakeddisorder:pos=sniext+4:tcp_ts=-1000" "" \
                "Fake + fakeddisorder sniext+4 ts-1000" >/dev/null
            ;;
        fake_fakedsplit)
            builder_register_candidate "$profile" "$family" "fake_default_tls" "midsld" "tcp_seq=-3000" "2" \
                "tls_client_hello" "optimize" "107" "generated" "$base_candidate" \
                "fake:blob=fake_default_tls:tcp_seq=-3000:repeats=2" \
                "fakedsplit:pos=midsld:tcp_seq=-3000" "" \
                "Fake + fakedsplit seq-3000 midsld" >/dev/null
            ;;
        fake_hostfakesplit)
            builder_register_candidate "$profile" "$family" "fake_default_tls" "" "tcp_ack=-66000:tcp_ts_up" "2" \
                "tls_client_hello" "optimize" "106" "generated" "$base_candidate" \
                "fake:blob=fake_default_tls:tcp_ts=-1000:repeats=2" \
                "hostfakesplit:disorder_after:midhost=midsld:tcp_ack=-66000:tcp_ts_up:repeats=2" "" \
                "Fake + hostfakesplit midhost" >/dev/null
            builder_register_candidate "$profile" "$family" "fake_default_tls" "" "tcp_md5:ip_autottl=-1,3-20:ip6_autottl=-1,3-20" "2" \
                "tls_client_hello" "optimize" "105" "generated" "$base_candidate" \
                "fake:blob=fake_default_tls:tcp_ts=-1000:repeats=2" \
                "hostfakesplit:nofake1:midhost=midsld:tcp_md5:ip_autottl=-1,3-20:ip6_autottl=-1,3-20:repeats=2" "" \
                "Fake + hostfakesplit nofake1 md5" >/dev/null
            ;;
        multisplit_multidisorder)
            builder_register_candidate "$profile" "$family" "custom" "1,midsld" "seqovl=666:seqovl_pattern=custom" "" \
                "tls_client_hello" "optimize" "104" "generated" "$base_candidate" \
                "multisplit:seqovl=666:seqovl_pattern=custom" \
                "multidisorder:pos=1,host+2,sld+2,sld+5,sniext+1,sniext+2,endhost-2" "" \
                "Seqovl custom + multidisorder extended" >/dev/null
            ;;
    esac
}

builder_job_id() {
    printf 'job-%s-%s-%s\n' "$(date +%Y%m%d%H%M%S)" "$1" "$2"
}

builder_validation_job_file() {
    local profile="$1"
    local job_id="$2"
    printf '%s/%s.json\n' "$(builder_profile_dir "$profile")" "$job_id"
}

builder_write_definition() {
    local profile="$1"
    local candidate_id="$2"
    local family="$3"
    local label="$4"
    local blob_mode="$5"
    local position_params="$6"
    local tcp_modifiers="$7"
    local repeats="$8"
    local constraints="$9"
    local desync_steps="${10}"
    local step1="${11}"
    local step2="${12}"
    local step3="${13}"
    local capabilities="${14:-}"
    local requires="${15:-}"
    local features="${16:-}"
    local risk_flags="${17:-}"
    local cost_score="${18:-0}"
    local stability_hint="${19:-0}"
    local diversity_key="${20:-}"
    local host_scope
    local file

    host_scope="$(builder_profile_host_scope "$profile")"
    file="$(builder_candidate_file "$profile" "$candidate_id")"
    mkdir -p "$(dirname "$file")"
    cat > "$file" <<EOF
PROFILE_ID='$profile'
PROTO='tls'
FAMILY='$(builder_escape_env "$family")'
DESYNC_STEPS='$(builder_escape_env "$desync_steps")'
BLOB_MODE='$(builder_escape_env "$blob_mode")'
HOSTLIST_SCOPE='$(builder_escape_env "$host_scope")'
POSITION_PARAMS='$(builder_escape_env "$position_params")'
TCP_MODIFIERS='$(builder_escape_env "$tcp_modifiers")'
UDP_MODIFIERS=''
REPEATS='$(builder_escape_env "$repeats")'
CONSTRAINTS='$(builder_escape_env "$constraints")'
LABEL='$(builder_escape_env "$label")'
ORIGIN='generated'
STEP1='$(builder_escape_env "$step1")'
STEP2='$(builder_escape_env "$step2")'
STEP3='$(builder_escape_env "$step3")'
CAPABILITIES='$(builder_escape_env "$capabilities")'
REQUIRES='$(builder_escape_env "$requires")'
FEATURES='$(builder_escape_env "$features")'
RISK_FLAGS='$(builder_escape_env "$risk_flags")'
COST_SCORE='$(builder_escape_env "$cost_score")'
STABILITY_HINT='$(builder_escape_env "$stability_hint")'
DIVERSITY_KEY='$(builder_escape_env "$diversity_key")'
CANDIDATE_ID='$(builder_escape_env "$candidate_id")'
EOF
}

builder_seed_profile_candidates() {
    local profile="$1"
    if [ "${BUILDER_SEEDING_PROFILE:-}" = "$profile" ]; then
        return 0
    fi
    builder_profile_supported "$profile" || return 1
    builder_init_dirs
    BUILDER_SEEDING_PROFILE="$profile"

    builder_reset_profile_candidates "$profile"

    # Phase 0: previously successful candidates first.
    builder_generate_cached_candidates "$profile"

    # Phase 1: family representatives.
    builder_register_candidate "$profile" \
        "tcpseg" "" "" "ip_id=rnd" "20" \
        "tls_client_hello" "family_scan" "98" "generated" "" \
        "tcpseg:pos=0,1:ip_id=rnd:repeats=20" \
        "" "" \
        "Tcpseg 0,1 repeats20" >/dev/null
    builder_register_candidate "$profile" \
        "oob" "" "" "" "" \
        "tls_client_hello" "family_scan" "97" "generated" "" \
        "oob:urp=midsld" \
        "" "" \
        "OOB midsld" >/dev/null
    builder_register_candidate "$profile" \
        "fake" "fake_default_tls" "" "tcp_ts=-1000" "2" \
        "tls_client_hello" "family_scan" "96" "generated" "" \
        "fake:blob=fake_default_tls:tcp_ts=-1000:repeats=2" \
        "" "" \
        "Fake ts-1000" >/dev/null
    builder_register_candidate "$profile" \
        "syndata" "fake_default_tls" "" "" "" \
        "tls_client_hello" "family_scan" "95" "generated" "" \
        "syndata:blob=0x1603" \
        "" "" \
        "Syndata 0x1603" >/dev/null
    builder_register_candidate "$profile" \
        "fake_multisplit" "fake_default_tls" "1,midsld" "tcp_ts=-1000" "2" \
        "tls_client_hello" "family_scan" "82" "generated" "" \
        "fake:blob=fake_default_tls:tcp_ts=-1000:repeats=2" \
        "multisplit:pos=1,midsld" "" \
        "Fake + multisplit midsld ts-1000" >/dev/null
    builder_register_candidate "$profile" \
        "multisplit" "fake_default_tls" "2:nodrop" "tcp_ts=-500" "" \
        "tls_client_hello" "family_scan" "90" "generated" "" \
        "multisplit:blob=fake_default_tls:tcp_ts=-500:pos=2:nodrop" \
        "" "" \
        "Multisplit pos2 nodrop ts-500" >/dev/null
    builder_register_candidate "$profile" \
        "multidisorder" "" "1,sniext+1,host+1,midsld-2,midsld,midsld+2,endhost-1" "" "" \
        "tls_client_hello" "family_scan" "89" "generated" "" \
        "multidisorder:pos=1,sniext+1,host+1,midsld-2,midsld,midsld+2,endhost-1" \
        "" "" \
        "Multidisorder extended" >/dev/null
    builder_register_candidate "$profile" \
        "fakeddisorder" "fake_default_tls" "midsld" "tcp_ts=-1000" "" \
        "tls_client_hello" "family_scan" "88" "generated" "" \
        "fakeddisorder:pos=midsld:tcp_ts=-1000" \
        "" "" \
        "Fakeddisorder midsld ts-1000" >/dev/null
    builder_register_candidate "$profile" \
        "seqovl" "custom" "10,sniext+1" "seqovl=666:seqovl_pattern=custom" "" \
        "tls_client_hello" "family_scan" "87" "generated" "" \
        "multisplit:blob=custom:pos=10,sniext+1:seqovl=666:seqovl_pattern=custom" \
        "" "" \
        "Seqovl multisplit custom sniext+1" >/dev/null
    builder_register_candidate "$profile" \
        "multisplit_fakeddisorder" "fake_default_tls" "2:nodrop|midsld" "tcp_ts=-500" "" \
        "tls_client_hello" "family_scan" "68" "generated" "" \
        "multisplit:blob=fake_default_tls:tcp_ts=-500:pos=2:nodrop" \
        "fakeddisorder:pos=midsld:tcp_ts=-500" "" \
        "Multisplit + fakeddisorder midsld ts-500" >/dev/null
    builder_register_candidate "$profile" \
        "multisplit_fakeddisorder" "fake_default_tls" "2:nodrop|sniext+4" "tcp_ts=-1000" "" \
        "tls_client_hello" "family_scan" "84" "generated" "" \
        "multisplit:blob=fake_default_tls:tcp_ts=-1000:pos=2:nodrop" \
        "fakeddisorder:pos=sniext+4:tcp_ts=-1000" "" \
        "Multisplit + fakeddisorder sniext+4 ts-1000" >/dev/null
    builder_register_candidate "$profile" \
        "hostfakesplit" "" "" "tcp_ack=-66000:tcp_ts_up" "" \
        "tls_client_hello" "family_scan" "80" "generated" "" \
        "hostfakesplit:tcp_ack=-66000:tcp_ts_up" \
        "" "" \
        "Hostfakesplit ack ts_up" >/dev/null
    builder_register_candidate "$profile" \
        "hostfakesplit" "" "" "tcp_md5:ip_autottl=-1,3-20:ip6_autottl=-1,3-20" "" \
        "tls_client_hello" "family_scan" "78" "generated" "" \
        "hostfakesplit:tcp_md5:ip_autottl=-1,3-20:ip6_autottl=-1,3-20" \
        "" "" \
        "Hostfakesplit tcp_md5 autottl" >/dev/null
    builder_register_candidate "$profile" \
        "fakedsplit" "fake_default_tls" "midsld" "tcp_seq=-3000" "" \
        "tls_client_hello" "family_scan" "76" "generated" "" \
        "fakedsplit:pos=midsld:tcp_seq=-3000" \
        "" "" \
        "Fakedsplit seq-3000 midsld" >/dev/null
    builder_register_candidate "$profile" \
        "fake_fakeddisorder" "fake_default_tls" "midsld" "tcp_ts=-1000" "2" \
        "tls_client_hello" "family_scan" "74" "generated" "" \
        "fake:blob=fake_default_tls:tcp_ts=-1000:repeats=2" \
        "fakeddisorder:pos=midsld:tcp_ts=-1000" "" \
        "Fake + fakeddisorder midsld ts-1000" >/dev/null
    builder_register_candidate "$profile" \
        "fake_fakedsplit" "fake_default_tls" "midsld" "tcp_seq=-3000" "2" \
        "tls_client_hello" "family_scan" "73" "generated" "" \
        "fake:blob=fake_default_tls:tcp_seq=-3000:repeats=2" \
        "fakedsplit:pos=midsld:tcp_seq=-3000" "" \
        "Fake + fakedsplit seq-3000 midsld" >/dev/null
    builder_register_candidate "$profile" \
        "fake_hostfakesplit" "fake_default_tls" "" "tcp_ack=-66000:tcp_ts_up" "2" \
        "tls_client_hello" "family_scan" "72" "generated" "" \
        "fake:blob=fake_default_tls:tcp_ts=-1000:repeats=2" \
        "hostfakesplit:disorder_after:midhost=midsld:tcp_ack=-66000:tcp_ts_up:repeats=2" "" \
        "Fake + hostfakesplit midhost" >/dev/null
    builder_register_candidate "$profile" \
        "multisplit_fakedsplit" "fake_default_tls" "2:nodrop|midsld" "tcp_seq=-3000" "" \
        "tls_client_hello" "family_scan" "74" "generated" "" \
        "multisplit:blob=fake_default_tls:tcp_seq=-3000:pos=2:nodrop" \
        "fakedsplit:pos=midsld:tcp_seq=-3000" "" \
        "Multisplit + fakedsplit seq-3000 midsld" >/dev/null
    builder_register_candidate "$profile" \
        "multisplit_multidisorder" "custom" "1,midsld" "seqovl=666:seqovl_pattern=custom" "" \
        "tls_client_hello" "family_scan" "70" "generated" "" \
        "multisplit:seqovl=666:seqovl_pattern=custom" \
        "multidisorder:pos=1,midsld" "" \
        "Seqovl custom + multidisorder" >/dev/null

    builder_sync_policy_catalog "$profile"
    builder_sync_policy_profile_state "$profile"
    builder_sync_webui_profile_cache "$profile"
    BUILDER_SEEDING_PROFILE=""
}

builder_load_definition() {
    local profile="$1"
    local candidate_id="$2"
    local file
    file="$(builder_candidate_file "$profile" "$candidate_id")"
    [ -f "$file" ] || return 1
    # shellcheck disable=SC1090
    . "$file"
}

builder_candidate_compile_line() {
    local strategy_num="$1"
    local line=""
    local step=""

    for step in "$STEP1" "$STEP2" "$STEP3"; do
        [ -n "$step" ] || continue
        if [ -n "$line" ]; then
            line="$line "
        fi
        line="${line}--lua-desync=${step}:strategy=${strategy_num}"
    done
    printf '%s\n' "$line"
}

builder_strip_generated_block() {
    local profile="$1"
    local src="$2"
    local dst="$3"
    awk -v profile="$profile" '
        BEGIN {skip=0}
        $0 ~ ("^# Z2R_BUILDER_BEGIN profile=" profile "$") {skip=1; next}
        $0 ~ ("^# Z2R_BUILDER_END profile=" profile "$") {skip=0; next}
        !skip {print}
    ' "$src" > "$dst"
}

builder_profile_max_strategy_from_cfg() {
    local profile="$1"
    local cfg="$2"
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

builder_profile_strategy_sequence_ok() {
    local profile="$1"
    local cfg="$2"
    awk -v pid="$profile" '
        BEGIN{inopt=0; prof=1}
        /^NFQWS2_OPT="/ {inopt=1}
        inopt {
            if ($0 ~ /^--new/) {prof++}
            if (prof==pid) {
                line=$0
                while (match(line, /strategy=[0-9]+/)) {
                    num=substr(line, RSTART+9, RLENGTH-9)+0
                    uniq[num]=1
                    if (num>max) max=num
                    line=substr(line, RSTART+RLENGTH)
                }
            }
            if ($0 ~ /^"$/) {exit}
        }
        END{
            if (max == 0) exit 0
            for (i=1; i<=max; i++) {
                if (!(i in uniq)) exit 1
            }
            exit 0
        }
    ' "$cfg"
}

builder_insert_generated_block() {
    local profile="$1"
    local candidate_id="$2"
    local strategy_num="$3"
    local lines_file="$4"
    local src="$5"
    local dst="$6"

    awk -v pid="$profile" -v cid="$candidate_id" -v snum="$strategy_num" -v lines="$lines_file" '
        function emit_block() {
            if (inserted) return
            print "# Z2R_BUILDER_BEGIN profile=" pid
            while ((getline row < lines) > 0) print row
            close(lines)
            print "# Z2R_BUILDER_END profile=" pid
            inserted=1
        }
        BEGIN {inopt=0; prof=1; inserted=0}
        {
            if ($0 ~ /^NFQWS2_OPT="/) inopt=1
            if (inopt && prof==pid && ($0 ~ /^--new/ || $0 ~ /^"$/)) emit_block()
            print
            if (inopt && $0 ~ /^--new/) prof++
        }
        END {
            if (!inserted) exit 1
        }
    ' "$src" > "$dst"
}

builder_restore_lock() {
    local profile="$1"
    local proto="$2"
    local prev="$3"
    if type orch_locked_set >/dev/null 2>&1; then
        if printf '%s' "$prev" | grep -Eq '^[0-9]+$' && [ "$prev" -gt 0 ]; then
            orch_locked_set "$profile" "$proto" "$prev"
        elif type orch_locked_clear >/dev/null 2>&1; then
            orch_locked_clear "$profile" "$proto"
        fi
    fi
}

builder_restart_if_possible() {
    if type restart_zapret2 >/dev/null 2>&1; then
        restart_zapret2 >/dev/null 2>&1 || true
    elif [ -n "${ZAPRET2_INIT:-}" ] && [ -f "${ZAPRET2_INIT:-}" ]; then
        "$ZAPRET2_INIT" restart >/dev/null 2>&1 || true
    fi
}

builder_state_snapshot_file() {
    printf '%s/profile-%s.json\n' "$(builder_runtime_backup_dir "$1")" "$1"
}

builder_domain_snapshot_file() {
    printf '%s/domain-%s.json\n' "$(builder_runtime_backup_dir "$1")" "$(builder_profile_host_scope "$1")"
}

builder_capture_runtime_state() {
    local profile="$1"
    local runtime_dir profile_file domain_file hostkey
    runtime_dir="$(builder_runtime_backup_dir "$profile")"
    profile_file="$(builder_state_snapshot_file "$profile")"
    domain_file="$(builder_domain_snapshot_file "$profile")"
    hostkey="$(builder_profile_host_scope "$profile")"
    mkdir -p "$runtime_dir"
    if builder_policy_runtime_enabled "$profile"; then
        policy_read_profile_state "$profile" > "$profile_file" 2>/dev/null || : > "$profile_file"
        policy_read_domain_state "$hostkey" > "$domain_file" 2>/dev/null || : > "$domain_file"
    fi
}

builder_restore_runtime_state() {
    local profile="$1"
    local profile_file domain_file hostkey
    profile_file="$(builder_state_snapshot_file "$profile")"
    domain_file="$(builder_domain_snapshot_file "$profile")"
    hostkey="$(builder_profile_host_scope "$profile")"
    if builder_policy_runtime_enabled "$profile"; then
        if [ -s "$profile_file" ]; then
            policy_write_profile_state "$profile" "$profile_file" || true
        fi
        if [ -s "$domain_file" ]; then
            policy_write_domain_state "$hostkey" "$domain_file" || true
        fi
        policy_rebuild_runtime_snapshot >/dev/null 2>&1 || true
    fi
}

builder_apply_candidate_state() {
    local profile="$1"
    local candidate_id="$2"
    local mode="${3:-persist}"
    local hostkey policy_candidate family_id chosen updated_at json_file domain_file
    local active_file

    if ! builder_load_definition "$profile" "$candidate_id" >/dev/null 2>&1; then
        builder_seed_profile_candidates "$profile" || return 1
    fi
    builder_load_definition "$profile" "$candidate_id" || return 1
    policy_candidate="$(builder_policy_candidate_id "$profile" "$candidate_id")"
    family_id="$(builder_policy_family_id "${FAMILY:-unknown}")"
    chosen="$([ "$mode" = "persist" ] && echo 1 || echo 0)"
    updated_at="$(date +%Y-%m-%dT%H:%M:%S%z)"
    hostkey="$(builder_profile_host_scope "$profile")"
    json_file="$(mktemp)"
    domain_file="$(mktemp)"

    cat > "$json_file" <<EOF
{
  "profile": $profile,
  "mode": "$([ "$mode" = "persist" ] && echo manual_fixed || echo discovery_testing)",
  "active_candidate_id": "$(builder_json_escape "$policy_candidate")",
  "active_family_id": "$(builder_json_escape "$family_id")",
  "status": "$([ "$mode" = "persist" ] && echo known_good || echo testing)",
  "confidence": $([ "$mode" = "persist" ] && echo 0.95 || echo 0.5),
  "pending_job_id": "",
  "fallback_chain": [],
  "last_validated_at": "$(builder_json_escape "$updated_at")",
  "source": "$([ "$mode" = "persist" ] && echo manual_apply || echo discovery_apply)"
}
EOF
    cat > "$domain_file" <<EOF
{
  "host": "$(builder_json_escape "$hostkey")",
  "group_key": "$(builder_json_escape "$hostkey")",
  "profile": $profile,
  "active_candidate_id": "$(builder_json_escape "$policy_candidate")",
  "status": "$([ "$mode" = "persist" ] && echo known_good || echo testing)",
  "confidence": $([ "$mode" = "persist" ] && echo 0.95 || echo 0.5),
  "blocked_candidates": [],
  "unstable_candidates": [],
  "last_success_at": "",
  "last_failure_at": ""
}
EOF

    policy_write_profile_state "$profile" "$json_file" || {
        rm -f "$json_file" "$domain_file"
        return 1
    }
    policy_write_domain_state "$hostkey" "$domain_file" || {
        rm -f "$json_file" "$domain_file"
        return 1
    }
    policy_rebuild_runtime_snapshot >/dev/null 2>&1 || true

    if [ "$mode" = "persist" ]; then
        active_file="$(builder_active_file "$profile")"
        mkdir -p "$(dirname "$active_file")"
        cat > "$active_file" <<EOF
PROFILE_ID='$profile'
CANDIDATE_ID='$(builder_escape_env "$candidate_id")'
STRATEGY_NUM='state'
TARGET_PROFILE='$(builder_escape_env "$profile")'
LABEL='$(builder_escape_env "$LABEL")'
CHOSEN='1'
UPDATED_AT='$(date '+%Y-%m-%d %H:%M:%S')'
EOF
    fi

    builder_sync_webui_profile_cache "$profile"
    rm -f "$json_file" "$domain_file"
    printf 'state\n'
}

builder_apply_candidate() {
    local profile="$1"
    local candidate_id="$2"
    local mode="${3:-persist}"
    local cfg cleaned tmp lines_file max strategy_num active_file lock_proto

    if builder_policy_runtime_enabled "$profile"; then
        builder_apply_candidate_state "$profile" "$candidate_id" "$mode"
        return $?
    fi

    if ! builder_load_definition "$profile" "$candidate_id" >/dev/null 2>&1; then
        builder_seed_profile_candidates "$profile" || return 1
    fi
    builder_load_definition "$profile" "$candidate_id" || return 1

    cfg="$(builder_current_config_file)"
    [ -f "$cfg" ] || return 1

    cleaned="$(mktemp)"
    lines_file="$(mktemp)"
    tmp="$(mktemp)"

    builder_strip_generated_block "$profile" "$cfg" "$cleaned" || {
        rm -f "$cleaned" "$lines_file" "$tmp"
        return 1
    }

    builder_profile_strategy_sequence_ok "$profile" "$cleaned" || {
        rm -f "$cleaned" "$lines_file" "$tmp"
        return 1
    }

    max="$(builder_profile_max_strategy_from_cfg "$profile" "$cleaned")"
    [ -n "$max" ] || max=0
    strategy_num=$((max + 1))
    builder_candidate_compile_line "$strategy_num" > "$lines_file"

    builder_insert_generated_block "$profile" "$candidate_id" "$strategy_num" "$lines_file" "$cleaned" "$tmp" || {
        rm -f "$cleaned" "$lines_file" "$tmp"
        return 1
    }
    mv "$tmp" "$cfg"

    if type orch_locked_set >/dev/null 2>&1; then
        for lock_proto in $(builder_profile_lock_protos "$profile"); do
            [ -n "$lock_proto" ] || continue
            orch_locked_set "$profile" "$lock_proto" "$strategy_num"
        done
    fi
    if type sync_orchestra >/dev/null 2>&1; then
        sync_orchestra >/dev/null 2>&1 || true
    fi

    if [ "$mode" = "persist" ]; then
        active_file="$(builder_active_file "$profile")"
        mkdir -p "$(dirname "$active_file")"
        cat > "$active_file" <<EOF
PROFILE_ID='$profile'
CANDIDATE_ID='$(builder_escape_env "$candidate_id")'
STRATEGY_NUM='$strategy_num'
TARGET_PROFILE='$(builder_escape_env "$profile")'
LABEL='$(builder_escape_env "$LABEL")'
CHOSEN='1'
UPDATED_AT='$(date '+%Y-%m-%d %H:%M:%S')'
EOF
    fi

    builder_sync_policy_profile_state "$profile"
    if type policy_rebuild_runtime_snapshot >/dev/null 2>&1; then
        policy_rebuild_runtime_snapshot >/dev/null 2>&1 || true
    fi
    builder_sync_webui_profile_cache "$profile"

    builder_restart_if_possible
    rm -f "$cleaned" "$lines_file"
    printf '%s\n' "$strategy_num"
}

builder_probe_target() {
    local target="$1"
    local profile="${2:-0}"
    local candidate_id="${3:-}"
    local host="${4:-}"
    local repeats="${5:-2}"
    local timeout_sec="${6:-4}"
    local source="${7:-builder_discovery}"
    local job_id job_file done_file result_json score elapsed verdict reason dns_host
    local dns_state baseline_state tls12_ok tls13_ok long_get_ok failure_class confidence transport_ok

    if ! type policy_enqueue_job >/dev/null 2>&1 || ! type validator_validate_candidate >/dev/null 2>&1; then
        printf '0\t0\tinconclusive\tvalidator_unavailable\t%s\n' "$target"
        return 0
    fi

    dns_host="$(builder_profile_dns_host "$profile")"
    [ -n "$dns_host" ] || dns_host="$host"

    job_id="$(builder_job_id "$profile" "$candidate_id")"
    job_file="$(builder_validation_job_file "$profile" "$job_id")"
    cat > "$job_file" <<EOF
{
  "job_id": "$(builder_json_escape "$job_id")",
  "type": "validate_candidate",
  "source": "$(builder_json_escape "$source")",
  "profile": $profile,
  "hosts": ["$(builder_json_escape "$host")"],
  "dns_host": "$(builder_json_escape "$dns_host")",
  "candidate_id": "$(builder_json_escape "$(builder_policy_candidate_id "$profile" "$candidate_id")")",
  "target_url": "$(builder_json_escape "$target")",
  "reference_url": "https://example.com/",
  "checks": {
    "baseline": true,
    "tls12": true,
    "tls13": true,
    "long_get": true,
    "dns_check": true,
    "ip_block_check": true,
    "quic": false
  },
  "repeats": ${repeats:-2},
  "timeout_sec": ${timeout_sec:-4},
  "created_at": "$(date +%Y-%m-%dT%H:%M:%S%z)"
}
EOF
    policy_enqueue_job "$job_file" || {
        rm -f "$job_file"
        printf '0\t0\tinconclusive\tenqueue_failed\t%s\n' "$target"
        return 1
    }
    rm -f "$job_file"

    if [ -f "$builder_validator_daemon" ]; then
        env \
            policy_root="$policy_root" \
            validator_policy_store_module="$builder_policy_store_module" \
            validator_netcheck_module="${validator_netcheck_module:-/opt/zapret2/z2r_lib/netcheck.sh}" \
            POLICY_STORE_MODULE="$builder_policy_store_module" \
            VALIDATOR_MODULE="$builder_validator_module" \
            bash "$builder_validator_daemon" once >/dev/null 2>&1 || true
    fi

    done_file="$policy_jobs_done_root/${job_id}.json"
    [ -f "$done_file" ] || done_file="$policy_jobs_failed_root/${job_id}.json"
    if [ ! -f "$done_file" ]; then
        printf '0\t0\tinconclusive\tmissing_result\t%s\n' "$target"
        return 1
    fi

    result_json="$done_file"
    score="$(validator_json_get_number "$result_json" "score" 2>/dev/null || echo 0)"
    elapsed="$(validator_json_get_number "$result_json" "elapsed_ms" 2>/dev/null || echo 0)"
    verdict="$(validator_json_get_string "$result_json" "verdict" 2>/dev/null || echo inconclusive)"
    dns_state="$(validator_json_get_string "$result_json" "dns_state" 2>/dev/null || echo unknown)"
    baseline_state="$(validator_json_get_string "$result_json" "baseline_state" 2>/dev/null || echo unknown)"
    tls12_ok="$(validator_json_get_number "$result_json" "tls12_ok" 2>/dev/null || echo 0)"
    tls13_ok="$(validator_json_get_number "$result_json" "tls13_ok" 2>/dev/null || echo 0)"
    long_get_ok="$(validator_json_get_number "$result_json" "long_get_ok" 2>/dev/null || echo 0)"
    failure_class="$(validator_json_get_string "$result_json" "failure_class" 2>/dev/null || echo inconclusive)"
    confidence="$(validator_json_get_number "$result_json" "confidence" 2>/dev/null || echo 0)"
    transport_ok="$(validator_json_get_bool "$result_json" "transport_ok" 2>/dev/null || echo false)"
    case "$verdict" in
        valid) reason="validator_valid" ;;
        unstable) reason="validator_unstable" ;;
        dns_poisoned) reason="dns_poisoned" ;;
        transport_blocked) reason="transport_blocked" ;;
        invalid) reason="validator_invalid" ;;
        *) reason="validator_inconclusive" ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$score" "$elapsed" "$verdict" "$reason" "$target" \
        "$dns_state" "$baseline_state" "$tls12_ok" "$tls13_ok" "$long_get_ok" \
        "$failure_class" "$confidence" "$transport_ok"
}

builder_restore_config_and_state() {
    local cfg="$1"
    local backup_cfg="$2"
    local profile="$3"
    local prev_locks="$4"
    local prev_active="$5"
    local lock_proto="" lock_entry="" lock_value=""
    if builder_policy_runtime_enabled "$profile"; then
        builder_restore_runtime_state "$profile"
        if [ -n "$prev_active" ]; then
            mkdir -p "$(dirname "$(builder_active_file "$profile")")"
            printf '%s' "$prev_active" > "$(builder_active_file "$profile")"
        else
            rm -f "$(builder_active_file "$profile")"
        fi
        return 0
    fi
    mv "$backup_cfg" "$cfg"
    for lock_entry in $prev_locks; do
        lock_proto="${lock_entry%%=*}"
        lock_value="${lock_entry#*=}"
        [ -n "$lock_proto" ] || continue
        builder_restore_lock "$profile" "$lock_proto" "$lock_value"
    done
    if [ -n "$prev_active" ]; then
        mkdir -p "$(dirname "$(builder_active_file "$profile")")"
        printf '%s' "$prev_active" > "$(builder_active_file "$profile")"
    else
        rm -f "$(builder_active_file "$profile")"
    fi
    if type sync_orchestra >/dev/null 2>&1; then
        sync_orchestra >/dev/null 2>&1 || true
    fi
    builder_restart_if_possible
}

builder_run_discovery() {
    local profile="$1"
    local session_id="${2:-$(date +%Y%m%d%H%M%S)}"
    if type discovery_run_session >/dev/null 2>&1; then
        discovery_run_session "$session_id" "$profile" "$(builder_profile_target "$profile")" "$(builder_profile_host_scope "$profile")"
        return $?
    fi
    return 1
}

builder_ranked_results() {
    local session_id="$1"
    local session_file
    local ranking_json
    session_file="$policy_sessions_discovery_root/$session_id.json"
    [ -f "$session_file" ] || return 1
    ranking_json="$(grep '"ranking": \[' "$session_file" | sed 's/^.*"ranking": //; s/,"recommended_candidate".*$//' | head -n 1)"
    [ -n "$ranking_json" ] || return 1
    printf '%s\n' "$ranking_json" | grep -o '{"candidate":"[^"]*","profile":[0-9]*,"strategy":"[^"]*","score":[0-9]*,"elapsed_ms":[0-9]*,"result":"[^"]*","reason":"[^"]*","label":"[^"]*"[^}]*}' | \
    sed 's/{"candidate":"\([^"]*\)","profile":\([0-9]*\),"strategy":"\([^"]*\)","score":\([0-9]*\),"elapsed_ms":\([0-9]*\),"result":"\([^"]*\)","reason":"\([^"]*\)","label":"\([^"]*\)".*/\1\t\2\t\3\t\4\t\5\t\6\t\7\t\8/' | \
    sort -t $'\t' -k4,4nr -k5,5n
}

builder_discovery_wizard() {
    local profile="$1"
    local session_id=""
    local choice=""
    local line=""
    local rank=0
    local target=""

    builder_profile_supported "$profile" || {
        echo "Профиль $profile пока не поддерживается builder-discovery."
        pause_enter
        return 1
    }

    target="$(builder_profile_target "$profile")"
    echo "Builder-discovery для профиля $(builder_profile_label "$profile")"
    echo "Цель проверки: $target"
    echo "Генерируем и проверяем кандидаты..."
    session_id="$(builder_run_discovery "$profile")" || {
        echo "Не удалось выполнить discovery."
        pause_enter
        return 1
    }

    echo ""
    echo "Результаты сессии: $session_id"
    while IFS=$'\t' read -r candidate_id _profile strat_num score elapsed result reason label; do
        rank=$((rank + 1))
        printf "%2s. %-4s score=%-4s elapsed=%-5s result=%-8s strategy=%-3s %s\n" \
            "$rank" "$candidate_id" "$score" "$elapsed" "$result" "$strat_num" "$label"
    done < <(builder_ranked_results "$session_id")
    echo ""
    read -re -p "Введите candidate id для применения (например c01, Enter - отмена): " choice
    if [ -z "$choice" ]; then
        echo "Ничего не применено."
        pause_enter
        return 0
    fi
    if ! builder_load_definition "$profile" "$choice"; then
        echo "Кандидат $choice не найден."
        pause_enter
        return 1
    fi
    builder_apply_candidate "$profile" "$choice" "persist" >/dev/null || {
        echo "Не удалось применить кандидат $choice."
        pause_enter
        return 1
    }
    echo "Кандидат $choice применён как фиксированная стратегия для профиля $profile."
    pause_enter
}

builder_list_candidates_tsv() {
    local profile="$1"
    local active_id=""
    local active_strategy="0"
    local file=""

    builder_seed_profile_candidates "$profile" || return 1
    if [ -f "$(builder_active_file "$profile")" ]; then
        # shellcheck disable=SC1090
        . "$(builder_active_file "$profile")"
        active_id="${CANDIDATE_ID:-}"
        active_strategy="${STRATEGY_NUM:-0}"
    fi

    for file in "$(builder_candidates_dir "$profile")"/*.env; do
        [ -f "$file" ] || continue
        # shellcheck disable=SC1090
        . "$file"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "${CANDIDATE_ID:-}" \
            "${LABEL:-}" \
            "${FAMILY:-}" \
            "${BLOB_MODE:-}" \
            "${ORIGIN:-generated}" \
            "$([ "${active_id:-}" = "${CANDIDATE_ID:-}" ] && echo 1 || echo 0)" \
            "$active_strategy"
    done
}

builder_saved_candidates_menu() {
    local profile="$1"
    local candidate_id=""
    builder_profile_supported "$profile" || {
        echo "Профиль $profile пока не поддерживается builder."
        pause_enter
        return 1
    }

    echo "Сохранённые builder-кандидаты для $(builder_profile_label "$profile"):"
    while IFS=$'\t' read -r cid label family blob active active_strategy_unused; do
        printf "  %s [%s] blob=%s%s\n" "$cid" "$family" "$blob" "$([ "$active" = "1" ] && printf ' ACTIVE' || printf '')"
        printf "      %s\n" "$label"
    done < <(builder_list_candidates_tsv "$profile" | awk -F '\t' '{print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $6 "\t" $7}')
    echo ""
    read -re -p "Введите candidate id для применения (Enter - выход): " candidate_id
    [ -n "$candidate_id" ] || return 0
    builder_apply_candidate "$profile" "$candidate_id" "persist" >/dev/null || {
        echo "Не удалось применить кандидат $candidate_id."
        pause_enter
        return 1
    }
    echo "Кандидат $candidate_id применён."
    pause_enter
}

builder_profile_json() {
    local profile="$1"
    local active_id="" active_strategy="0" chosen="false"
    if [ -f "$(builder_active_file "$profile")" ]; then
        # shellcheck disable=SC1090
        . "$(builder_active_file "$profile")"
        active_id="${CANDIDATE_ID:-}"
        active_strategy="${STRATEGY_NUM:-0}"
        chosen="$([ "${CHOSEN:-0}" = "1" ] && echo true || echo false)"
    fi
    printf '{"profile":%s,"supported":true,"label":"%s","active_candidate":"%s","active_strategy":"%s","chosen":%s}' \
        "$profile" \
        "$(printf '%s' "$(builder_profile_label "$profile")" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
        "$(printf '%s' "$active_id" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
        "$(printf '%s' "$active_strategy" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
        "$chosen"
}

builder_policy_sync_if_available() {
    if type policy_init_dirs >/dev/null 2>&1; then
        policy_init_dirs
        return 0
    fi
    return 1
}

builder_policy_family_id() {
    printf '%s' "$1" | tr ' ' '_' | tr '+' '_' | tr -s '_'
}

builder_policy_step_json() {
    local step="$1"
    local op="${step%%:*}"
    local rest part key value
    local first=1
    printf '{"op":"%s","args":{' "$(builder_json_escape "$op")"
    rest="${step#*:}"
    if [ "$rest" != "$step" ] && [ -n "$rest" ]; then
        local OLDIFS="$IFS"
        IFS=':'
        for part in $rest; do
            key="${part%%=*}"
            value="${part#*=}"
            [ -n "$key" ] || continue
            [ "$first" -eq 1 ] || printf ','
            first=0
            if [ "$key" = "$part" ]; then
                printf '"%s":true' "$(builder_json_escape "$key")"
            else
                case "$value" in
                    ''|*[!0-9-]*)
                        printf '"%s":"%s"' "$(builder_json_escape "$key")" "$(builder_json_escape "$value")"
                        ;;
                    *)
                        printf '"%s":%s' "$(builder_json_escape "$key")" "$value"
                        ;;
                esac
            fi
        done
        IFS="$OLDIFS"
    fi
    printf '}}'
}

builder_policy_steps_json() {
    local first=1
    local step=""
    printf '['
    for step in "$STEP1" "$STEP2" "$STEP3"; do
        [ -n "$step" ] || continue
        [ "$first" -eq 1 ] || printf ','
        first=0
        builder_policy_step_json "$step"
    done
    printf ']'
}

builder_policy_catalog_json() {
    local profile="$1"
    local first_family=1
    local first_candidate=1
    local seen_families=""
    local cid label family blob origin active active_strategy payloads

    printf '{'
    printf '"profile":%s,' "$profile"
    printf '"label":"%s",' "$(builder_json_escape "$(builder_profile_label "$profile")")"
    printf '"supported":true,'
    printf '"families":['
    while IFS=$'\t' read -r cid label family blob origin active active_strategy; do
        case " $seen_families " in
            *" $family "*) continue ;;
        esac
        seen_families="$seen_families $family"
        [ "$first_family" -eq 1 ] || printf ','
        first_family=0
        printf '{"family_id":"%s","label":"%s"}' \
            "$(builder_json_escape "$(builder_policy_family_id "$family")")" \
            "$(builder_json_escape "$family")"
    done < <(builder_list_candidates_tsv "$profile")
    printf '],'
    printf '"candidates":['
    while IFS=$'\t' read -r cid label family blob origin active active_strategy; do
        builder_load_definition "$profile" "$cid" || continue
        payloads="${CONSTRAINTS:-tls_client_hello}"
        [ "$first_candidate" -eq 1 ] || printf ','
        first_candidate=0
        printf '{'
        printf '"candidate_id":"%s",' "$(builder_json_escape "$(builder_policy_candidate_id "$profile" "$cid")")"
        printf '"family_id":"%s",' "$(builder_json_escape "$(builder_policy_family_id "$family")")"
        printf '"label":"%s",' "$(builder_json_escape "$label")"
        printf '"origin":"%s",' "$(builder_json_escape "$origin")"
        printf '"capabilities":"%s",' "$(builder_json_escape "${CAPABILITIES:-}")"
        printf '"requires":"%s",' "$(builder_json_escape "${REQUIRES:-}")"
        printf '"features":"%s",' "$(builder_json_escape "${FEATURES:-}")"
        printf '"risk_flags":"%s",' "$(builder_json_escape "${RISK_FLAGS:-}")"
        printf '"cost_score":%s,' "${COST_SCORE:-0}"
        printf '"stability_hint":%s,' "${STABILITY_HINT:-0}"
        printf '"diversity_key":"%s",' "$(builder_json_escape "${DIVERSITY_KEY:-}")"
        printf '"steps":%s,' "$(builder_policy_steps_json)"
        printf '"constraints":{"payload":["%s"]}' "$(builder_json_escape "$payloads")"
        printf '}'
    done < <(builder_list_candidates_tsv "$profile")
    printf ']}'
}

builder_policy_compile_step_lua() {
    local step="$1"
    local op="${step%%:*}"
    local rest part key value
    local first=1
    printf '        { op = "%s", args = {' "$(builder_json_escape "$op")"
    rest="${step#*:}"
    if [ "$rest" != "$step" ] && [ -n "$rest" ]; then
        local OLDIFS="$IFS"
        IFS=':'
        for part in $rest; do
            key="${part%%=*}"
            value="${part#*=}"
            [ -n "$key" ] || continue
            [ "$first" -eq 1 ] || printf ', '
            first=0
            if [ "$key" = "$part" ]; then
                printf '%s = true' "$key"
            else
                case "$value" in
                    pos|host|hostname|sni|tls_sni|midhost|method|methodeol|seqovl_pattern|blob|ip_id|ip_id_pattern|pattern|fooling_mode|md5sig|hostspell|split)
                        printf '%s = "%s"' "$key" "$(builder_json_escape "$value")"
                        ;;
                    ''|*[!0-9-]*)
                        printf '%s = "%s"' "$key" "$(builder_json_escape "$value")"
                        ;;
                    *)
                        printf '%s = %s' "$key" "$value"
                        ;;
                esac
            fi
        done
        IFS="$OLDIFS"
    fi
    printf '} },\n'
}

builder_policy_compile_candidates_lua() {
    local profile="$1"
    local first=1
    local cid label family blob origin active active_strategy payloads step
    while IFS=$'\t' read -r cid label family blob origin active active_strategy; do
        builder_load_definition "$profile" "$cid" || continue
        payloads="${CONSTRAINTS:-tls_client_hello}"
        [ "$first" -eq 1 ] || printf ',\n'
        first=0
        printf '    ["%s"] = {\n' "$(builder_json_escape "$(builder_policy_candidate_id "$profile" "$cid")")"
        printf '      profile = %s,\n' "$profile"
        printf '      family_id = "%s",\n' "$(builder_json_escape "$(builder_policy_family_id "$family")")"
        printf '      constraints = { payload = { ["%s"] = true } },\n' "$(builder_json_escape "$payloads")"
        printf '      steps = {\n'
        for step in "$STEP1" "$STEP2" "$STEP3"; do
            [ -n "$step" ] || continue
            builder_policy_compile_step_lua "$step"
        done
        printf '      }\n'
        printf '    }'
    done < <(builder_list_candidates_tsv "$profile")
}

builder_sync_policy_catalog() {
    local profile="$1"
    local json_file lua_file
    builder_policy_sync_if_available || return 0
    json_file="$(builder_policy_catalog_json_file "$profile")"
    lua_file="$(builder_policy_catalog_lua_file "$profile")"
    mkdir -p "$(dirname "$json_file")"
    builder_policy_catalog_json "$profile" > "$json_file" || return 1
    builder_policy_compile_candidates_lua "$profile" > "$lua_file" || return 1
    policy_write_catalog "$profile" "$json_file" || return 1
    policy_write_catalog_lua "$profile" "$lua_file" || return 1
}

builder_sync_policy_profile_state() {
    local profile="$1"
    local json_file candidate_id family_id updated_at chosen mode source status confidence
    builder_policy_sync_if_available || return 0
    json_file="$(builder_policy_profile_state_json_file "$profile")"
    candidate_id=""
    family_id=""
    updated_at=""
    chosen="0"
    if [ -f "$(builder_active_file "$profile")" ]; then
        # shellcheck disable=SC1090
        . "$(builder_active_file "$profile")"
        if [ -n "${CANDIDATE_ID:-}" ]; then
            candidate_id="$(builder_policy_candidate_id "$profile" "${CANDIDATE_ID:-}")"
            updated_at="${UPDATED_AT:-}"
            chosen="${CHOSEN:-0}"
            if builder_load_definition "$profile" "${CANDIDATE_ID:-}"; then
                family_id="$(builder_policy_family_id "${FAMILY:-}")"
            fi
        fi
    fi
    mode="$([ "$chosen" = "1" ] && echo "manual_fixed" || echo "builder_temp")"
    source="$([ "$chosen" = "1" ] && echo "manual_apply" || echo "builder_sync")"
    status="$([ -n "$candidate_id" ] && echo "known_good" || echo "idle")"
    confidence="$([ -n "$candidate_id" ] && echo "1" || echo "0")"
    cat > "$json_file" <<EOF
{
  "profile": $profile,
  "mode": "$mode",
  "active_candidate_id": "$(builder_json_escape "$candidate_id")",
  "active_family_id": "$(builder_json_escape "$family_id")",
  "status": "$status",
  "confidence": $confidence,
  "pending_job_id": "",
  "fallback_chain": [],
  "last_validated_at": "$(builder_json_escape "$updated_at")",
  "source": "$source"
}
EOF
    policy_write_profile_state "$profile" "$json_file" || return 1
}

builder_record_knowledge_entry() {
    local profile="$1"
    local candidate_id="$2"
    local score="$3"
    local elapsed="$4"
    local verdict="$5"
    local phase="${6:-}"
    local knowledge_file tmp current_sig existing_sig line

    builder_load_definition "$profile" "$candidate_id" || return 1
    knowledge_file="$(builder_knowledge_file "$profile")"
    mkdir -p "$(dirname "$knowledge_file")"
    tmp="$(mktemp)"
    current_sig="$(builder_candidate_signature "${STEP1:-}" "${STEP2:-}" "${STEP3:-}")"
    if [ -f "$knowledge_file" ]; then
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            existing_sig="$(printf '%s' "$line" | awk -F '\t' '{print $8 "|" $9 "|" $10}')"
            [ "$existing_sig" = "$current_sig" ] && continue
            printf '%s\n' "$line" >> "$tmp"
        done < "$knowledge_file"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${FAMILY:-}" "${BLOB_MODE:-}" "${POSITION_PARAMS:-}" "${TCP_MODIFIERS:-}" \
        "${REPEATS:-}" "${CONSTRAINTS:-tls_client_hello}" "${DESYNC_STEPS:-}" \
        "${STEP1:-}" "${STEP2:-}" "${STEP3:-}" "${LABEL:-$candidate_id}" \
        "${score:-0}" "${elapsed:-0}" "${verdict:-inconclusive}" "${phase:-${PHASE:-}}" \
        "${CAPABILITIES:-}" "${REQUIRES:-}" "${FEATURES:-}" "${RISK_FLAGS:-}" \
        "${COST_SCORE:-0}" "${STABILITY_HINT:-0}" "${DIVERSITY_KEY:-}" >> "$tmp"
    sort -t $'\t' -k12,12nr -k13,13n "$tmp" | head -n 24 > "$knowledge_file"
    rm -f "$tmp"
}

builder_profiles_json() {
    printf '['
    builder_profile_json 1
    printf ','
    builder_profile_json 2
    printf ']'
}

builder_candidates_json() {
    local profile="$1"
    local first=1
    local active_id=""
    if [ -f "$(builder_active_file "$profile")" ]; then
        # shellcheck disable=SC1090
        . "$(builder_active_file "$profile")"
        active_id="${CANDIDATE_ID:-}"
    fi
    printf '['
    while IFS=$'\t' read -r cid label family blob origin active active_strategy; do
        [ "$first" -eq 1 ] || printf ','
        first=0
        printf '{"candidate":"%s","profile":%s,"label":"%s","family":"%s","blob_mode":"%s","origin":"%s","active":%s,"chosen":%s,"active_strategy":"%s"}' \
            "$(printf '%s' "$cid" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
            "$profile" \
            "$(printf '%s' "$label" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
            "$(printf '%s' "$family" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
            "$(printf '%s' "$blob" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
            "$(printf '%s' "$origin" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
            "$([ "$active" = "1" ] && echo true || echo false)" \
            "$([ "$cid" = "$active_id" ] && echo true || echo false)" \
            "$(printf '%s' "$active_strategy" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    done < <(builder_list_candidates_tsv "$profile")
    printf ']'
}

builder_session_results_json() {
    local session_id="$1"
    local session_file
    session_file="$policy_sessions_discovery_root/$session_id.json"
    [ -f "$session_file" ] || {
        printf '[]'
        return
    }
    grep '"results": \[' "$session_file" | sed 's/^.*"results": //; s/,"ranking".*$//' | head -n 1
}

builder_last_session_json() {
    local profile="$1"
    local session_id=""
    if [ -f "$(builder_last_session_file "$profile")" ]; then
        session_id="$(cat "$(builder_last_session_file "$profile")")"
    fi
    if [ -z "$session_id" ]; then
        printf '{"profile":%s,"session_id":"","results":[]}' "$profile"
        return
    fi
    if [ -f "$policy_sessions_discovery_root/$session_id.json" ]; then
        cat "$policy_sessions_discovery_root/$session_id.json"
        return
    fi
    printf '{"profile":%s,"session_id":"%s","results":[]}' "$profile" "$(printf '%s' "$session_id" | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

builder_write_webui_candidates_cache() {
    local profile="$1"
    local file tmp
    file="$(builder_webui_candidates_cache_file "$profile")"
    mkdir -p "$(dirname "$file")"
    tmp="$(mktemp "${TMPDIR:-/tmp}/builder-candidates-cache.XXXXXX")" || return 1
    cat > "$tmp" <<EOF
{"profile":${profile},"candidates":$(builder_candidates_json "$profile"),"last_session":$(builder_last_session_json "$profile")}
EOF
    mv "$tmp" "$file"
}

builder_write_webui_last_session_cache() {
    local profile="$1"
    local file tmp
    file="$(builder_webui_last_session_cache_file "$profile")"
    mkdir -p "$(dirname "$file")"
    tmp="$(mktemp "${TMPDIR:-/tmp}/builder-last-session-cache.XXXXXX")" || return 1
    builder_last_session_json "$profile" > "$tmp"
    mv "$tmp" "$file"
}

builder_sync_webui_profile_cache() {
    local profile="$1"
    builder_write_webui_last_session_cache "$profile" || true
    builder_write_webui_candidates_cache "$profile" || true
}

builder_active_json() {
    local first=1
    local profile=""
    printf '{"active":['
    for profile in 1 2; do
        [ -f "$(builder_active_file "$profile")" ] || continue
        # shellcheck disable=SC1090
        . "$(builder_active_file "$profile")"
        [ "$first" -eq 1 ] || printf ','
        first=0
        printf '{"profile":%s,"candidate":"%s","strategy":"%s","label":"%s","chosen":%s,"updated_at":"%s"}' \
            "$profile" \
            "$(printf '%s' "${CANDIDATE_ID:-}" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
            "$(printf '%s' "${STRATEGY_NUM:-0}" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
            "$(printf '%s' "${LABEL:-}" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
            "$([ "${CHOSEN:-0}" = "1" ] && echo true || echo false)" \
            "$(printf '%s' "${UPDATED_AT:-}" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    done
    printf ']}'
}

builder_cli_main() {
    local cmd="${1:-}"
    local profile="${2:-}"
    local candidate_id="${3:-}"

    case "$cmd" in
        discovery)
            builder_discovery_wizard "$profile"
            ;;
        candidates)
            builder_saved_candidates_menu "$profile"
            ;;
        apply-generated)
            builder_apply_candidate "$profile" "$candidate_id" "persist"
            ;;
        *)
            echo "usage: $0 {discovery PROFILE|candidates PROFILE|apply-generated PROFILE CANDIDATE_ID}"
            return 1
            ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    builder_cli_main "$@"
fi
