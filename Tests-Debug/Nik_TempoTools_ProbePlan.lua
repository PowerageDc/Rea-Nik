local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Read = dofile(script_dir .. "../TempoTools/TempoTapRead_common_logic.lua")
local Plan = dofile(script_dir .. "../TempoTools/TempoTapPlan_common_logic.lua")

local function log(s)
  reaper.ShowConsoleMsg(s .. "\n")
end

reaper.ClearConsole()

local proj_num, proj_den, proj_bpm = reaper.TimeMap_GetTimeSigAtTime(0, 0)
log(string.format("proyecto: %d/%d a %.3f bpm", proj_num, proj_den, proj_bpm))

local measures, read_warnings = Read.group(Read.read_taps())
local plan, plan_warnings = Plan.build(measures, {
  proj_num = proj_num,
  proj_den = proj_den,
  proj_bpm = proj_bpm,
})

if plan then
  log(string.format("pre-roll: %d compases | compás %.3f s | inicial %d/%d a %.3f bpm",
    plan.preroll_bars, plan.bar, plan.init.num, plan.init.den, plan.init.bpm))
  log(string.format("desplazamiento del contenido: %+.3f s", plan.delta))
  log(string.format("rango: %.3f s a %.3f s | markers: %d", plan.first_pos, plan.last_pos, #plan.markers))
  log("")
  for i, mk in ipairs(plan.markers) do
    local sig = mk.num and string.format("%d/%d", mk.num, mk.den) or ""
    log(string.format("%3d  %9.3f s  %8.3f bpm  %-5s %s",
      i, mk.pos, mk.bpm, sig, mk.closing and "cierre" or ""))
  end
end

local all = {}
for _, w in ipairs(read_warnings) do all[#all + 1] = w end
for _, w in ipairs(plan_warnings) do all[#all + 1] = w end
if #all > 0 then
  log("")
  for _, w in ipairs(all) do
    log(string.format("[%s] %.3f s  %s", w.level, w.pos, w.text))
  end
end