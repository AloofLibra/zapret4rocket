ANALYTICS_DIR="/opt/zapret2/extra_strats/cache/analytics"
ANALYTICS_LAST_REPORT_FILE="$ANALYTICS_DIR/last_report.json"
ANALYTICS_HISTORY_DIR="$ANALYTICS_DIR/history"
ANALYTICS_JOBS_DIR="$ANALYTICS_DIR/jobs"

analytics_init_dirs() {
    mkdir -p "$ANALYTICS_DIR" "$ANALYTICS_HISTORY_DIR" "$ANALYTICS_JOBS_DIR"
}

analytics_json_escape() {
    if type json_escape >/dev/null 2>&1; then
        json_escape "$1"
    else
        printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g; s/\n/\\n/g'
    fi
}

analytics_progress_write() {
    [ -n "${ANALYTICS_PROGRESS_FILE:-}" ] || return 0
    cat > "$ANALYTICS_PROGRESS_FILE" <<EOF
{"status":"running","phase":"$(analytics_json_escape "$1")","status_text":"$(analytics_json_escape "$2")","target":"$(analytics_json_escape "$3")","profile_id":"$(analytics_json_escape "$4")","profile_name":"$(analytics_json_escape "$5")"}
EOF
}

analytics_normalize_target() {
    case "$1" in
        http://*|https://*) printf '%s\n' "$1" ;;
        *) printf 'https://%s\n' "$1" ;;
    esac
}

analytics_target_host() {
    printf '%s\n' "$1" | sed -E 's#^[a-zA-Z]+://##; s#/.*$##; s#:[0-9]+$##'
}

analytics_csv_to_json() {
    local csv="$1"
    local out="" item
    [ -n "$csv" ] || {
        printf '[]'
        return
    }
    IFS=',' read -r -a analytics_items <<< "$csv"
    for item in "${analytics_items[@]}"; do
        [ -n "$item" ] || continue
        out="${out:+$out,}\"$(analytics_json_escape "$item")\""
    done
    printf '[%s]' "$out"
}

analytics_json_array_from_file() {
    local file="$1"
    [ -f "$file" ] || {
        printf '[]'
        return
    }
    awk '
        BEGIN { first=1; printf "[" }
        {
            gsub(/\\/,"\\\\")
            gsub(/"/,"\\\"")
            gsub(/\r/,"")
            if (!first) printf ","
            first=0
            printf "\"%s\"", $0
        }
        END { printf "]" }
    ' "$file"
}

analytics_ip_is_bad() {
    case "$1" in
        10.*|127.*|0.*|169.254.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|100.6[4-9].*|100.[7-9][0-9].*|100.1[0-1][0-9].*|100.12[0-7].*|::1|fe80:*|fc*|fd*)
            return 0
            ;;
    esac
    return 1
}

analytics_extract_json_field() {
    printf '%s\n' "$1" | sed -n -E "s/.*\"$2\":\"([^\"]*)\".*/\\1/p" | head -n1
}

analytics_dns_collect_getent() {
    command -v getent >/dev/null 2>&1 || return 1
    getent ahosts "$1" 2>/dev/null | awk '{print $1}' | sort -u
}

analytics_dns_collect_nslookup() {
    command -v nslookup >/dev/null 2>&1 || return 1
    if [ "$2" = "system" ]; then
        nslookup "$1" 2>/dev/null | sed -n 's/^Address[[:space:]]*:[[:space:]]*//p' | grep -E '^[0-9A-Fa-f:.]+$' | sort -u
    else
        nslookup "$1" "$2" 2>/dev/null | sed -n 's/^Address[[:space:]]*:[[:space:]]*//p' | grep -E '^[0-9A-Fa-f:.]+$' | sort -u
    fi
}

analytics_dns_collect_dig() {
    local dig_bin=""
    if command -v dig >/dev/null 2>&1; then
        dig_bin="dig"
    elif command -v drill >/dev/null 2>&1; then
        dig_bin="drill"
    else
        return 1
    fi
    if [ "$2" = "system" ]; then
        "$dig_bin" +short A "$1" 2>/dev/null
        "$dig_bin" +short AAAA "$1" 2>/dev/null
    else
        "$dig_bin" @"$2" +short A "$1" 2>/dev/null
        "$dig_bin" @"$2" +short AAAA "$1" 2>/dev/null
    fi | grep -E '^[0-9A-Fa-f:.]+$' | sort -u
}

analytics_dns_collect_doh() {
    command -v curl >/dev/null 2>&1 || return 1
    local url_a url_aaaa
    case "$2" in
        cloudflare)
            url_a="https://cloudflare-dns.com/dns-query?name=$1&type=A"
            url_aaaa="https://cloudflare-dns.com/dns-query?name=$1&type=AAAA"
            ;;
        google)
            url_a="https://dns.google/resolve?name=$1&type=A"
            url_aaaa="https://dns.google/resolve?name=$1&type=AAAA"
            ;;
        *)
            return 1
            ;;
    esac
    {
        curl -fsSL --max-time 4 -H 'accept: application/dns-json' "$url_a" 2>/dev/null || true
        curl -fsSL --max-time 4 -H 'accept: application/dns-json' "$url_aaaa" 2>/dev/null || true
    } | tr ',' '\n' | sed -n 's/.*"data":"\([^"]*\)".*/\1/p' | grep -E '^[0-9A-Fa-f:.]+$' | sort -u
}

analytics_dns_resolver() {
    local host="$1"
    local name="$2"
    local resolver="$3"
    local tmp_file="$ANALYTICS_DIR/.dns_${name}_$$.txt"
    local method="unavailable"
    local ips_csv="" ip any_ip=false private_only=true

    : > "$tmp_file"
    if analytics_dns_collect_dig "$host" "$resolver" > "$tmp_file" 2>/dev/null && [ -s "$tmp_file" ]; then
        method="classic_dns"
    elif analytics_dns_collect_nslookup "$host" "$resolver" > "$tmp_file" 2>/dev/null && [ -s "$tmp_file" ]; then
        method="classic_dns"
    elif [ "$resolver" = "system" ] && analytics_dns_collect_getent "$host" > "$tmp_file" 2>/dev/null && [ -s "$tmp_file" ]; then
        method="system_resolver"
    elif [ "$name" = "cloudflare" ] && analytics_dns_collect_doh "$host" cloudflare > "$tmp_file" 2>/dev/null && [ -s "$tmp_file" ]; then
        method="doh"
    elif [ "$name" = "google" ] && analytics_dns_collect_doh "$host" google > "$tmp_file" 2>/dev/null && [ -s "$tmp_file" ]; then
        method="doh"
    fi

    if [ -s "$tmp_file" ]; then
        while IFS= read -r ip; do
            [ -n "$ip" ] || continue
            any_ip=true
            ips_csv="${ips_csv:+$ips_csv,}$ip"
            if ! analytics_ip_is_bad "$ip"; then
                private_only=false
            fi
        done < "$tmp_file"
    fi

    local verdict="ok"
    local status_text="all resolvers agree"
    if [ "$any_ip" = false ]; then
        verdict="no_answer"
        status_text="no DNS answer"
    elif [ "$private_only" = true ]; then
        verdict="suspicious"
        status_text="system DNS returns private or local address"
    fi

    printf '{"name":"%s","resolver":"%s","method":"%s","ips":%s,"ips_csv":"%s","verdict":"%s","status_text":"%s"}' \
        "$(analytics_json_escape "$name")" \
        "$(analytics_json_escape "$resolver")" \
        "$(analytics_json_escape "$method")" \
        "$(analytics_csv_to_json "$ips_csv")" \
        "$(analytics_json_escape "$ips_csv")" \
        "$(analytics_json_escape "$verdict")" \
        "$(analytics_json_escape "$status_text")"
    rm -f "$tmp_file"
}

analytics_collect_dns() {
    local host="$1"
    local system_json cloudflare_json google_json
    local system_ips cloudflare_ips google_ips
    local dns_verdict="ok"
    local dns_summary="DNS looks normal; failure is likely at transport/HTTP/TLS level"
    local flags_file="$ANALYTICS_DIR/.dns_flags_$$.txt"

    : > "$flags_file"
    system_json="$(analytics_dns_resolver "$host" system system)"
    cloudflare_json="$(analytics_dns_resolver "$host" cloudflare 1.1.1.1)"
    google_json="$(analytics_dns_resolver "$host" google 8.8.8.8)"
    system_ips="$(analytics_extract_json_field "$system_json" ips_csv)"
    cloudflare_ips="$(analytics_extract_json_field "$cloudflare_json" ips_csv)"
    google_ips="$(analytics_extract_json_field "$google_json" ips_csv)"

    if [ -z "$system_ips" ] && [ -z "$cloudflare_ips" ] && [ -z "$google_ips" ]; then
        dns_verdict="no_dns_answer"
        dns_summary="No DNS answers were received from system or public resolvers"
        printf '%s\n' "no_dns_answer" >> "$flags_file"
    elif [ -n "$system_ips" ] && printf '%s\n' "$system_ips" | tr ',' '\n' | while read -r ip; do analytics_ip_is_bad "$ip"; done; then
        dns_verdict="dns_suspect"
        dns_summary="System DNS returns private or local addresses"
        printf '%s\n' "system_private_ip" >> "$flags_file"
    elif [ -n "$cloudflare_ips" ] && [ -n "$google_ips" ] && [ "$cloudflare_ips" = "$google_ips" ] && [ "$system_ips" != "$cloudflare_ips" ]; then
        dns_verdict="dns_mismatch"
        dns_summary="System DNS differs from public resolvers"
        printf '%s\n' "resolver_mismatch" >> "$flags_file"
    elif [ -z "$system_ips" ] && { [ -n "$cloudflare_ips" ] || [ -n "$google_ips" ]; }; then
        dns_verdict="dns_mismatch"
        dns_summary="System DNS returned no answer while public resolvers returned records"
        printf '%s\n' "system_no_answer" >> "$flags_file"
    fi

    printf '{"hostname":"%s","system":%s,"comparisons":[%s,%s],"suspicious_flags":%s,"verdict":"%s","summary":"%s"}' \
        "$(analytics_json_escape "$host")" \
        "$system_json" \
        "$cloudflare_json" \
        "$google_json" \
        "$(analytics_json_array_from_file "$flags_file")" \
        "$(analytics_json_escape "$dns_verdict")" \
        "$(analytics_json_escape "$dns_summary")"
    rm -f "$flags_file"
}

analytics_probe_curl() {
    local label="$1"
    local target="$2"
    shift 2
    local body_file="$ANALYTICS_DIR/.${label}_body_$$.txt"
    local head_file="$ANALYTICS_DIR/.${label}_head_$$.txt"
    local err_file="$ANALYTICS_DIR/.${label}_err_$$.txt"
    local info curl_code status_code redirect_url verdict error_class snippet stderr_text

    : > "$body_file"
    : > "$head_file"
    : > "$err_file"
    info="$(curl -sS -L --max-time 6 -D "$head_file" -o "$body_file" -w '%{http_code}\t%{url_effective}' "$@" "$target" 2>"$err_file")"
    curl_code=$?
    status_code="$(printf '%s' "$info" | awk -F '\t' '{print $1}')"
    redirect_url="$(printf '%s' "$info" | awk -F '\t' '{print $2}')"
    snippet="$(tr '\n' ' ' < "$body_file" | sed 's/[[:space:]]\+/ /g' | cut -c1-180)"
    stderr_text="$(tr '\n' ' ' < "$err_file" | cut -c1-180)"
    verdict="ok"
    error_class=""

    if [ "$curl_code" -ne 0 ] || [ -z "$status_code" ] || [ "$status_code" = "000" ]; then
        verdict="fail"
        if grep -qi 'timed out' "$err_file"; then
            error_class="timeout"
        elif grep -Eqi 'reset|refused|failed to connect|network is unreachable|no route' "$err_file"; then
            error_class="connectivity"
        else
            error_class="curl_error"
        fi
    fi

    printf '{"label":"%s","verdict":"%s","http_code":"%s","redirect_url":"%s","error_class":"%s","snippet":"%s","stderr":"%s"}' \
        "$(analytics_json_escape "$label")" \
        "$(analytics_json_escape "$verdict")" \
        "$(analytics_json_escape "$status_code")" \
        "$(analytics_json_escape "$redirect_url")" \
        "$(analytics_json_escape "$error_class")" \
        "$(analytics_json_escape "$snippet")" \
        "$(analytics_json_escape "$stderr_text")"
    rm -f "$body_file" "$head_file" "$err_file"
}

analytics_transport_classify() {
    local plain_json="$1"
    local tls12_json="$2"
    local tls13_json="$3"
    local plain_verdict tls12_verdict tls13_verdict snippet verdict summary

    plain_verdict="$(analytics_extract_json_field "$plain_json" verdict)"
    tls12_verdict="$(analytics_extract_json_field "$tls12_json" verdict)"
    tls13_verdict="$(analytics_extract_json_field "$tls13_json" verdict)"
    snippet="$(analytics_extract_json_field "$plain_json" snippet)"
    verdict="ok"
    summary="Transport looks normal"

    case " $snippet " in
        *" access denied "*|*" forbidden "*|*" blocked "*|*" unavailable for legal reasons "*)
            verdict="likely_block_page"
            summary="Response resembles a block page"
            ;;
        *" welcome to nginx "*|*" apache2 "*|*" index of / "*|*" stub "*)
            verdict="likely_redirect_or_stub"
            summary="Response resembles a stub or redirect page"
            ;;
    esac
    if [ "$plain_verdict" != "ok" ] && [ "$tls12_verdict" != "ok" ] && [ "$tls13_verdict" != "ok" ]; then
        verdict="transport_blocked"
        summary="DNS looks normal, but HTTPS/TLS fails"
    elif [ "$tls12_verdict" = "ok" ] && [ "$tls13_verdict" != "ok" ]; then
        verdict="tls_partial"
        summary="TLS 1.2 works, but TLS 1.3 fails"
    elif [ "$tls13_verdict" = "ok" ] && [ "$tls12_verdict" != "ok" ]; then
        verdict="tls_partial"
        summary="TLS 1.3 works, but TLS 1.2 fails"
    fi
    printf '%s\t%s\n' "$verdict" "$summary"
}

analytics_collect_http_tls() {
    local target="$1"
    local plain_json tls12_json tls13_json verdict summary
    plain_json="$(analytics_probe_curl plain "$target")"
    tls12_json="$(analytics_probe_curl tls12 "$target" --tls-max 1.2)"
    tls13_json="$(analytics_probe_curl tls13 "$target" --tlsv1.3)"
    IFS=$'\t' read -r verdict summary <<EOF
$(analytics_transport_classify "$plain_json" "$tls12_json" "$tls13_json")
EOF
    printf '{"plain":%s,"tls12":%s,"tls13":%s,"verdict":"%s","summary":"%s"}' \
        "$plain_json" "$tls12_json" "$tls13_json" "$(analytics_json_escape "$verdict")" "$(analytics_json_escape "$summary")"
}

analytics_results_json() {
    local run_file="$1"
    [ -f "$run_file" ] || {
        printf '[]'
        return
    }
    awk -F '\t' '
        BEGIN { printf "["; first=1 }
        NF >= 12 {
            if (!first) printf ","
            first=0
            gsub(/\\/,"\\\\",$7); gsub(/"/,"\\\"",$7)
            gsub(/\\/,"\\\\",$8); gsub(/"/,"\\\"",$8)
            printf "{\"strategy\":%s,\"result\":\"%s\",\"reason\":\"%s\",\"elapsed_ms\":%s}", $6, $7, $8, $9
        }
        END { printf "]" }
    ' "$run_file"
}

analytics_collect_blockcheck_context() {
    local recommendation_json="$1"
    local run_file="$2"
    local best backups failed results_count stable_count unstable_count fail_count
    best="$(printf '%s\n' "$recommendation_json" | sed -n -E 's/.*"best_strategy":(null|[0-9]+).*/\1/p' | head -n1)"
    backups="$(printf '%s\n' "$recommendation_json" | sed -n -E 's/.*"backup_strategies":\[([^]]*)\].*/\1/p' | head -n1 | tr -d ' ')"
    failed="$(printf '%s\n' "$recommendation_json" | sed -n -E 's/.*"failed_strategies":\[([^]]*)\].*/\1/p' | head -n1 | tr -d ' ')"
    results_count="$(printf '%s\n' "$recommendation_json" | sed -n -E 's/.*"results_count":([0-9]+).*/\1/p' | head -n1)"
    stable_count="$(printf '%s\n' "$recommendation_json" | sed -n -E 's/.*"stable_count":([0-9]+).*/\1/p' | head -n1)"
    unstable_count="$(printf '%s\n' "$recommendation_json" | sed -n -E 's/.*"unstable_count":([0-9]+).*/\1/p' | head -n1)"
    fail_count="$(printf '%s\n' "$recommendation_json" | sed -n -E 's/.*"fail_count":([0-9]+).*/\1/p' | head -n1)"
    printf '{"best_strategy":%s,"backup_strategies":%s,"failed_strategies":%s,"results_count":%s,"stable_count":%s,"unstable_count":%s,"fail_count":%s,"results":%s}' \
        "${best:-null}" \
        "$(blockcheck_json_array_from_csv "$backups")" \
        "$(blockcheck_json_array_from_csv "$failed")" \
        "${results_count:-0}" \
        "${stable_count:-0}" \
        "${unstable_count:-0}" \
        "${fail_count:-0}" \
        "$(analytics_results_json "$run_file")"
}

analytics_hints_file() {
    local dns_verdict="$1"
    local transport_verdict="$2"
    local blockcheck_json="$3"
    local hint_file="$ANALYTICS_DIR/.hints_$$.txt"
    local stable_count fail_count
    stable_count="$(printf '%s\n' "$blockcheck_json" | sed -n -E 's/.*"stable_count":([0-9]+).*/\1/p' | head -n1)"
    fail_count="$(printf '%s\n' "$blockcheck_json" | sed -n -E 's/.*"fail_count":([0-9]+).*/\1/p' | head -n1)"
    : > "$hint_file"
    case "$dns_verdict" in
        dns_mismatch) echo "Compare system DNS with public resolvers; resolver-level interference is likely." >> "$hint_file" ;;
        dns_suspect) echo "System DNS returned private or local IPs; check router DNS settings and forced resolver policies." >> "$hint_file" ;;
        no_dns_answer) echo "DNS resolution is failing before transport checks; verify upstream resolvers and routing." >> "$hint_file" ;;
    esac
    case "$transport_verdict" in
        transport_blocked) echo "DNS looks usable, but HTTPS/TLS fails; focus on transport desync strategies." >> "$hint_file" ;;
        tls_partial) echo "One TLS version works and another fails; tune TLS-specific strategies and fake blobs." >> "$hint_file" ;;
        likely_block_page|likely_redirect_or_stub) echo "The response resembles a block or stub page; add response-specific regression targets for this domain." >> "$hint_file" ;;
    esac
    if [ "${stable_count:-0}" -gt 0 ] && [ "${fail_count:-0}" -gt 0 ]; then
        echo "The target is strategy-sensitive; keep several backups and avoid overfitting to a single lock." >> "$hint_file"
    fi
    [ -s "$hint_file" ] || echo "Not enough evidence for a targeted recommendation yet; collect more reports for this domain." >> "$hint_file"
    printf '%s\n' "$hint_file"
}

analytics_build_verdict() {
    local dns_json="$1"
    local transport_json="$2"
    local blockcheck_json="$3"
    local dns_verdict transport_verdict block_class short_text recommendation_note stable_count fail_count
    dns_verdict="$(analytics_extract_json_field "$dns_json" verdict)"
    transport_verdict="$(analytics_extract_json_field "$transport_json" verdict)"
    stable_count="$(printf '%s\n' "$blockcheck_json" | sed -n -E 's/.*"stable_count":([0-9]+).*/\1/p' | head -n1)"
    fail_count="$(printf '%s\n' "$blockcheck_json" | sed -n -E 's/.*"fail_count":([0-9]+).*/\1/p' | head -n1)"
    block_class="unclear"
    short_text="Not enough evidence for a confident classification"
    recommendation_note="Review DNS and transport sections before adjusting strategy sets."

    case "$dns_verdict" in
        dns_suspect|dns_mismatch|no_dns_answer)
            block_class="$dns_verdict"
            short_text="$(analytics_extract_json_field "$dns_json" summary)"
            recommendation_note="DNS behavior is suspicious; strategy tuning alone may not fix this target."
            ;;
        *)
            case "$transport_verdict" in
                transport_blocked|tls_partial|likely_block_page|likely_redirect_or_stub)
                    block_class="$transport_verdict"
                    short_text="$(analytics_extract_json_field "$transport_json" summary)"
                    recommendation_note="Transport-side blocking is more likely than DNS poisoning."
                    ;;
            esac
            ;;
    esac

    if [ "${stable_count:-0}" -gt 0 ] && [ "${fail_count:-0}" -gt 0 ] && { [ "$block_class" = "unclear" ] || [ "$block_class" = "transport_blocked" ] || [ "$block_class" = "tls_partial" ]; }; then
        block_class="strategy_sensitive"
        short_text="One strategy succeeds while others fail; the target is strategy-sensitive"
        recommendation_note="Preserve the current working strategy as primary and keep backups in the profile."
    fi

    printf '{"blocking_class":"%s","dns_verdict":"%s","transport_verdict":"%s","short_text":"%s","recommendation_note":"%s"}' \
        "$(analytics_json_escape "$block_class")" \
        "$(analytics_json_escape "$dns_verdict")" \
        "$(analytics_json_escape "$transport_verdict")" \
        "$(analytics_json_escape "$short_text")" \
        "$(analytics_json_escape "$recommendation_note")"
}

analytics_last_json() {
    analytics_init_dirs
    if [ -s "$ANALYTICS_LAST_REPORT_FILE" ]; then
        cat "$ANALYTICS_LAST_REPORT_FILE"
    else
        echo '{"run_id":"","created_at":"","mode":"","profile_id":"","profile_name":"","target":"","source":{"type":"","run_file":"","recommendation_file":"","used_existing_blockcheck":false},"summary":{"blocking_class":"unclear","dns_verdict":"unknown","transport_verdict":"unknown","short_text":"Analytics report is not available yet.","recommendation_note":""},"dns":{"hostname":"","system":{"name":"system","resolver":"system","method":"unavailable","ips":[],"ips_csv":"","verdict":"unknown","status_text":"not checked"},"comparisons":[],"suspicious_flags":[],"verdict":"unknown","summary":"not checked"},"transport":{"plain":{"label":"plain","verdict":"unknown","http_code":"","redirect_url":"","error_class":"","snippet":"","stderr":""},"tls12":{"label":"tls12","verdict":"unknown","http_code":"","redirect_url":"","error_class":"","snippet":"","stderr":""},"tls13":{"label":"tls13","verdict":"unknown","http_code":"","redirect_url":"","error_class":"","snippet":"","stderr":""},"verdict":"unknown","summary":"not checked"},"blockcheck":{"best_strategy":null,"backup_strategies":[],"failed_strategies":[],"results_count":0,"stable_count":0,"unstable_count":0,"fail_count":0,"results":[]},"hints":[]}'
    fi
}

analytics_run_report() {
    local mode="$1"
    local profile_id="${2:-3}"
    local target="$3"
    local _source_run="${4:-}"
    local use_existing="${5:-0}"
    local recommendation_json run_file recommendation_file source_type profile_name normalized_target host report_id created_at
    local dns_json transport_json blockcheck_json summary_json hints_path

    analytics_init_dirs
    profile_name="$(blockcheck_profile_name "$profile_id")"
    analytics_progress_write "prepare" "Preparing analytics report" "$target" "$profile_id" "$profile_name"

    case "$mode" in
        last)
            recommendation_json="$(blockcheck_last_context_json)"
            run_file="$(printf '%s\n' "$recommendation_json" | sed -n -E 's/.*"run_file":"([^"]*)".*/\1/p' | head -n1)"
            recommendation_file="$BLOCKCHECK_LAST_RECOMMENDATION_FILE"
            target="$(printf '%s\n' "$recommendation_json" | sed -n -E 's/.*"target":"([^"]*)".*/\1/p' | head -n1)"
            profile_id="$(printf '%s\n' "$recommendation_json" | sed -n -E 's/.*"profile_id":"([^"]*)".*/\1/p' | head -n1)"
            profile_id="${profile_id:-3}"
            profile_name="$(blockcheck_profile_name "$profile_id")"
            source_type="blockcheck_last"
            ;;
        run)
            analytics_progress_write "blockcheck" "Running fresh blockcheck scan" "$target" "$profile_id" "$profile_name"
            if [ -n "$target" ]; then
                blockcheck_run_custom_scan "$target" "$profile_id" || return 1
            else
                blockcheck_run_profile_scan "$profile_id" || return 1
            fi
            recommendation_json="$(blockcheck_last_context_json)"
            run_file="$(printf '%s\n' "$recommendation_json" | sed -n -E 's/.*"run_file":"([^"]*)".*/\1/p' | head -n1)"
            recommendation_file="$BLOCKCHECK_LAST_RECOMMENDATION_FILE"
            target="$(printf '%s\n' "$recommendation_json" | sed -n -E 's/.*"target":"([^"]*)".*/\1/p' | head -n1)"
            source_type="extended_run"
            ;;
        target)
            normalized_target="$(analytics_normalize_target "$target")"
            recommendation_json="$(blockcheck_last_context_json)"
            if [ "$use_existing" = "1" ] && [ "$(printf '%s\n' "$recommendation_json" | sed -n -E 's/.*"target":"([^"]*)".*/\1/p' | head -n1)" = "$normalized_target" ] && [ "$(printf '%s\n' "$recommendation_json" | sed -n -E 's/.*"profile_id":"([^"]*)".*/\1/p' | head -n1)" = "$profile_id" ]; then
                run_file="$(printf '%s\n' "$recommendation_json" | sed -n -E 's/.*"run_file":"([^"]*)".*/\1/p' | head -n1)"
                recommendation_file="$BLOCKCHECK_LAST_RECOMMENDATION_FILE"
                target="$normalized_target"
                source_type="blockcheck_last"
            else
                analytics_progress_write "blockcheck" "Running blockcheck for target" "$normalized_target" "$profile_id" "$profile_name"
                blockcheck_run_custom_scan "$normalized_target" "$profile_id" || return 1
                recommendation_json="$(blockcheck_last_context_json)"
                run_file="$(printf '%s\n' "$recommendation_json" | sed -n -E 's/.*"run_file":"([^"]*)".*/\1/p' | head -n1)"
                recommendation_file="$BLOCKCHECK_LAST_RECOMMENDATION_FILE"
                target="$(printf '%s\n' "$recommendation_json" | sed -n -E 's/.*"target":"([^"]*)".*/\1/p' | head -n1)"
                source_type="extended_run"
            fi
            ;;
        *)
            return 1
            ;;
    esac

    [ -n "$target" ] || return 1
    normalized_target="$(analytics_normalize_target "$target")"
    host="$(analytics_target_host "$normalized_target")"
    created_at="$(date '+%Y-%m-%d %H:%M:%S')"
    report_id="$(date +%Y%m%d_%H%M%S)_${profile_id}_$$"
    analytics_progress_write "dns" "Collecting DNS diagnostics" "$normalized_target" "$profile_id" "$profile_name"
    dns_json="$(analytics_collect_dns "$host")"
    analytics_progress_write "transport" "Collecting HTTPS and TLS diagnostics" "$normalized_target" "$profile_id" "$profile_name"
    transport_json="$(analytics_collect_http_tls "$normalized_target")"
    analytics_progress_write "classify" "Summarizing blocking behavior" "$normalized_target" "$profile_id" "$profile_name"
    blockcheck_json="$(analytics_collect_blockcheck_context "$recommendation_json" "$run_file")"
    summary_json="$(analytics_build_verdict "$dns_json" "$transport_json" "$blockcheck_json")"
    hints_path="$(analytics_hints_file "$(analytics_extract_json_field "$dns_json" verdict)" "$(analytics_extract_json_field "$transport_json" verdict)" "$blockcheck_json")"
    analytics_progress_write "finalize" "Saving analytics report" "$normalized_target" "$profile_id" "$profile_name"

    cat > "$ANALYTICS_HISTORY_DIR/${report_id}.json" <<EOF
{"run_id":"$(analytics_json_escape "$report_id")","created_at":"$(analytics_json_escape "$created_at")","mode":"$(analytics_json_escape "$mode")","profile_id":"$(analytics_json_escape "$profile_id")","profile_name":"$(analytics_json_escape "$profile_name")","target":"$(analytics_json_escape "$normalized_target")","source":{"type":"$(analytics_json_escape "$source_type")","run_file":"$(analytics_json_escape "$run_file")","recommendation_file":"$(analytics_json_escape "$recommendation_file")","used_existing_blockcheck":$([ "$source_type" = "blockcheck_last" ] && echo true || echo false)},"summary":$summary_json,"dns":$dns_json,"transport":$transport_json,"blockcheck":$blockcheck_json,"hints":$(analytics_json_array_from_file "$hints_path")}
EOF
    cp "$ANALYTICS_HISTORY_DIR/${report_id}.json" "$ANALYTICS_LAST_REPORT_FILE"
    rm -f "$hints_path"
    printf '%s\n' "$ANALYTICS_HISTORY_DIR/${report_id}.json"
}
