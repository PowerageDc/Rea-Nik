local PREROLL = 2

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Read = dofile(script_dir .. "../TempoTools/TempoTapRead_common_logic.lua")
local Plan = dofile(script_dir .. "../TempoTools/TempoTapPlan_common_logic.lua")

local function log(s)
  reaper.ShowConsoleMsg(s .. "\n")
end

reaper.ClearConsole()

local proj_num, proj_den, proj_bpm = reaper.TimeMap_GetTimeSigAtTime(0, 0)
local measures = Read.group(Read.read_taps())
local plan, warnings = Plan.build(measures, {
  proj_num = proj_num,
  proj_den = proj_den,
  proj_bpm = proj_bpm,
  preroll_bars = PREROLL,
})

if not plan then
  for _, w in ipairs(warnings) do log("[plan] " .. w.text) end
  return
end

log("tempo markers: plan contra real")
log("idx   pos plan   pos real       dif    compás.beat real    bpm plan   bpm real   compás plan / real")

for i = 0, reaper.CountTempoTimeSigMarkers(0) - 1 do
  local _, pos, mpos, bpos, bpm, num, den = reaper.GetTempoTimeSigMarker(0, i)
  local planned = i > 0 and plan.markers[i] or nil
  local plan_sig = (planned and planned.num) and string.format("%d/%d", planned.num, planned.den) or "-"
  log(string.format("%3d  %9s  %9.3f  %8s    %5d.%-8.3f  %9s  %9.3f   %-5s / %d/%d",
    i,
    planned and string.format("%.3f", planned.pos) or "-",
    pos,
    planned and string.format("%+.4f", pos - planned.pos) or "-",
    mpos, bpos,
    planned and string.format("%.3f", planned.bpm) or "-",
    bpm, plan_sig, num, den))
end

log("")
log("downbeats del plan: compás y beat que les asigna REAPER")
for i, t in ipairs(plan.downbeats) do
  local beats, measure, cml = reaper.TimeMap2_timeToBeats(0, t)
  log(string.format("%2d  %9.3f s  compás %d  beat %.3f de %.0f", i, t, measure, beats, cml))
end