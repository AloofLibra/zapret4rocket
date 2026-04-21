#!/bin/bash

policy_root="${policy_root:-/opt/zapret2/extra_strats/cache/policy}"
policy_catalog_root="$policy_root/catalog"
policy_catalog_profiles_root="$policy_catalog_root/profiles"
policy_state_root="$policy_root/state"
policy_state_profiles_root="$policy_state_root/profiles"
policy_state_domains_root="$policy_state_root/domains"
policy_jobs_root="$policy_root/jobs"
policy_jobs_pending_root="$policy_jobs_root/pending"
policy_jobs_running_root="$policy_jobs_root/running"
policy_jobs_done_root="$policy_jobs_root/done"
policy_jobs_failed_root="$policy_jobs_root/failed"
policy_sessions_root="$policy_root/sessions"
policy_sessions_discovery_root="$policy_sessions_root/discovery"
policy_events_root="$policy_root/events"
policy_snapshot_file="$policy_state_root/runtime_snapshot.lua"
policy_snapshot_lkg_file="$policy_state_root/runtime_snapshot.last_good.lua"

policy_init_dirs() {
    mkdir -p \
        "$policy_catalog_profiles_root" \
        "$policy_state_profiles_root" \
        "$policy_state_domains_root" \
        "$policy_jobs_pending_root" \
        "$policy_jobs_running_root" \
        "$policy_jobs_done_root" \
        "$policy_jobs_failed_root" \
        "$policy_sessions_discovery_root" \
        "$policy_events_root"
}

policy_atomic_replace() {
    local src="$1"
    local dst="$2"
    local dir base tmp
    dir="$(dirname "$dst")"
    base="$(basename "$dst")"
    mkdir -p "$dir" || return 1
    tmp="$dir/.${base}.tmp.$$"
    cp "$src" "$tmp" || {
        rm -f "$tmp"
        return 1
    }
    mv -f "$tmp" "$dst"
}

policy_write_from_file() {
    local dst="$1"
    local src="$2"
    [ -f "$src" ] || return 1
    policy_atomic_replace "$src" "$dst"
}

policy_read_profile_state() {
    local profile="$1"
    cat "$policy_state_profiles_root/$profile.json"
}

policy_write_profile_state() {
    local profile="$1"
    local file="$2"
    policy_init_dirs
    policy_write_from_file "$policy_state_profiles_root/$profile.json" "$file"
}

policy_read_domain_state() {
    local host="$1"
    cat "$policy_state_domains_root/$host.json"
}

policy_write_domain_state() {
    local host="$1"
    local file="$2"
    policy_init_dirs
    policy_write_from_file "$policy_state_domains_root/$host.json" "$file"
}

policy_read_catalog() {
    local profile="$1"
    cat "$policy_catalog_profiles_root/$profile.json"
}

policy_write_catalog() {
    local profile="$1"
    local file="$2"
    policy_init_dirs
    policy_write_from_file "$policy_catalog_profiles_root/$profile.json" "$file"
}

policy_write_catalog_lua() {
    local profile="$1"
    local file="$2"
    policy_init_dirs
    policy_write_from_file "$policy_catalog_profiles_root/$profile.lua" "$file"
}

policy_enqueue_job() {
    local file="$1"
    policy_init_dirs
    policy_write_from_file "$policy_jobs_pending_root/$(basename "$file")" "$file"
}

policy_claim_job() {
    local file base
    for file in "$policy_jobs_pending_root"/*.json; do
        [ -e "$file" ] || return 1
        base="$(basename "$file")"
        if mv "$file" "$policy_jobs_running_root/$base" 2>/dev/null; then
            printf '%s\n' "$policy_jobs_running_root/$base"
            return 0
        fi
    done
    return 1
}

policy_finish_job() {
    local job="$1"
    local result="$2"
    policy_write_from_file "$policy_jobs_done_root/$(basename "$job")" "$result"
    rm -f "$job"
}

policy_fail_job() {
    local job="$1"
    local result="$2"
    policy_write_from_file "$policy_jobs_failed_root/$(basename "$job")" "$result"
    rm -f "$job"
}

policy_json_compact() {
    tr -d '\r\n\t' < "$1" | sed 's/[[:space:]]\+/ /g'
}

policy_json_get_string() {
    local file="$1"
    local key="$2"
    local raw data
    raw="$(policy_json_compact "$file")"
    data="${raw#*\"$key\"}"
    [ "$data" != "$raw" ] || return 1
    data="${data#*:}"
    data="$(printf '%s' "$data" | sed 's/^ *//')"
    data="${data#\"}"
    printf '%s' "${data%%\"*}"
}

policy_json_get_number() {
    local file="$1"
    local key="$2"
    local raw data
    raw="$(policy_json_compact "$file")"
    data="${raw#*\"$key\"}"
    [ "$data" != "$raw" ] || return 1
    data="${data#*:}"
    data="$(printf '%s' "$data" | sed 's/^ *//')"
    printf '%s' "$data" | sed -n 's/^\(-\{0,1\}[0-9][0-9.]*\).*$/\1/p'
}

policy_json_get_array_strings_lua() {
    local file="$1"
    local key="$2"
    local raw data array out=1 item
    raw="$(policy_json_compact "$file")"
    data="${raw#*\"$key\"}"
    [ "$data" != "$raw" ] || {
        printf '{}'
        return 0
    }
    data="${data#*:}"
    array="$(printf '%s' "$data" | sed -n 's/^[^[]*\[\([^]]*\)\].*$/\1/p')"
    [ -n "$array" ] || {
        printf '{}'
        return 0
    }
    printf '{'
    OLDIFS="$IFS"
    IFS=','
    for item in $array; do
        item="$(printf '%s' "$item" | sed 's/^ *"//; s/" *$//; s/\\"/"/g')"
        [ -n "$item" ] || continue
        [ "$out" -eq 1 ] || printf ','
        out=0
        printf '%s' "\"$(printf '%s' "$item" | sed 's/\\/\\\\/g; s/"/\\"/g')\""
    done
    IFS="$OLDIFS"
    printf '}'
}

policy_lua_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

policy_rebuild_runtime_snapshot() {
    local tmp
    local generated_at
    local first_profile=1
    local first_candidate=1
    local first_domain=1
    local file profile candidate_block active_candidate active_family mode status source confidence last_validated fallback_chain host domain_profile domain_candidate domain_status

    policy_init_dirs
    tmp="$(mktemp "${TMPDIR:-/tmp}/policy-snapshot.XXXXXX")" || return 1
    generated_at="$(date +%Y-%m-%dT%H:%M:%S%z)"

    {
        printf 'POLICY_RUNTIME = {\n'
        printf '  version = 1,\n'
        printf '  generated_at = "%s",\n' "$generated_at"
        printf '  profiles = {\n'
        for file in "$policy_state_profiles_root"/*.json; do
            [ -e "$file" ] || continue
            profile="$(basename "$file" .json)"
            mode="$(policy_json_get_string "$file" "mode" 2>/dev/null || true)"
            active_candidate="$(policy_json_get_string "$file" "active_candidate_id" 2>/dev/null || true)"
            active_family="$(policy_json_get_string "$file" "active_family_id" 2>/dev/null || true)"
            status="$(policy_json_get_string "$file" "status" 2>/dev/null || true)"
            source="$(policy_json_get_string "$file" "source" 2>/dev/null || true)"
            confidence="$(policy_json_get_number "$file" "confidence" 2>/dev/null || true)"
            last_validated="$(policy_json_get_string "$file" "last_validated_at" 2>/dev/null || true)"
            fallback_chain="$(policy_json_get_array_strings_lua "$file" "fallback_chain")"
            [ "$first_profile" -eq 1 ] || printf ',\n'
            first_profile=0
            printf '    ["%s"] = {\n' "$(policy_lua_escape "$profile")"
            printf '      mode = "%s",\n' "$(policy_lua_escape "${mode:-unknown}")"
            printf '      active_candidate_id = "%s",\n' "$(policy_lua_escape "$active_candidate")"
            printf '      active_family_id = "%s",\n' "$(policy_lua_escape "$active_family")"
            printf '      status = "%s",\n' "$(policy_lua_escape "${status:-unknown}")"
            if [ -n "$confidence" ]; then
                printf '      confidence = %s,\n' "$confidence"
            else
                printf '      confidence = 0,\n'
            fi
            printf '      fallback_chain = %s,\n' "$fallback_chain"
            printf '      last_validated_at = "%s",\n' "$(policy_lua_escape "$last_validated")"
            printf '      source = "%s"\n' "$(policy_lua_escape "$source")"
            printf '    }'
        done
        printf '\n  },\n'
        printf '  candidates = {\n'
        for file in "$policy_catalog_profiles_root"/*.lua; do
            [ -e "$file" ] || continue
            candidate_block="$(cat "$file")"
            [ -n "$candidate_block" ] || continue
            [ "$first_candidate" -eq 1 ] || printf ',\n'
            first_candidate=0
            printf '%s' "$candidate_block"
        done
        printf '\n  },\n'
        printf '  domains = {\n'
        for file in "$policy_state_domains_root"/*.json; do
            [ -e "$file" ] || continue
            host="$(basename "$file" .json)"
            domain_profile="$(policy_json_get_number "$file" "profile" 2>/dev/null || true)"
            domain_candidate="$(policy_json_get_string "$file" "active_candidate_id" 2>/dev/null || true)"
            domain_status="$(policy_json_get_string "$file" "status" 2>/dev/null || true)"
            [ "$first_domain" -eq 1 ] || printf ',\n'
            first_domain=0
            printf '    ["%s"] = {\n' "$(policy_lua_escape "$host")"
            printf '      profile = %s,\n' "${domain_profile:-0}"
            printf '      active_candidate_id = "%s",\n' "$(policy_lua_escape "$domain_candidate")"
            printf '      status = "%s"\n' "$(policy_lua_escape "${domain_status:-unknown}")"
            printf '    }'
        done
        printf '\n  }\n'
        printf '}\n'
        printf 'return POLICY_RUNTIME\n'
    } > "$tmp" || {
        rm -f "$tmp"
        return 1
    }

    policy_atomic_replace "$tmp" "$policy_snapshot_file" || {
        rm -f "$tmp"
        return 1
    }
    cp "$policy_snapshot_file" "$policy_snapshot_lkg_file" 2>/dev/null || true
    rm -f "$tmp"
}

policy_log_event() {
    local event_type="$1"
    local payload="$2"
    local tmp
    policy_init_dirs
    tmp="$(mktemp "${TMPDIR:-/tmp}/policy-event.XXXXXX")" || return 1
    if [ -f "$policy_events_root/events.log" ]; then
        cat "$policy_events_root/events.log" > "$tmp"
    fi
    printf '{"ts":"%s","type":"%s","payload":%s}\n' \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" \
        "$(policy_lua_escape "$event_type")" \
        "${payload:-null}" >> "$tmp"
    policy_atomic_replace "$tmp" "$policy_events_root/events.log"
    rm -f "$tmp"
}
