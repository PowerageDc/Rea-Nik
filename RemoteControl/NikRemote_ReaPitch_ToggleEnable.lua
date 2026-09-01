-- NikRemote_ReaPitch_ToggleEnable.lua
-- Toggle global: si no todas las instancias de ReaPitch (hijos del Stem Bus)
-- están encendidas, las enciende todas. Si ya están todas encendidas, las
-- apaga todas. Sin parámetros de entrada.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local ReaPitchBus = dofile(script_dir .. "../_Shared/ReaPitchBus_common_logic.lua")

local instances = ReaPitchBus.find_all_instances()
if #instances == 0 then return end

local all_on = true
for _, inst in ipairs(instances) do
  if not reaper.TrackFX_GetEnabled(inst.track, inst.fx) then
    all_on = false
    break
  end
end

local new_state = not all_on -- si ya estaban todas encendidas, apaga; si no, enciende

reaper.Undo_BeginBlock()

for _, inst in ipairs(instances) do
  reaper.TrackFX_SetEnabled(inst.track, inst.fx, new_state)
end

reaper.Undo_EndBlock("NikRemote: toggle ReaPitch " .. (new_state and "ON" or "OFF") .. " (Stem Bus)", -1)

reaper.SetExtState("NikRemote", "reapitch_enabled", new_state and "on" or "off", false)
