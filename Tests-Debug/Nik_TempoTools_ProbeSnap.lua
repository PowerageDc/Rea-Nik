local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local cfg = dofile(script_dir .. "../TempoTools/TempoTools_config.lua")
local Read = dofile(script_dir .. "../TempoTools/TempoTapRead_common_logic.lua")
local Items = dofile(script_dir .. "../TempoTools/TempoTapItems_common_logic.lua")
local Snap = dofile(script_dir .. "../TempoTools/TempoTapSnap_common_logic.lua")

local function log(s)
  reaper.ShowConsoleMsg(s .. "\n")
end

reaper.ClearConsole()

local measures = Read.group(Read.read_taps())
if #measures == 0 then
  log("no hay compases: hacen falta al menos dos downbeats")
  return
end

local coll = Items.collect(cfg)
local cache = {}
local t0 = os.clock()
local res = Snap.run(measures, coll, cfg, { cache = cache })
local t1 = os.clock()
Snap.run(measures, coll, cfg, { cache = cache })
local t2 = os.clock()

local counts = {
  down = { snapped = 0, interpolated = 0, kept = 0 },
  beat = { snapped = 0, interpolated = 0, kept = 0 },
}

for i, p in ipairs(res.points) do
  counts[p.kind][p.status] = counts[p.kind][p.status] + 1
  local flags = ""
  if p.status == "snapped" and p.ratio < cfg.snap_high_ratio then flags = flags .. " [baja confianza]" end
  if p.outlier then flags = flags .. " [dudoso]" end
  if p.rejected then flags = flags .. " [rechazado]" end
  log(string.format("%3d  %-5s %9.3f -> %9.3f  %+7.1f ms  %-12s %-14s %s%s",
    i, p.kind, p.raw, p.pos, p.shift * 1000, p.status, p.ref or "-",
    p.ratio and string.format("x%.1f", p.ratio) or "", flags))
end

log("")
for _, kind in ipairs({ "down", "beat" }) do
  local c = counts[kind]
  log(string.format("%-5s ajustados %d | interpolados %d | sin cambio %d",
    kind, c.snapped, c.interpolated, c.kept))
end
log(string.format("mediana del desplazamiento de los ajustados: %+.1f ms", res.median_shift * 1000))
log(string.format("irregularidad de intervalos: %.1f ms antes -> %.1f ms después",
  res.irregularity_raw * 1000, res.irregularity_new * 1000))

local to_beat = 0
for i, m in ipairs(res.measures) do
  if m.mode == "beat" and measures[i].mode == "bar" then to_beat = to_beat + 1 end
end
log(string.format("compases que pasan de un marker por compás a uno por beat: %d", to_beat))
log(string.format("tiempo: primera corrida %.2f s | con caché %.2f s", t1 - t0, t2 - t1))