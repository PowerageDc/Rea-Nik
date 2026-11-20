local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Onset = dofile(script_dir .. "TempoTapOnset_common_logic.lua")

local M = {}

local OUTLIER_FLOOR = 0.005

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function median_of(list)
  local n = #list
  if n == 0 then return 0 end
  local s = {}
  for i, v in ipairs(list) do s[i] = v end
  table.sort(s)
  if n % 2 == 1 then return s[(n + 1) // 2] end
  return (s[n // 2] + s[n // 2 + 1]) / 2
end

-- Desvío de las diferencias entre intervalos consecutivos: mide el jitter
-- sin que lo afecte un cambio lento de tempo.
local function irregularity(positions)
  local d = {}
  for i = 2, #positions do d[#d + 1] = positions[i] - positions[i - 1] end
  local diffs = {}
  for i = 2, #d do diffs[#diffs + 1] = d[i] - d[i - 1] end
  if #diffs == 0 then return 0 end
  local sum = 0
  for _, v in ipairs(diffs) do sum = sum + v end
  local mean = sum / #diffs
  local sq = 0
  for _, v in ipairs(diffs) do sq = sq + (v - mean) ^ 2 end
  return math.sqrt(sq / #diffs)
end

local function copy_measures(measures)
  local out = {}
  for i, m in ipairs(measures) do
    local c = {}
    for k, v in pairs(m) do c[k] = v end
    c.beats = {}
    for j, b in ipairs(m.beats) do
      c.beats[j] = { pos = b.pos, raw = b.pos, origin = b.origin, status = "kept" }
    end
    out[i] = c
  end
  return out
end

-- Lista plana en orden: todos los beats de cada compás y el downbeat final
-- que cierra el último.
local function flatten(ms, closing)
  local pts = {}
  for i, m in ipairs(ms) do
    for j, b in ipairs(m.beats) do
      pts[#pts + 1] = { b = b, kind = j == 1 and "down" or "beat" }
    end
  end
  pts[#pts + 1] = { b = closing, kind = "down" }
  return pts
end

local function sync(ms, closing)
  for i, m in ipairs(ms) do
    m.start = m.beats[1].pos
    m.finish = ms[i + 1] and ms[i + 1].beats[1].pos or closing.pos
  end
end

-- Reparte en partes iguales los beats interiores de los compases con solo downbeats.
local function respread_bar_beats(ms)
  for _, m in ipairs(ms) do
    if m.mode == "bar" then
      local n = #m.beats
      for j = 2, n do
        m.beats[j].pos = m.start + (m.finish - m.start) * (j - 1) / n
      end
    end
  end
end

local function candidates(ctx, r, pos, hw)
  local key = string.format("%s|%.6f|%.6f", r.token, pos, hw)
  local c = ctx.cache[key]
  if not c then
    c = Onset.candidates(r.items, pos, hw, ctx.opts)
    ctx.cache[key] = c
  end
  return c
end

local function snap_points(pts, kind, ctx)
  local cfg = ctx.cfg
  for k, pt in ipairs(pts) do
    if pt.kind == kind then
      if ctx.locked[k] then pt.b.locked = true end
      if ctx.skip[k] then pt.b.skipped = true end
    end
    if pt.kind == kind and not pt.b.locked and not pt.b.skipped then
      local pos = pt.b.pos
      local prev = pts[k - 1] and pts[k - 1].b.pos
      local nxt = pts[k + 1] and pts[k + 1].b.pos
      local spacing = math.min(prev and pos - prev or math.huge, nxt and nxt - pos or math.huge)
      local hw = clamp(cfg.snap_window_ratio * spacing, cfg.snap_window_min, cfg.snap_window_max)
      for _, r in ipairs(ctx.refs) do
        if #r.items > 0 then
          local hit = candidates(ctx, r, pos, hw)[1]
          if hit
              and (not prev or hit.t > prev + cfg.snap_min_gap)
              and (not nxt or hit.t < nxt - cfg.snap_min_gap) then
            pt.b.pos = hit.t
            pt.b.status = "snapped"
            pt.b.ref = r.token
            pt.b.ratio = hit.ratio
            break
          end
        end
      end
    end
  end
end

-- Los tramos cortos de puntos sin ataque, entre dos anclas, se reparten en
-- partes iguales entre ellas.
local function anchored(b)
  return b.status == "snapped" or b.locked
end

local function interpolate_unanchored(pts, max_run)
  local k = 1
  while k <= #pts do
    if anchored(pts[k].b) then
      k = k + 1
    else
      local s = k
      while k <= #pts and not anchored(pts[k].b) do k = k + 1 end
      local e = k - 1
      local left, right = pts[s - 1], pts[e + 1]
      if left and right and (e - s + 1) <= max_run then
        local span = right.b.pos - left.b.pos
        local n = e - s + 2
        for q = s, e do
          pts[q].b.pos = left.b.pos + span * (q - s + 1) / n
          pts[q].b.status = "interpolated"
        end
      end
    end
  end
end

local function run_once(measures, coll, cfg, extra)
  local ms = copy_measures(measures)
  local last = ms[#ms]
  local closing = { pos = last.finish, raw = last.finish, origin = "tapped", status = "kept" }

  local refs = {}
  for _, token in ipairs(cfg.snap_references) do
    refs[#refs + 1] = { token = token, items = Onset.resolve(coll, token) }
  end
  local ctx = {
    cfg = cfg,
    refs = refs,
    locked = extra.locked,
    skip = extra.skip,
    cache = extra.cache,
    opts = { min_ratio = cfg.snap_min_ratio, abs_floor = cfg.snap_abs_floor },
  }

  snap_points(flatten(ms, closing), "down", ctx)
  sync(ms, closing)
  respread_bar_beats(ms)

  local pts = flatten(ms, closing)
  snap_points(pts, "beat", ctx)
  if cfg.snap_unanchored == "interpolate" then
    interpolate_unanchored(pts, cfg.snap_interp_max)
  end
  sync(ms, closing)

  if cfg.snap_bar_to_beat then
    for _, m in ipairs(ms) do
      if m.mode == "bar" then
        for j = 2, #m.beats do
          if m.beats[j].status ~= "kept" then
            m.mode = "beat"
            break
          end
        end
      end
    end
  end

  local points, shifts, raws, news = {}, {}, {}, {}
  for k, pt in ipairs(pts) do
    local b = pt.b
    local shift = b.pos - b.raw
    points[k] = {
      kind = pt.kind, raw = b.raw, pos = b.pos, shift = shift,
      status = b.status, ref = b.ref, ratio = b.ratio,
      locked = b.locked, rejected = b.skipped,
    }
    raws[k], news[k] = b.raw, b.pos
    if b.status == "snapped" then shifts[#shifts + 1] = shift end
  end

  local med = median_of(shifts)
  local devs = {}
  for i, s in ipairs(shifts) do devs[i] = math.abs(s - med) end
  local limit = cfg.snap_outlier_k * math.max(median_of(devs), OUTLIER_FLOOR)
  for _, p in ipairs(points) do
    if p.status == "snapped" and math.abs(p.shift - med) > limit then
      p.outlier = true
    end
  end

  return {
    measures = ms,
    points = points,
    median_shift = med,
    irregularity_raw = irregularity(raws),
    irregularity_new = irregularity(news),
  }
end

-- Ajusta los taps al audio. No modifica `measures` ni el proyecto.
-- opts.locked: set { [índice de punto] = true } de puntos que se dejan como se
-- tocaron. opts.cache: tabla que se conserva entre corridas para no repetir la
-- detección.
-- Un punto de baja confianza y dudoso a la vez no se ancla: se corre de nuevo
-- tratándolo como un punto sin ataque.
-- Devuelve { measures, points, median_shift, irregularity_raw, irregularity_new }.
-- Cada punto: { kind, raw, pos, shift, status, ref, ratio, outlier, locked, rejected,
-- rejected_pos, rejected_ratio } con status "snapped", "interpolated" o "kept".
-- Los rechazados conservan la posición y el ratio del ataque que se descartó.
-- El índice del punto en `points` es estable mientras `measures` no cambie.
function M.run(measures, coll, cfg, opts)
  opts = opts or {}
  local extra = {
    locked = opts.locked or {},
    skip = {},
    cache = opts.cache or {},
  }
  local res = run_once(measures, coll, cfg, extra)

  local rejected, any = {}, false
  for k, p in ipairs(res.points) do
    if p.outlier and p.ratio < cfg.snap_high_ratio then
      rejected[k] = true
      any = true
    end
  end
  if any then
    local first = res
    extra.skip = rejected
    res = run_once(measures, coll, cfg, extra)
    for k in pairs(rejected) do
      res.points[k].rejected_pos = first.points[k].pos
      res.points[k].rejected_ratio = first.points[k].ratio
    end
  end
  return res
end

return M