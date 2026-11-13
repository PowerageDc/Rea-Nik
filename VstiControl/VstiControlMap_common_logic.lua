local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Core = dofile(script_dir .. "VstiControl_common_logic.lua")

local M = {}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function M.scale_to_raw(ctrl, u)
  local sc = ctrl.scale
  local lo, hi = ctrl.min or 0, ctrl.max or 127
  local center = sc.center or 0
  local raw = center
  if u >= 0 and sc.pos and sc.pos > 0 then
    raw = center + (u / sc.pos) * (hi - center)
  elseif u < 0 and sc.neg and sc.neg > 0 then
    raw = center + (u / sc.neg) * (center - lo)
  end
  return clamp(math.floor(raw + 0.5), lo, hi)
end

function M.raw_to_scale(ctrl, raw)
  local sc = ctrl.scale
  local lo, hi = ctrl.min or 0, ctrl.max or 127
  local center = sc.center or 0
  if raw >= center then
    local span = hi - center
    if span == 0 or not sc.pos then return 0 end
    return (raw - center) / span * sc.pos
  end
  local span = center - lo
  if span == 0 or not sc.neg then return 0 end
  return (raw - center) / span * sc.neg
end

function M.position_value(ctrl, p)
  if ctrl.values then return ctrl.values[p] end
  local step = ctrl.step or (128 / ctrl.count)
  return clamp(math.floor((p - 0.5) * step + 0.5), 0, 127)
end

function M.position_spec(cfg, ctrl, n)
  local first = ctrl.first or 1
  local p = n - first + 1
  if p < 1 or p > ctrl.count then return nil, "Posicion fuera de rango" end
  local label = ctrl.label .. " " .. n

  if ctrl.via == "cc" then
    local raw = M.position_value(ctrl, p)
    if not raw then return nil, "Falta el valor de la posicion" end
    return { type = "cc_point", label = label, cc = ctrl.cc, value = raw }
  end

  if ctrl.via == "ks_pair" then
    local base = ctrl.base
    if type(base) == "string" then
      local err
      base, err = Core.note(base, cfg.middle_c)
      if not base then return nil, err end
    end
    local d = cfg.defaults or {}
    local at = (ctrl.offset or d.ks_offset or 0) - (ctrl.lead or 1)
    local spec = {
      type = "keyswitch",
      label = label,
      steps = {
        { pitch = ctrl.enable, offset = at - (ctrl.stagger or 1) },
        { pitch = base + p - 1, offset = at },
      },
    }
    for _, k in ipairs({ "length", "velocity", "channel" }) do
      spec[k] = ctrl[k]
    end
    return spec
  end

  return nil, "Tipo de posicion desconocido: " .. tostring(ctrl.via)
end

return M