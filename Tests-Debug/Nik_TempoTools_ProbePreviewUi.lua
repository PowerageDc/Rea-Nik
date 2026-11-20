local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local cfg = dofile(script_dir .. "../TempoTools/TempoTools_config.lua")
local Read = dofile(script_dir .. "../TempoTools/TempoTapRead_common_logic.lua")
local Items = dofile(script_dir .. "../TempoTools/TempoTapItems_common_logic.lua")
local Preview = dofile(script_dir .. "../TempoTools/TempoTapPreview_common_logic.lua")
local Ui = dofile(script_dir .. "../TempoTools/TempoTapPreviewUi_common_logic.lua")

local function log(s)
  reaper.ShowConsoleMsg(s .. "\n")
end

reaper.ClearConsole()

local measures = Read.group(Read.read_taps())
if #measures == 0 then
  log("no hay compases: hacen falta al menos dos downbeats")
  return
end

local S = Preview.new(measures, Items.collect(cfg), cfg)

Ui.run(S, {
  on_apply = function(ms)
    log(string.format("aplicar: %d compases, %d puntos", #ms, #S.res.points))
  end,
  on_cancel = function()
    log("cancelar")
  end,
})