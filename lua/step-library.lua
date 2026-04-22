local function sl_log(msg)
    if type(DLOG) == "function" then
        DLOG("step-library: " .. tostring(msg))
    end
end

local function sl_copy_table(src)
    local dst = {}
    if type(src) ~= "table" then
        return dst
    end
    for k, v in pairs(src) do
        dst[k] = v
    end
    return dst
end

local function sl_invoke_builtin(ctx, desync, op, args)
    local fn = _G[op]
    if type(fn) ~= "function" then
        return nil, "missing_builtin:" .. tostring(op)
    end

    local prev_arg = desync.arg
    local merged_arg = sl_copy_table(prev_arg)
    local arg_key, arg_value

    for arg_key, arg_value in pairs(args or {}) do
        merged_arg[arg_key] = arg_value
    end

    desync.arg = merged_arg
    local ok, verdict = pcall(fn, ctx, desync)
    desync.arg = prev_arg

    if not ok then
        return nil, "runtime_error:" .. tostring(verdict)
    end
    return verdict, nil
end

function sl_fake(ctx, desync, args)
    return sl_invoke_builtin(ctx, desync, "fake", args)
end

function sl_tcpseg(ctx, desync, args)
    return sl_invoke_builtin(ctx, desync, "tcpseg", args)
end

function sl_oob(ctx, desync, args)
    return sl_invoke_builtin(ctx, desync, "oob", args)
end

function sl_syndata(ctx, desync, args)
    return sl_invoke_builtin(ctx, desync, "syndata", args)
end

function sl_multisplit(ctx, desync, args)
    return sl_invoke_builtin(ctx, desync, "multisplit", args)
end

function sl_fakeddisorder(ctx, desync, args)
    return sl_invoke_builtin(ctx, desync, "fakeddisorder", args)
end

function sl_fakedsplit(ctx, desync, args)
    return sl_invoke_builtin(ctx, desync, "fakedsplit", args)
end

function sl_hostfakesplit(ctx, desync, args)
    return sl_invoke_builtin(ctx, desync, "hostfakesplit", args)
end

function sl_multidisorder(ctx, desync, args)
    local impl = _G.MULTIDISORDER or "multidisorder"
    if type(impl) ~= "string" or impl == "" then
        impl = "multidisorder"
    end
    return sl_invoke_builtin(ctx, desync, impl, args)
end

function sl_udplen(ctx, desync, args)
    return sl_invoke_builtin(ctx, desync, "udplen", args)
end

function sl_send(ctx, desync, args)
    return sl_invoke_builtin(ctx, desync, "send", args)
end

function sl_handlers()
    return {
        fake = sl_fake,
        tcpseg = sl_tcpseg,
        oob = sl_oob,
        syndata = sl_syndata,
        multisplit = sl_multisplit,
        fakeddisorder = sl_fakeddisorder,
        fakedsplit = sl_fakedsplit,
        hostfakesplit = sl_hostfakesplit,
        multidisorder = sl_multidisorder,
        udplen = sl_udplen,
        send = sl_send,
    }
end

sl_log("loaded")
