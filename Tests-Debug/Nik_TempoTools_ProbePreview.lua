local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local cfg = dofile(script_dir .. "../TempoTools/TempoTools_config.lua")
local Read = dofile(script_dir .. "../TempoTools/TempoTapRead_common_logic.lua")
local Items = dofile(script_dir .. "../TempoTools/TempoTapItems_common_logic.lua")
local Preview = dofile(script_dir .. "../TempoTools/TempoTapPreview_common_logic.lua")

local function log(s)
  reaper.ShowConsoleMsg(s .. "\n")
end

local function timed(label, fn)
  local t = os.clock()
  fn()
  log(string.format("%-30s %.2f s", label, os.clock() - t))
end

local function show(S)
  local s = S.summary
  local function sum(k)
    return s.down[k] + s.beat[k]
  end
  log(string.format(
    "  ajustados %d | interpolados %d | sin cambio %d | sin marker %d | baja conf. %d | dudosos %d | rechazados %d | bloqueados %d | a beat %d | mediana %+.1f ms",
    sum("snapped"), sum("interpolated"), sum("kept"), s.inert, s.low, s.outlier,
    s.rejected, s.locked, s.to_beat, s.median_shift * 1000))
end

reaper.ClearConsole()

local measures = Read.group(Read.read_taps())
if #measures == 0 then
  log("no hay compases: hacen falta al menos dos downbeats")
  return
end

local S
timed("modelo nuevo", function() S = Preview.new(measures, Items.collect(cfg), cfg) end)
show(S)

local target
for k, p in ipairs(S.res.points) do
  if p.status == "snapped" then target = k break end
end
timed(string.format("bloquear punto %d", target), function() Preview.toggle_lock(S, target) end)
show(S)
local p = S.res.points[target]
log(string.format("  punto %d: compas %d beat %d | raw %.3f pos %.3f | %s | bloqueado %s",
  target, p.bar, p.beat, p.raw, p.pos, p.status, tostring(p.locked)))

timed("desbloquear", function() Preview.toggle_lock(S, target) end)
show(S)

timed("politica keep", function() Preview.set_policy(S, "keep") end)
show(S)

timed("interpolate, largo max 5", function()
  Preview.set_policy(S, "interpolate")
  Preview.set_interp_max(S, 5)
end)
show(S)

timed("un tempo por compas", function() Preview.set_inner_beats(S, false) end)
show(S)

timed("seguir los ataques", function() Preview.set_inner_beats(S, true) end)
show(S)

local pts = S.res.points
local n = #pts

local monotonic = true
for k = 2, n do
  if pts[k].pos < pts[k - 1].pos then monotonic = false end
end
log("  posiciones no decrecientes: " .. tostring(monotonic))

local function check(label, t, expected)
  local got = Preview.index_at(S, t)
  log(string.format("  %-26s t=%.4f -> %s (esperado %s) %s",
    label, t, tostring(got), tostring(expected), got == expected and "ok" or "FALLA"))
end

local mid = math.max(1, n // 2)
check("antes del primero", pts[1].pos - 1, nil)
check("en el primero", pts[1].pos, 1)
check("dentro del epsilon", pts[1].pos - 0.0005, 1)
check("en un punto intermedio", pts[mid].pos, mid)
if mid < n then
  check("justo antes del siguiente", pts[mid + 1].pos - 0.01, mid)
end
check("en el ultimo", pts[n].pos, n)
check("despues del ultimo", pts[n].pos + 10, n)

local mismatches = 0
for k, p in ipairs(pts) do
  if Preview.index_at(S, p.pos) ~= k then mismatches = mismatches + 1 end
end
log(string.format("  puntos cuyo index_at(pos) no es su indice: %d de %d", mismatches, n))