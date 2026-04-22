local POLICY_RESCUE_CANDIDATES = {
    ["1"] = {
        profile = 1,
        rescue_id = "rescue-p1",
        constraints = { payload = { tls_client_hello = true } },
        steps = {
            { op = "fake", args = { blob = "fake_default_tls", tcp_ts = -1000, repeats = 2 } },
            { op = "multisplit", args = { pos = "1,midsld" } },
        }
    },
    ["2"] = {
        profile = 2,
        rescue_id = "rescue-p2",
        constraints = { payload = { tls_client_hello = true } },
        steps = {
            { op = "fake", args = { blob = "fake_default_tls", tcp_ts = -1000, repeats = 2 } },
            { op = "multisplit", args = { pos = "1,midsld" } },
        }
    }
}

local function pr_profile_from_desync(desync)
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

local function pr_validator_testing(profile_id)
    if type(ps_get_profile) ~= "function" then
        return false
    end
    local profile = ps_get_profile(profile_id)
    return type(profile) == "table" and profile.mode == "validator_testing"
end

function policy_rescue(ctx, desync)
    local profile_id = pr_profile_from_desync(desync)
    if pr_validator_testing(profile_id) then
        return VERDICT_PASS
    end
    local candidate = POLICY_RESCUE_CANDIDATES[profile_id]
    if not candidate then
        return VERDICT_PASS
    end
    local verdict = se_execute_candidate(ctx, desync, candidate)
    return verdict or VERDICT_PASS
end
