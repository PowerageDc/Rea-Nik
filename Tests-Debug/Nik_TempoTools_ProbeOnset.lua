local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local cfg = dofile(script_dir .. "../TempoTools/TempoTools_config.lua")
local Read = dofile(script_dir .. "../TempoTools/TempoTapRead_common_logic.lua")
local Items = dofile(script_dir .. "../TempoTools/TempoTapItems_common_logic.lua")
local Onset = dofile(script_dir .. "../TempoTools/TempoTapOnset_common_logic.lua")

local function log(s)
  reaper.ShowConsoleMsg(s .. "\n")
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function stats(list)
  local n = #list
  if n == 0 then return nil end
  local sum = 0
  for _, v in ipairs(list) do sum = sum + v end
  local mean = sum / n
  local sq = 0
  for _, v in ipairs(list) do sq = sq + (v - mean) ^ 2 end
  local sorted = {}
  for i, v in ipairs(list) do sorted[i] = v end
  table.sort(sorted)
  local median = n % 2 == 1 and sorted[(n + 1) // 2] or (sorted[n // 2] + sorted[n // 2 + 1]) / 2
  return { n = n, mean = mean, median = median, sd = math.sqrt(sq / n) }
end

local function show(label, list, total)
  local s = stats(list)
  if not s then
    log(string.format("%-10s sin ataques (0 de %d)", label, total))
    return
  end
  log(string.format("%-10s %d de %d | media %+.1f ms | mediana %+.1f ms | desvío %.1f ms",
    label, s.n, total, s.mean, s.median, s.sd))
end

reaper.ClearConsole()

local taps = Read.read_taps()
if #taps < 2 then
  log("hacen falta al menos dos taps")
  return
end

local coll = Items.collect(cfg)
for _, s in ipairs(coll.stems) do
  local take = reaper.GetActiveTake(s.item)
  if take and not reaper.TakeIsMIDI(take) then
    local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
    local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    if offs ~= 0 or rate ~= 1 then
      log(string.format("[warn] %s: offset de source %.3f s, rate %.3f", s.track, offs, rate))
    end
  end
end

local refs = {}
for _, token in ipairs(cfg.snap_references) do
  local items = Onset.resolve(coll, token)
  refs[#refs + 1] = { token = token, items = items }
  log(string.format("referencia %-14s %d items", token, #items))
end
log("")

local opts = { min_ratio = cfg.snap_min_ratio, abs_floor = cfg.snap_abs_floor }
local offsets = { down = {}, beat = {} }
local totals = { down = 0, beat = 0 }
local per_ref = {}

local function detail(tap, hw)
  for _, r in ipairs(refs) do
    if #r.items > 0 then
      local c = Onset.candidates(r.items, tap.pos, hw,
        { min_ratio = 0, abs_floor = cfg.snap_abs_floor })
      local parts = {}
      for k = 1, math.min(3, #c) do
        parts[#parts + 1] = string.format("%+.0f ms (x%.1f)", (c[k].t - tap.pos) * 1000, c[k].ratio)
      end
      log(string.format("       %-14s %s", r.token, #parts > 0 and table.concat(parts, "  ") or "sin picos"))
    end
  end
end

for i, tap in ipairs(taps) do
  local kind = tap.is_down and "down" or "beat"
  totals[kind] = totals[kind] + 1
  local spacing = taps[i + 1] and (taps[i + 1].pos - tap.pos) or (tap.pos - taps[i - 1].pos)
  local hw = clamp(cfg.snap_window_ratio * spacing, cfg.snap_window_min, cfg.snap_window_max)

  local found, used
  for _, r in ipairs(refs) do
    if #r.items > 0 then
      local c = Onset.candidates(r.items, tap.pos, hw, opts)
      if #c > 0 then
        found, used = c[1], r.token
        break
      end
    end
  end

  if found then
    local off = (found.t - tap.pos) * 1000
    offsets[kind][#offsets[kind] + 1] = off
    per_ref[used] = (per_ref[used] or 0) + 1
    log(string.format("%3d  %-5s tap %9.3f s  ataque %9.3f s  %+7.1f ms  ratio %5.1f  %s",
      i, tap.is_down and "down" or "beat", tap.pos, found.t, off, found.ratio, used))
    if math.abs(off) > 40 then detail(tap, hw) end
  else
    log(string.format("%3d  %-5s tap %9.3f s  sin ataque (ventana ±%.0f ms)",
      i, tap.is_down and "down" or "beat", tap.pos, hw * 1000))
    detail(tap, hw)
  end
end

log("")
show("downbeats", offsets.down, totals.down)
show("beats", offsets.beat, totals.beat)
for token, n in pairs(per_ref) do
  log(string.format("resueltos con %-14s %d", token, n))
end