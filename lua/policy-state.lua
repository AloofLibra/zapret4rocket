local POLICY_SNAPSHOT_PATH = "/opt/zapret2/extra_strats/cache/policy/state/runtime_snapshot.lua"
local POLICY_SNAPSHOT_TTL = 3

POLICY_STATE_CACHE = POLICY_STATE_CACHE or {
    loaded_at = 0,
    snapshot = nil,
    ok = false
}

local function ps_now()
    if os and os.time then
        return os.time()
    end
    return 0
end

function ps_load_snapshot(force)
    local now = ps_now()
    if not force and POLICY_STATE_CACHE.snapshot and POLICY_STATE_CACHE.ok and (now - POLICY_STATE_CACHE.loaded_at) < POLICY_SNAPSHOT_TTL then
        return POLICY_STATE_CACHE.snapshot
    end

    local ok, snapshot = pcall(dofile, POLICY_SNAPSHOT_PATH)
    POLICY_STATE_CACHE.loaded_at = now
    POLICY_STATE_CACHE.ok = ok and type(snapshot) == "table"
    POLICY_STATE_CACHE.snapshot = POLICY_STATE_CACHE.ok and snapshot or nil
    return POLICY_STATE_CACHE.snapshot
end

function ps_get_profile(profile_id)
    local snapshot = ps_load_snapshot(false)
    if not snapshot or type(snapshot.profiles) ~= "table" then
        return nil
    end
    return snapshot.profiles[tostring(profile_id)]
end

function ps_get_candidate(candidate_id)
    local snapshot = ps_load_snapshot(false)
    if not snapshot or type(snapshot.candidates) ~= "table" then
        return nil
    end
    return snapshot.candidates[candidate_id]
end

function ps_get_domain(hostkey)
    local snapshot = ps_load_snapshot(false)
    if not snapshot or type(snapshot.domains) ~= "table" then
        return nil
    end
    return snapshot.domains[hostkey]
end

function ps_get_active_candidate(profile_id, hostkey)
    local domain = hostkey and ps_get_domain(hostkey) or nil
    if domain and domain.active_candidate_id then
        return ps_get_candidate(domain.active_candidate_id)
    end

    local profile = ps_get_profile(profile_id)
    if profile and profile.active_candidate_id then
        return ps_get_candidate(profile.active_candidate_id)
    end

    return nil
end

function ps_snapshot_ok()
    ps_load_snapshot(false)
    return POLICY_STATE_CACHE.ok == true
end
