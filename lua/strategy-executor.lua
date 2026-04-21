local function se_log(msg)
    if type(DLOG) == "function" then
        DLOG("strategy-executor: " .. tostring(msg))
    end
end

local function se_payload_key(desync)
    if not desync then
        return nil
    end
    return desync.l7payload or desync.payload_type or desync.payload or nil
end

local function se_constraints_payload_match(desync, payload_map)
    if type(payload_map) ~= "table" then
        return true
    end
    local key = se_payload_key(desync)
    if not key then
        return false
    end
    return payload_map[key] == true
end

function se_constraints_match(desync, candidate)
    if type(candidate) ~= "table" then
        return false
    end
    if type(candidate.constraints) ~= "table" then
        return true
    end
    if candidate.constraints.payload and not se_constraints_payload_match(desync, candidate.constraints.payload) then
        return false
    end
    return true
end

function se_execute_step(ctx, desync, step)
    if type(step) ~= "table" then
        return nil, "invalid_step"
    end
    local handlers = type(sl_handlers) == "function" and sl_handlers() or nil
    local handler = handlers and handlers[step.op] or nil
    if type(handler) ~= "function" then
        return nil, "missing_handler:" .. tostring(step.op)
    end
    return handler(ctx, desync, step.args or {})
end

function se_execute_rescue(ctx, desync, rescue_id)
    if not rescue_id or type(policy_rescue) ~= "function" then
        return VERDICT_PASS
    end
    se_log("using rescue " .. tostring(rescue_id))
    local ok, verdict = pcall(policy_rescue, ctx, desync)
    if not ok then
        return VERDICT_PASS
    end
    return verdict
end

function se_execute_candidate(ctx, desync, candidate)
    if type(candidate) ~= "table" then
        return VERDICT_PASS, "invalid_candidate"
    end
    if not se_constraints_match(desync, candidate) then
        return VERDICT_PASS, "constraints_mismatch"
    end

    local verdict = VERDICT_PASS
    local step_idx, step, step_verdict, err

    for step_idx, step in ipairs(candidate.steps or {}) do
        step_verdict, err = se_execute_step(ctx, desync, step)
        if err then
            candidate.runtime_invalid = true
            candidate.runtime_invalid_reason = err
            se_log("step " .. tostring(step_idx) .. " failed: " .. tostring(err))
            return se_execute_rescue(ctx, desync, candidate.rescue_id), err
        end
        if step_verdict ~= nil then
            verdict = step_verdict
        end
    end

    return verdict, nil
end

se_log("loaded")
