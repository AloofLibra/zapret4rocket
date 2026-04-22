local POLICY_SIGNAL_DIR = "/opt/zapret2/extra_strats/cache/policy/events/runtime-signals"
local POLICY_SIGNAL_TTL = 5

POLICY_ORCHESTRATOR_CACHE = POLICY_ORCHESTRATOR_CACHE or {
    last_signal = {}
}

local function po_log(msg)
    if type(DLOG) == "function" then
        DLOG("policy-orchestrator: " .. tostring(msg))
    end
end

local function po_now()
    if os and os.time then
        return os.time()
    end
    return 0
end

local function po_normalize_host(host)
    if type(host) ~= "string" then
        return nil
    end
    host = string.lower(host)
    host = string.gsub(host, "%.+$", "")
    host = string.gsub(host, "^%.+", "")
    if host == "" then
        return nil
    end
    return host
end

local function po_host_from_desync(desync)
    if not desync then
        return nil
    end
    local host =
        desync.hostname or
        desync.host or
        desync.http_host or
        desync.sni or
        desync.tls_sni or
        desync.server_name or
        (desync.http and desync.http.host) or
        (desync.tls and desync.tls.sni) or
        (desync.arg and (desync.arg.host or desync.arg.hostname or desync.arg.sni or desync.arg.tls_sni))
    return po_normalize_host(host)
end

local function po_profile_from_desync(desync)
    if not desync then
        return "default"
    end
    return tostring(
        desync.profile or
        desync.profile_id or
        desync.profileid or
        desync.profile_num or
        (desync.arg and (desync.arg.profile or desync.arg.key)) or
        desync.func_instance or
        "default"
    )
end

local function po_signal_key(profile_id, hostkey, candidate_id, reason)
    return table.concat({
        tostring(profile_id or "default"),
        tostring(hostkey or "nohost"),
        tostring(candidate_id or "nocandidate"),
        tostring(reason or "runtime")
    }, "|")
end

local function po_mkdir_p(path)
    if type(io.popen) ~= "function" then
        return
    end
    io.popen("mkdir -p '" .. path .. "' >/dev/null 2>&1"):close()
end

function po_queue_revalidate(profile_id, hostkey, candidate_id, reason)
    local now = po_now()
    local key = po_signal_key(profile_id, hostkey, candidate_id, reason)
    local last = POLICY_ORCHESTRATOR_CACHE.last_signal[key] or 0
    if (now - last) < POLICY_SIGNAL_TTL then
        return
    end
    POLICY_ORCHESTRATOR_CACHE.last_signal[key] = now

    po_mkdir_p(POLICY_SIGNAL_DIR)
    local signal_name = string.format(
        "%s/%s.signal",
        POLICY_SIGNAL_DIR,
        tostring(now) .. "-" .. string.gsub(key, "[^%w%-_]+", "_")
    )
    local f = io.open(signal_name, "w")
    if f then
        f:write(string.format(
            '{"ts":"%s","profile":"%s","host":"%s","candidate_id":"%s","reason":"%s"}\n',
            os.date("%Y-%m-%dT%H:%M:%S"),
            tostring(profile_id or ""),
            tostring(hostkey or ""),
            tostring(candidate_id or ""),
            tostring(reason or "runtime")
        ))
        f:close()
    end
end

function po_mark_suspect(profile_id, hostkey, reason)
    po_queue_revalidate(profile_id, hostkey, nil, reason or "suspect")
end

function po_use_fallback(profile_id, hostkey)
    local profile = type(ps_get_profile) == "function" and ps_get_profile(profile_id) or nil
    if type(profile) ~= "table" or type(profile.fallback_chain) ~= "table" then
        return nil
    end
    local fallback_id = profile.fallback_chain[1]
    if not fallback_id then
        return nil
    end
    return type(ps_get_candidate) == "function" and ps_get_candidate(fallback_id) or nil
end

local function po_validator_testing(profile_id)
    local profile = type(ps_get_profile) == "function" and ps_get_profile(profile_id) or nil
    return type(profile) == "table" and profile.mode == "validator_testing"
end

function po_select_candidate(profile_id, hostkey, desync)
    if type(ps_get_active_candidate) ~= "function" then
        return nil
    end
    local candidate = ps_get_active_candidate(profile_id, hostkey)
    if candidate then
        return candidate
    end
    return po_use_fallback(profile_id, hostkey)
end

function policy_orchestrator(ctx, desync)
    local profile_id = po_profile_from_desync(desync)
    local hostkey = po_host_from_desync(desync)

    if type(ps_snapshot_ok) ~= "function" or not ps_snapshot_ok() then
        if po_validator_testing(profile_id) then
            return VERDICT_PASS
        end
        po_log("snapshot unavailable, using rescue")
        return policy_rescue(ctx, desync)
    end

    local candidate = po_select_candidate(profile_id, hostkey, desync)
    if not candidate then
        po_log("no candidate for profile=" .. tostring(profile_id))
        po_mark_suspect(profile_id, hostkey, "no_candidate")
        if po_validator_testing(profile_id) then
            return VERDICT_PASS
        end
        return policy_rescue(ctx, desync)
    end

    local verdict, err = se_execute_candidate(ctx, desync, candidate)
    if err then
        po_mark_suspect(profile_id, hostkey, err)
        po_queue_revalidate(profile_id, hostkey, candidate.candidate_id or candidate.id, err)
    end
    return verdict or VERDICT_PASS
end
