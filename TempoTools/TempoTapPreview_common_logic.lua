-- TempoTapPreview_common_logic.lua
-- Modelo de la vista previa del snap: corre Snap.run con los bloqueos del
-- usuario y la politica de puntos sin ataque, y deja los puntos anotados y
-- resumidos para que una UI los dibuje. No usa ImGui ni modifica el proyecto,
-- salvo el cursor de edicion en goto.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Snap = dofile(script_dir .. "TempoTapSnap_common_logic.lua")

local M = {}

local INTERP_MAX_LIMIT = 16
M.INTERP_MAX_LIMIT = INTERP_MAX_LIMIT

local function view_cfg(S)
  return setmetatable({
    snap_unanchored = S.policy,
    snap_interp_max = S.interp_max,
    snap_inner_beats = S.inner_beats,
  }, { __index = S.cfg })
end

-- Agrega a cada punto el compas, el beat, el origen y las marcas de lectura.
local function annotate(S, res)
  local labels = {}
  for i, m in ipairs(S.measures) do
    for j, b in ipairs(m.beats) do
      labels[#labels + 1] = { bar = i, beat = j, origin = b.origin }
    end
  end
  labels[#labels + 1] = { bar = #S.measures + 1, beat = 1, origin = "tapped" }

  for k, p in ipairs(res.points) do
    local l = labels[k]
    p.bar, p.beat, p.origin = l.bar, l.beat, l.origin
    p.low = p.status == "snapped" and p.ratio < S.cfg.snap_high_ratio
  end
end

local function summarize(S, res)
  local s = {
    total = #res.points,
    down = { snapped = 0, interpolated = 0, kept = 0 },
    beat = { snapped = 0, interpolated = 0, kept = 0 },
    low = 0, outlier = 0, rejected = 0, locked = 0, to_beat = 0, inert = 0,
    median_shift = res.median_shift,
    irregularity_raw = res.irregularity_raw,
    irregularity_new = res.irregularity_new,
  }
  for _, p in ipairs(res.points) do
    if p.inert then
      s.inert = s.inert + 1
    else
      s[p.kind][p.status] = s[p.kind][p.status] + 1
    end
    if p.low then s.low = s.low + 1 end
    if p.outlier then s.outlier = s.outlier + 1 end
    if p.rejected then s.rejected = s.rejected + 1 end
    if p.locked and not p.inert then s.locked = s.locked + 1 end
  end
  for i, m in ipairs(res.measures) do
    if m.mode == "beat" and S.measures[i].mode == "bar" then
      s.to_beat = s.to_beat + 1
    end
  end
  return s
end

function M.recompute(S)
  local res = Snap.run(S.measures, S.coll, view_cfg(S), { locked = S.locked, cache = S.cache })
  annotate(S, res)
  S.res = res
  S.summary = summarize(S, res)
end

-- measures: salida de Read.group. coll: salida de Items.collect.
-- Estado: { res, summary, policy, interp_max, inner_beats, clear_taps, locked, ... }
--   S.res      resultado de Snap.run con puntos anotados (bar, beat, origin, low)
--   S.summary  conteos por tipo y estado, marcas, desplazamiento y irregularidad
function M.new(measures, coll, cfg)
  local S = {
    measures = measures,
    coll = coll,
    cfg = cfg,
    locked = {},
    cache = {},
    policy = cfg.snap_unanchored,
    interp_max = cfg.snap_interp_max,
    inner_beats = cfg.snap_inner_beats and true or false,
    clear_taps = cfg.clear_taps_after and true or false,
  }
  M.recompute(S)
  return S
end

-- Deja el punto k como se toco (o lo vuelve a anclar).
function M.toggle_lock(S, k)
  local p = S.res.points[k]
  if not p or p.inert then return end
  S.locked[k] = (not S.locked[k]) or nil
  M.recompute(S)
end

-- policy: "interpolate" o "keep".
function M.set_policy(S, policy)
  if policy ~= "interpolate" and policy ~= "keep" then return end
  if S.policy == policy then return end
  S.policy = policy
  M.recompute(S)
end

-- on = true: los beats interiores, tocados o segun los ataques, dan un marker por
-- beat. false: se ignoran y cada compas queda con un tempo.
function M.set_inner_beats(S, on)
  on = on and true or false
  if S.inner_beats == on then return end
  S.inner_beats = on
  M.recompute(S)
end

function M.set_interp_max(S, n)
  n = math.max(1, math.min(INTERP_MAX_LIMIT, math.floor(n)))
  if S.interp_max == n then return end
  S.interp_max = n
  M.recompute(S)
end

-- Mueve el cursor de edicion al punto k, en su posicion resultante.
function M.go_to(S, k)
  local p = S.res.points[k]
  if p then reaper.SetEditCurPos(p.pos, true, false) end
end

-- Compases resultantes, para Plan.build.
function M.measures(S)
  return S.res.measures
end

return M