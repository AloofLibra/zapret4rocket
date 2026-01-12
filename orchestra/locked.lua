local LOCKED_PATH = "/opt/zapret2/extra_strats/cache/orchestra/locked.tsv"
local last_load = 0
local cache_ttl = 2
local LOCKED_TLS = {}
local LOCKED_HTTP = {}
local LOCKED_UDP = {}

local function load_locked_tables()
  local now = os.time()
  if now and (now - last_load) < cache_ttl then return end
  last_load = now or 0
  LOCKED_TLS = {}
  LOCKED_HTTP = {}
  LOCKED_UDP = {}

  local f = io.open(LOCKED_PATH, "r")
  if not f then return end
  for line in f:lines() do
    if line ~= "" then
      local p1, p2, p3 = string.match(line, "^([^\t]+)\t([^\t]+)\t([^\t]+)$")
      if p1 then
        local profile = string.lower(p1)
        local proto = string.lower(p2)
        local strat = tonumber(p3)
        if strat then
          if proto == "http" then LOCKED_HTTP[profile] = strat
          elseif proto == "udp" then LOCKED_UDP[profile] = strat
          else LOCKED_TLS[profile] = strat end
        end
      else
        local p, s = string.match(line, "^([^\t]+)\t([^\t]+)$")
        if p and s then
          local strat = tonumber(s)
          if strat then LOCKED_TLS[string.lower(p)] = strat end
        end
      end
    end
  end
  f:close()
end

function locked_strategy_for_profile(profile, proto)
  if not profile then return nil end
  profile = string.lower(tostring(profile))
  proto = string.lower(tostring(proto or "tls"))
  load_locked_tables()
  if proto == "http" then return LOCKED_HTTP[profile] end
  if proto == "udp" then return LOCKED_UDP[profile] end
  return LOCKED_TLS[profile]
end

function desync_profile_key(desync)
  if desync.profile then return tostring(desync.profile) end
  if desync.profile_id then return tostring(desync.profile_id) end
  if desync.profileid then return tostring(desync.profileid) end
  if desync.profile_num then return tostring(desync.profile_num) end
  if desync.profile_name then return tostring(desync.profile_name) end
  if desync.arg and desync.arg.profile then return tostring(desync.arg.profile) end
  if desync.arg and desync.arg.key then return tostring(desync.arg.key) end
  if desync.func_instance then return tostring(desync.func_instance) end
  return "default"
end

function circular_locked(ctx, desync)
  orchestrate(ctx, desync)
  if not desync.track then
    DLOG_ERR("circular_locked: conntrack is missing but required")
    return
  end

  local hrec = automate_host_record(desync)
  if not hrec then
    DLOG("circular_locked: passing with no tampering")
    return
  end

  if not hrec.ctstrategy then
    local uniq = {}
    local n = 0
    for i, instance in pairs(desync.plan) do
      if instance.arg.strategy then
        n = tonumber(instance.arg.strategy)
        if not n or n < 1 then
          error("circular_locked: strategy number '"..tostring(instance.arg.strategy).."' is invalid")
        end
        uniq[tonumber(instance.arg.strategy)] = true
        if instance.arg.final then
          hrec.final = n
        end
      end
    end
    n = 0
    for i, v in pairs(uniq) do
      n = n + 1
    end
    if n ~= #uniq then
      error("circular_locked: strategies numbers must start from 1 and increment. gaps are not allowed.")
    end
    hrec.ctstrategy = n
  end

  if hrec.ctstrategy == 0 then
    error("circular_locked: add strategy=N tag argument to each following instance ! N must start from 1 and increment")
  end

  local proto = "tls"
  if desync.dis and desync.dis.udp then
    proto = "udp"
  elseif desync.l7payload == "http_req" or desync.l7payload == "http_reply" then
    proto = "http"
  end

  local profile = desync_profile_key(desync)
  local locked = locked_strategy_for_profile(profile, proto)
  if locked and locked >= 1 and locked <= hrec.ctstrategy then
    hrec.nstrategy = locked
    DLOG("circular_locked: locked strategy "..hrec.nstrategy.." profile="..profile)
  else
    hrec.nstrategy = 1
    DLOG("circular_locked: start from strategy 1 profile="..profile)
  end

  local verdict = VERDICT_PASS
  DLOG("circular_locked: current strategy "..hrec.nstrategy.." profile="..profile)
  while true do
    local instance = plan_instance_pop(desync)
    if not instance then break end
    if instance.arg.strategy and tonumber(instance.arg.strategy) == hrec.nstrategy then
      verdict = plan_instance_execute(desync, verdict, instance)
    end
  end

  return verdict
end
