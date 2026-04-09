BLOCKCHECK_DIR="/opt/zapret2/extra_strats/cache/blockcheck2"
BLOCKCHECK_RESULTS_FILE="$BLOCKCHECK_DIR/results.tsv"
BLOCKCHECK_LAST_RECOMMENDATION_FILE="$BLOCKCHECK_DIR/last_recommendations.json"
BLOCKCHECK_HISTORY_DIR="$BLOCKCHECK_DIR/history"

blockcheck_init_dirs() {
    mkdir -p "$BLOCKCHECK_DIR" "$BLOCKCHECK_HISTORY_DIR"
    touch "$BLOCKCHECK_RESULTS_FILE"
}

blockcheck_profile_name() {
    case "$1" in
        1) echo "YouTube TCP" ;;
        2) echo "Googlevideo" ;;
        3) echo "Blocked Sites" ;;
        4) echo "Discord TCP" ;;
        5) echo "YouTube QUIC" ;;
        6) echo "Voice UDP" ;;
        7) echo "Telegram" ;;
        *) echo "Unknown" ;;
    esac
}

blockcheck_profile_target() {
    case "$1" in
        1) echo "https://www.youtube.com/" ;;
        2) echo "https://$(get_yt_cluster_domain)" ;;
        3) echo "https://meduza.io" ;;
        4) echo "https://discord.com/" ;;
        5) echo "" ;;
        6) echo "" ;;
        7) echo "https://telegram.org/" ;;
        *) echo "" ;;
    esac
}

blockcheck_profile_proto() {
    case "$1" in
        1|2|3|4|7) echo "tls" ;;
        5|6) echo "udp" ;;
        *) echo "" ;;
    esac
}

blockcheck_profile_supported() {
    case "$1" in
        1|2|3|4|7) return 0 ;;
        5|6) return 1 ;;
        *) return 1 ;;
    esac
}

blockcheck_mode_text() {
    if type hostlist_mode_text >/dev/null 2>&1; then
        hostlist_mode_text
    else
        echo "unknown"
    fi
}

blockcheck_fallback_text() {
    if type fallback_mode_text >/dev/null 2>&1; then
        fallback_mode_text
    else
        echo "unknown"
    fi
}

blockcheck_blob_text() {
    if type tls_blob_menu_text >/dev/null 2>&1; then
        tls_blob_menu_text
    else
        echo "unknown"
    fi
}

blockcheck_restart_runtime() {
    if type restart_zapret2 >/dev/null 2>&1; then
        restart_zapret2 >/dev/null 2>&1 || true
        return 0
    fi
    if [ -n "${ZAPRET2_INIT:-}" ] && [ -f "$ZAPRET2_INIT" ]; then
        "$ZAPRET2_INIT" restart >/dev/null 2>&1 || true
    fi
    if type orchestra_start >/dev/null 2>&1 && [ -f "${ORCH_ENABLED_FLAG:-/opt/zapret2/extra_strats/cache/orchestra/enabled}" ]; then
        orchestra_start >/dev/null 2>&1 || true
    elif [ -x "${ORCH_SCRIPT:-}" ] && [ -f "/opt/zapret2/extra_strats/cache/orchestra/enabled" ]; then
        "$ORCH_SCRIPT" start >/dev/null 2>&1 || true
    fi
}

blockcheck_run_http_probe() {
    local target="$1"
    local start elapsed
    local tls12=0 tls13=0 result reason

    start="$(date +%s)"
    curl --tls-max 1.2 --max-time 3 -s -o /dev/null "$target" && tls12=1 || true
    curl --tlsv1.3 --max-time 3 -s -o /dev/null "$target" && tls13=1 || true
    elapsed=$(( ($(date +%s) - start) * 1000 ))

    if [ "$tls12" -eq 1 ] && [ "$tls13" -eq 1 ]; then
        result="ok"
        reason="tls12+tls13"
    elif [ "$tls12" -eq 1 ] || [ "$tls13" -eq 1 ]; then
        result="unstable"
        if [ "$tls12" -eq 1 ]; then
            reason="tls12_only"
        else
            reason="tls13_only"
        fi
    else
        result="fail"
        reason="no_tls_response"
    fi

    printf '%s\t%s\t%s\n' "$result" "$reason" "$elapsed"
}

blockcheck_append_result_line() {
    local dest="$1"
    local timestamp="$2"
    local mode="$3"
    local profile_id="$4"
    local profile_name="$5"
    local target="$6"
    local strategy="$7"
    local result="$8"
    local reason="$9"
    local elapsed_ms="${10}"
    local blob_mode="${11}"
    local hostlist_mode="${12}"
    local fallback_mode="${13}"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$timestamp" "$mode" "$profile_id" "$profile_name" "$target" "$strategy" \
        "$result" "$reason" "$elapsed_ms" "$blob_mode" "$hostlist_mode" "$fallback_mode" >> "$dest"
}

blockcheck_json_array_from_csv() {
    local csv="$1"
    local out="" item
    if [ -z "$csv" ]; then
        printf '[]'
        return
    fi
    IFS=',' read -r -a _items <<< "$csv"
    for item in "${_items[@]}"; do
        [ -z "$item" ] && continue
        if [ -n "$out" ]; then
            out="${out},"
        fi
        out="${out}${item}"
    done
    printf '[%s]' "$out"
}

blockcheck_json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

blockcheck_write_last_recommendation() {
    local mode="$1"
    local profile_id="$2"
    local profile_name="$3"
    local target="$4"
    local supported="$5"
    local best="$6"
    local backups_csv="$7"
    local failed_csv="$8"
    local summary="$9"
    local run_file="${10}"
    local summary_file="${11}"

    blockcheck_init_dirs
    cat > "$BLOCKCHECK_LAST_RECOMMENDATION_FILE" <<EOF
{"mode":"$(blockcheck_json_escape "$mode")","profile_id":"$(blockcheck_json_escape "$profile_id")","profile_name":"$(blockcheck_json_escape "$profile_name")","target":"$(blockcheck_json_escape "$target")","supported":$supported,"best_strategy":${best:-null},"backup_strategies":$(blockcheck_json_array_from_csv "$backups_csv"),"failed_strategies":$(blockcheck_json_array_from_csv "$failed_csv"),"reason_summary":"$(blockcheck_json_escape "$summary")","run_file":"$(blockcheck_json_escape "$run_file")","summary_file":"$(blockcheck_json_escape "$summary_file")"}
EOF
}

blockcheck_compute_recommendation() {
    local run_file="$1"
    local mode="$2"
    local profile_id="$3"
    local profile_name="$4"
    local target="$5"
    local current_lock="$6"
    local summary_file="$7"
    local best="" backups_csv="" failed_csv="" summary="" supported=true
    local ranking_file="${run_file}.ranking"

    : > "$ranking_file"

    while IFS=$'\t' read -r ts _mode _profile_id _profile_name _target strategy result reason elapsed blob hostlist fallback; do
        [ -z "$strategy" ] && continue
        case "$result" in
            ok) score=3000 ;;
            unstable) score=2000 ;;
            fail) score=0 ;;
            skipped) score=-1 ;;
            *) score=-1 ;;
        esac
        if [ "$score" -ge 0 ] && [ -n "$current_lock" ] && [ "$current_lock" = "$strategy" ]; then
            score=$((score + 100))
        fi
        if [ "$result" = "fail" ]; then
            failed_csv="${failed_csv:+$failed_csv,}$strategy"
        fi
        if [ "$score" -ge 0 ]; then
            printf '%s\t%s\t%s\t%s\t%s\n' "$score" "${elapsed:-999999}" "$strategy" "$result" "$reason" >> "$ranking_file"
        fi
    done < "$run_file"

    if [ -s "$ranking_file" ]; then
        local idx=0 line score elapsed strategy result reason
        while IFS=$'\t' read -r score elapsed strategy result reason; do
            if [ -z "$best" ]; then
                best="$strategy"
                if [ "$result" = "ok" ]; then
                    summary="Рекомендуется стратегия $strategy: стабильный проход проверок."
                else
                    summary="Стабильных стратегий не найдено, лучший вариант: $strategy."
                fi
            elif [ "$idx" -lt 3 ]; then
                backups_csv="${backups_csv:+$backups_csv,}$strategy"
            fi
            idx=$((idx + 1))
            [ "$idx" -ge 4 ] && break
        done < <(sort -t $'\t' -k1,1nr -k2,2n "$ranking_file")
    else
        summary="Рабочие стратегии не найдены."
    fi

    if [ -z "$summary" ]; then
        summary="Недостаточно данных для рекомендации."
    fi

    {
        echo "Blockcheck summary"
        echo "Mode: $mode"
        echo "Profile: $profile_name ($profile_id)"
        echo "Target: $target"
        echo "Best: ${best:-none}"
        echo "Backups: ${backups_csv:-none}"
        echo "Failed: ${failed_csv:-none}"
        echo "Reason: $summary"
    } > "$summary_file"

    blockcheck_write_last_recommendation "$mode" "$profile_id" "$profile_name" "$target" "$supported" "${best:-null}" "$backups_csv" "$failed_csv" "$summary" "$run_file" "$summary_file"
    rm -f "$ranking_file"
}

blockcheck_write_unsupported_recommendation() {
    local mode="$1"
    local profile_id="$2"
    local profile_name="$3"
    local target="$4"
    local run_file="$5"
    local summary_file="$6"
    local summary="Профиль пока не поддерживает полноценную автоматическую HTTP-проверку в MVP."

    {
        echo "Blockcheck summary"
        echo "Mode: $mode"
        echo "Profile: $profile_name ($profile_id)"
        echo "Target: $target"
        echo "Best: none"
        echo "Reason: $summary"
    } > "$summary_file"

    blockcheck_write_last_recommendation "$mode" "$profile_id" "$profile_name" "$target" false null "" "" "$summary" "$run_file" "$summary_file"
}

blockcheck_run_scan() {
    local mode="$1"
    local profile_id="$2"
    local target="$3"
    local profile_name proto max current_lock run_id ts run_file summary_file result reason elapsed blob hostlist fallback

    blockcheck_init_dirs
    profile_name="$(blockcheck_profile_name "$profile_id")"
    proto="$(blockcheck_profile_proto "$profile_id")"
    max="$(orch_max_strategy_for_profile "$profile_id")"
    current_lock="$(orch_locked_get "$profile_id" "$proto")"
    ts="$(date +%Y%m%d_%H%M%S)"
    run_id="${mode}_${profile_id}_${ts}"
    run_file="$BLOCKCHECK_HISTORY_DIR/${run_id}.tsv"
    summary_file="$BLOCKCHECK_HISTORY_DIR/${run_id}.summary"
    : > "$run_file"

    if ! blockcheck_profile_supported "$profile_id"; then
        blockcheck_write_unsupported_recommendation "$mode" "$profile_id" "$profile_name" "$target" "$run_file" "$summary_file"
        BLOCKCHECK_LAST_RUN_FILE="$run_file"
        return 0
    fi

    if [ -z "$max" ] || [ "$max" -le 0 ]; then
        echo "Не удалось определить стратегии для профиля $profile_id" >&2
        return 1
    fi

    blob="$(blockcheck_blob_text)"
    hostlist="$(blockcheck_mode_text)"
    fallback="$(blockcheck_fallback_text)"

    for strategy in $(seq 1 "$max"); do
        orch_locked_set "$profile_id" "$proto" "$strategy"
        if type sync_orchestra >/dev/null 2>&1; then
            sync_orchestra
        fi
        blockcheck_restart_runtime
        sleep 1
        IFS=$'\t' read -r result reason elapsed <<EOF
$(blockcheck_run_http_probe "$target")
EOF
        blockcheck_append_result_line "$run_file" "$ts" "$mode" "$profile_id" "$profile_name" "$target" "$strategy" "$result" "$reason" "$elapsed" "$blob" "$hostlist" "$fallback"
        blockcheck_append_result_line "$BLOCKCHECK_RESULTS_FILE" "$ts" "$mode" "$profile_id" "$profile_name" "$target" "$strategy" "$result" "$reason" "$elapsed" "$blob" "$hostlist" "$fallback"
    done

    if [ -n "$current_lock" ] && [ "$current_lock" -gt 0 ] 2>/dev/null; then
        orch_locked_set "$profile_id" "$proto" "$current_lock"
    else
        orch_locked_clear "$profile_id" "$proto"
    fi
    if type sync_orchestra >/dev/null 2>&1; then
        sync_orchestra
    fi
    blockcheck_restart_runtime
    blockcheck_compute_recommendation "$run_file" "$mode" "$profile_id" "$profile_name" "$target" "$current_lock" "$summary_file"
    BLOCKCHECK_LAST_RUN_FILE="$run_file"
}

blockcheck_run_profile_scan() {
    local profile_id="$1"
    local target
    target="$(blockcheck_profile_target "$profile_id")"
    blockcheck_run_scan "profile" "$profile_id" "$target"
}

blockcheck_run_custom_scan() {
    local target="$1"
    local profile_id="$2"
    case "$target" in
        http://*|https://*) ;;
        *) target="https://$target" ;;
    esac
    if [ "$profile_id" = "auto" ] || [ -z "$profile_id" ]; then
        profile_id="3"
    fi
    blockcheck_run_scan "custom" "$profile_id" "$target"
}

blockcheck_last_json() {
    if [ -s "$BLOCKCHECK_LAST_RECOMMENDATION_FILE" ]; then
        cat "$BLOCKCHECK_LAST_RECOMMENDATION_FILE"
    else
        echo '{"mode":"","profile_id":"","profile_name":"","target":"","supported":false,"best_strategy":null,"backup_strategies":[],"failed_strategies":[],"reason_summary":"Рекомендации пока отсутствуют.","run_file":"","summary_file":""}'
    fi
}

blockcheck_parse_last_field() {
    local field="$1"
    sed -n -E "s/.*\"${field}\":\"([^\"]*)\".*/\\1/p" "$BLOCKCHECK_LAST_RECOMMENDATION_FILE" 2>/dev/null | head -n1
}

blockcheck_print_last_recommendation() {
    local profile_name best backups failed summary target
    if [ ! -s "$BLOCKCHECK_LAST_RECOMMENDATION_FILE" ]; then
        echo "Рекомендации пока отсутствуют."
        return 1
    fi
    profile_name="$(blockcheck_parse_last_field "profile_name")"
    target="$(blockcheck_parse_last_field "target")"
    best="$(sed -n -E 's/.*"best_strategy":(null|[0-9]+).*/\1/p' "$BLOCKCHECK_LAST_RECOMMENDATION_FILE" | head -n1)"
    backups="$(sed -n -E 's/.*"backup_strategies":\[([^]]*)\].*/\1/p' "$BLOCKCHECK_LAST_RECOMMENDATION_FILE" | head -n1)"
    failed="$(sed -n -E 's/.*"failed_strategies":\[([^]]*)\].*/\1/p' "$BLOCKCHECK_LAST_RECOMMENDATION_FILE" | head -n1)"
    summary="$(blockcheck_parse_last_field "reason_summary")"
    echo -e "${cyan}--- Последняя рекомендация ---${plain}"
    echo "Профиль: ${profile_name:-Unknown}"
    echo "Цель: ${target:-unknown}"
    echo "Лучшая стратегия: ${best:-none}"
    echo "Запасные: ${backups:-none}"
    echo "Неудачные: ${failed:-none}"
    echo "Причина: ${summary:-нет данных}"
}

blockcheck_apply_last_recommendation() {
    local profile_id best proto
    if [ ! -s "$BLOCKCHECK_LAST_RECOMMENDATION_FILE" ]; then
        echo "Рекомендации пока отсутствуют."
        return 1
    fi
    profile_id="$(blockcheck_parse_last_field "profile_id")"
    best="$(sed -n -E 's/.*"best_strategy":(null|[0-9]+).*/\1/p' "$BLOCKCHECK_LAST_RECOMMENDATION_FILE" | head -n1)"
    proto="$(blockcheck_profile_proto "$profile_id")"
    if [ -z "$profile_id" ] || [ -z "$proto" ] || [ "$best" = "null" ] || [ -z "$best" ]; then
        echo "Нет применимой рекомендации."
        return 1
    fi
    orch_locked_set "$profile_id" "$proto" "$best"
    if type sync_orchestra >/dev/null 2>&1; then
        sync_orchestra
    fi
    blockcheck_restart_runtime
    echo "Рекомендация применена: профиль $profile_id -> стратегия $best"
}

blockcheck_show_last_summary() {
    local summary_file
    summary_file="$(blockcheck_parse_last_field "summary_file")"
    if [ -n "$summary_file" ] && [ -f "$summary_file" ]; then
        cat "$summary_file"
        return 0
    fi
    if [ -f /opt/zapret2/blockcheck2_summary.txt ]; then
        cat /opt/zapret2/blockcheck2_summary.txt
        return 0
    fi
    echo "SUMMARY/лог пока отсутствует."
    return 1
}

blockcheck_cli_profile_scan_menu() {
    local profile_id
    echo "Профили для проверки: 1, 2, 3, 4, 5, 6, 7"
    read -re -p "Введите номер профиля: " profile_id
    if ! printf '%s' "$profile_id" | grep -Eq '^[1-7]$'; then
        echo "Некорректный профиль."
        return 1
    fi
    echo "Запуск проверки профиля $profile_id..."
    blockcheck_run_profile_scan "$profile_id" || return 1
    blockcheck_print_last_recommendation
}

blockcheck_cli_custom_scan_menu() {
    local target profile_id
    read -re -p "Введите домен или URL: " target
    if [ -z "$target" ]; then
        echo "Пустая цель."
        return 1
    fi
    read -re -p "Профиль (auto или 1-7, Enter = auto): " profile_id
    [ -z "$profile_id" ] && profile_id="auto"
    if [ "$profile_id" != "auto" ] && ! printf '%s' "$profile_id" | grep -Eq '^[1-7]$'; then
        echo "Некорректный профиль."
        return 1
    fi
    echo "Запуск кастомной проверки..."
    blockcheck_run_custom_scan "$target" "$profile_id" || return 1
    blockcheck_print_last_recommendation
}
