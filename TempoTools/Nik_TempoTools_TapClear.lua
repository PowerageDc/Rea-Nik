local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Tap = dofile(script_dir .. "TempoTools_common_logic.lua")

local answer = reaper.ShowMessageBox(
  "Se borrarán todos los markers TAP y TAP1 del proyecto. ¿Continuar?",
  "Tempo taps", 4)
if answer == 6 then
  Tap.clear_taps()
end