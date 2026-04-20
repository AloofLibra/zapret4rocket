#!/bin/bash

builder_root="${builder_root:-/opt/zapret2/extra_strats/cache/builder}"
builder_profiles_root="$builder_root/profiles"
builder_sessions_root="$builder_root/sessions"

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

builder_current_config_file() {
    if [ -f /opt/zapret2/config ]; then
        echo "/opt/zapret2/config"
    else
        echo "/opt/zapret2/config.default"
    fi
}

builder_escape_env() {
    printf "%s" "$1" | sed "s/'/'\"'\"'/g"
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
CANDIDATE_ID='$(builder_escape_env "$candidate_id")'
EOF
}

builder_seed_profile_candidates() {
    local profile="$1"
    builder_profile_supported "$profile" || return 1
    builder_init_dirs

    builder_write_definition "$profile" "c01" \
        "fake + multisplit" \
        "Fake + multisplit midsld ts-1000" \
        "fake_default_tls" \
        "1,midsld" \
        "tcp_ts=-1000" \
        "2" \
        "tls_client_hello" \
        "fake,multisplit" \
        "fake:blob=fake_default_tls:tcp_ts=-1000:repeats=2" \
        "multisplit:pos=1,midsld" \
        ""
    builder_write_definition "$profile" "c02" \
        "multisplit" \
        "Multisplit pos2 nodrop ts-500" \
        "fake_default_tls" \
        "2:nodrop" \
        "tcp_ts=-500" \
        "" \
        "tls_client_hello" \
        "multisplit" \
        "multisplit:blob=fake_default_tls:tcp_ts=-500:pos=2:nodrop" \
        "" \
        ""
    builder_write_definition "$profile" "c03" \
        "multisplit + fakeddisorder" \
        "Multisplit + fakeddisorder midsld ts-500" \
        "fake_default_tls" \
        "2:nodrop|midsld" \
        "tcp_ts=-500" \
        "" \
        "tls_client_hello" \
        "multisplit,fakeddisorder" \
        "multisplit:blob=fake_default_tls:tcp_ts=-500:pos=2:nodrop" \
        "fakeddisorder:pos=midsld:tcp_ts=-500" \
        ""
    builder_write_definition "$profile" "c04" \
        "multisplit + fakeddisorder" \
        "Multisplit + fakeddisorder sniext+4 ts-1000" \
        "fake_default_tls" \
        "2:nodrop|sniext+4" \
        "tcp_ts=-1000" \
        "" \
        "tls_client_hello" \
        "multisplit,fakeddisorder" \
        "multisplit:blob=fake_default_tls:tcp_ts=-1000:pos=2:nodrop" \
        "fakeddisorder:pos=sniext+4:tcp_ts=-1000" \
        ""
    builder_write_definition "$profile" "c05" \
        "hostfakesplit" \
        "Hostfakesplit ack ts_up" \
        "" \
        "" \
        "tcp_ack=-66000:tcp_ts_up" \
        "" \
        "tls_client_hello" \
        "hostfakesplit" \
        "hostfakesplit:tcp_ack=-66000:tcp_ts_up" \
        "" \
        ""
    builder_write_definition "$profile" "c06" \
        "hostfakesplit" \
        "Hostfakesplit tcp_md5 autottl" \
        "" \
        "" \
        "tcp_md5:ip_autottl=-1,3-20:ip6_autottl=-1,3-20" \
        "" \
        "tls_client_hello" \
        "hostfakesplit" \
        "hostfakesplit:tcp_md5:ip_autottl=-1,3-20:ip6_autottl=-1,3-20" \
        "" \
        ""
    builder_write_definition "$profile" "c07" \
        "multisplit + fakedsplit" \
        "Multisplit + fakedsplit seq-3000 midsld" \
        "fake_default_tls" \
        "2:nodrop|midsld" \
        "tcp_seq=-3000" \
        "" \
        "tls_client_hello" \
        "multisplit,fakedsplit" \
        "multisplit:blob=fake_default_tls:tcp_seq=-3000:pos=2:nodrop" \
        "fakedsplit:pos=midsld:tcp_seq=-3000" \
        ""
    builder_write_definition "$profile" "c08" \
        "multisplit + multidisorder" \
        "Seqovl custom + multidisorder" \
        "custom" \
        "1,midsld" \
        "seqovl=666:seqovl_pattern=custom" \
        "" \
        "tls_client_hello" \
        "multisplit,multidisorder" \
        "multisplit:seqovl=666:seqovl_pattern=custom" \
        "multidisorder:pos=1,midsld" \
        ""
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

builder_apply_candidate() {
    local profile="$1"
    local candidate_id="$2"
    local mode="${3:-persist}"
    local cfg cleaned tmp lines_file max strategy_num active_file lock_proto

    builder_seed_profile_candidates "$profile" || return 1
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

    builder_restart_if_possible
    rm -f "$cleaned" "$lines_file"
    printf '%s\n' "$strategy_num"
}

builder_probe_target() {
    local target="$1"
    local start elapsed tls12=0 tls13=0 score=0 result="fail" reason="no_tls_response"
    start="$(date +%s)"
    curl --tls-max 1.2 --max-time 4 -s -o /dev/null "$target" && tls12=1 || true
    curl --tlsv1.3 --max-time 4 -s -o /dev/null "$target" && tls13=1 || true
    elapsed=$(( ($(date +%s) - start) * 1000 ))

    if [ "$tls12" -eq 1 ] && [ "$tls13" -eq 1 ]; then
        score=3000
        result="ok"
        reason="tls12+tls13"
    elif [ "$tls12" -eq 1 ] || [ "$tls13" -eq 1 ]; then
        score=2000
        result="unstable"
        reason="single_tls_version"
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' "$score" "$elapsed" "$result" "$reason" "$target"
}

builder_restore_config_and_state() {
    local cfg="$1"
    local backup_cfg="$2"
    local profile="$3"
    local prev_locks="$4"
    local prev_active="$5"
    local lock_proto="" lock_entry="" lock_value=""
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
    local cfg backup_cfg prev_locks prev_active target results_file session_dir candidate_file candidate_id strat_num lock_proto
    local score elapsed result reason probed_target

    builder_seed_profile_candidates "$profile" || return 1
    cfg="$(builder_current_config_file)"
    target="$(builder_profile_target "$profile")"
    session_dir="$builder_sessions_root/$session_id"
    results_file="$session_dir/results.tsv"
    mkdir -p "$session_dir"
    cat > "$session_dir/meta.env" <<EOF
PROFILE_ID='$profile'
TARGET='$(builder_escape_env "$target")'
CREATED_AT='$(date '+%Y-%m-%d %H:%M:%S')'
EOF

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

    : > "$results_file"
    for candidate_file in "$(builder_candidates_dir "$profile")"/*.env; do
        [ -f "$candidate_file" ] || continue
        candidate_id="$(basename "$candidate_file" .env)"
        builder_load_definition "$profile" "$candidate_id" || continue
        strat_num="$(builder_apply_candidate "$profile" "$candidate_id" "temp" 2>/dev/null)" || continue
        IFS=$'\t' read -r score elapsed result reason probed_target <<EOF
$(builder_probe_target "$target")
EOF
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$candidate_id" "$profile" "$strat_num" "$score" "$elapsed" "$result" "$reason" "$LABEL" >> "$results_file"
    done

    builder_restore_config_and_state "$cfg" "$backup_cfg" "$profile" "$prev_locks" "$prev_active"
    printf '%s' "$session_id" > "$(builder_last_session_file "$profile")"
    printf '%s\n' "$session_id"
}

builder_ranked_results() {
    local session_id="$1"
    local results_file="$builder_sessions_root/$session_id/results.tsv"
    [ -f "$results_file" ] || return 1
    sort -t $'\t' -k4,4nr -k5,5n "$results_file"
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
    local first=1
    printf '['
    while IFS=$'\t' read -r candidate_id profile strat_num score elapsed result reason label; do
        [ "$first" -eq 1 ] || printf ','
        first=0
        printf '{"candidate":"%s","profile":%s,"strategy":"%s","score":%s,"elapsed_ms":%s,"result":"%s","reason":"%s","label":"%s"}' \
            "$(printf '%s' "$candidate_id" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
            "$profile" \
            "$(printf '%s' "$strat_num" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
            "${score:-0}" \
            "${elapsed:-0}" \
            "$(printf '%s' "$result" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
            "$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
            "$(printf '%s' "$label" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    done < <(builder_ranked_results "$session_id")
    printf ']'
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
    printf '{"profile":%s,"session_id":"%s","results":%s}' \
        "$profile" \
        "$(printf '%s' "$session_id" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
        "$(builder_session_results_json "$session_id")"
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
