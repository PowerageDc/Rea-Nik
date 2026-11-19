local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Read = dofile(script_dir .. "../TempoTools/TempoTapRead_common_logic.lua")

local function log(s)
  reaper.ShowConsoleMsg(s .. "\n")
end

reaper.ClearConsole()
local taps = Read.read_taps()
local measures, warnings = Read.group(taps)

log(string.format("taps: %d | compases: %d | avisos: %d", #taps, #measures, #warnings))
log("")

for i, m in ipairs(measures) do
  local tapped = 0
  for _, b in ipairs(m.beats) do
    if b.origin == "tapped" then tapped = tapped + 1 end
  end
  local dur = m.finish - m.start
  log(string.format(
    "%3d  %9.3f s  %2d/%-2d%s  %-4s  beats %2d (tapeados %2d)  dur %.3f s  %.1f pulsos/min",
    i, m.start, m.num, m.den, m.declared and "*" or " ", m.mode,
    #m.beats, tapped, dur, #m.beats / dur * 60))
end

if #warnings > 0 then
  log("")
  for _, w in ipairs(warnings) do
    log(string.format("[%s] %.3f s  %s", w.level, w.pos, w.text))
  end
end