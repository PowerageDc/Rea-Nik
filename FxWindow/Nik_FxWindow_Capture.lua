local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local FxWindow = dofile(script_dir .. "FxWindow_common_logic.lua")

if not FxWindow.has_js_api() then
  reaper.ShowMessageBox("Falta JS_ReaScriptAPI (instalar desde ReaPack).", "FxWindow", 0)
  return
end

local sel_count = reaper.CountSelectedTracks(0)
if sel_count == 0 then
  reaper.ShowMessageBox("Seleccioná al menos un track.", "FxWindow", 0)
  return
end

reaper.ClearConsole()
local lines = {}

for t = 0, sel_count - 1 do
  local track = reaper.GetSelectedTrack(0, t)
  for _, fx in ipairs(FxWindow.list_fx(track)) do
    local hwnd = reaper.TrackFX_GetFloatingWindow(track, fx.index)
    if hwnd then
      local measured = FxWindow.measure(hwnd)
      local match = fx.name:gsub("^%S+:%s*", ""):gsub("%s*%b()$", "")
      lines[#lines + 1] = FxWindow.format_entry(match, measured.cli, measured.view)
    end
  end
end

if #lines == 0 then
  reaper.ShowConsoleMsg("No hay ventanas de FX abiertas en los tracks seleccionados.\n")
else
  reaper.ShowConsoleMsg("Para pegar en FxWindow_config.lua:\n" .. table.concat(lines, "\n") .. "\n")
end