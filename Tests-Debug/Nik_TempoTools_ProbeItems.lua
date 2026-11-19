local PREROLL_OVERRIDE = nil

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local cfg = dofile(script_dir .. "../TempoTools/TempoTools_config.lua")
local Read = dofile(script_dir .. "../TempoTools/TempoTapRead_common_logic.lua")
local Plan = dofile(script_dir .. "../TempoTools/TempoTapPlan_common_logic.lua")
local Items = dofile(script_dir .. "../TempoTools/TempoTapItems_common_logic.lua")

local function log(s)
  reaper.ShowConsoleMsg(s .. "\n")
end

reaper.ClearConsole()

local coll = Items.collect(cfg)
log(string.format("stems: %d items | click: %d | count-in: %d | otros: %d | %s",
  #coll.stems, #coll.click_items, #coll.count_in, coll.others,
  coll.fresh and "recién importados (en 0)" or "ya alineados"))

local proj_num, proj_den, proj_bpm = reaper.TimeMap_GetTimeSigAtTime(0, 0)
local measures = Read.group(Read.read_taps())
local preroll = PREROLL_OVERRIDE or (coll.fresh and cfg.preroll_bars_default or nil)
local plan, plan_warnings = Plan.build(measures, {
  proj_num = proj_num,
  proj_den = proj_den,
  proj_bpm = proj_bpm,
  preroll_bars = preroll,
})

if not plan then
  log("")
  for _, w in ipairs(plan_warnings) do log("[plan] " .. w.text) end
  return
end

log(string.format("pre-roll: %d compases | desplazamiento %+.3f s", plan.preroll_bars, plan.delta))

local ev = Items.evaluate(coll, plan)

log("")
for _, s in ipairs(ev.stems) do
  log(string.format("stem   %-14s %-24s %9.3f -> %9.3f s", s.track, s.take, s.pos, s.new_pos))
end
if ev.click then
  log(string.format("click  %-14s %-24s tipo %s | largo %.3f -> %.3f s",
    ev.click.track, ev.click.take, ev.click.source, ev.click.len, ev.click.new_len))
end
for _, ci in ipairs(ev.count_in) do
  log(string.format("count  %-24s pos %.3f | largo %.3f s | timebase %d", ci.take, ci.pos, ci.len, ci.mode))
end
if ev.count_in.qn then
  log(string.format("count-in total: %.2f negras (necesarias: %.2f)", ev.count_in.qn, ev.count_in.expected_qn))
end

if #ev.warnings > 0 then
  log("")
  for _, w in ipairs(ev.warnings) do log("[warn] " .. w) end
end