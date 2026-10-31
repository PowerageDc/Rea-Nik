local FX_NAME_PATTERN = "MODO BASS"

if not reaper.JS_Window_GetRect then
  reaper.ShowMessageBox("Falta JS_ReaScriptAPI (instalar desde ReaPack).", "FxWindow Probe", 0)
  return
end

local track = reaper.GetSelectedTrack(0, 0)
if not track then
  reaper.ShowMessageBox("Seleccioná el track con el VSTi.", "FxWindow Probe", 0)
  return
end

reaper.ClearConsole()
local found = false
for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
  local _, name = reaper.TrackFX_GetFXName(track, fx, "")
  if name:upper():find(FX_NAME_PATTERN, 1, true) then
    found = true
    reaper.TrackFX_Show(track, fx, 3)
    local hwnd = reaper.TrackFX_GetFloatingWindow(track, fx)
    if hwnd then
      local _, wl, wt, wr, wb = reaper.JS_Window_GetRect(hwnd)
      local _, cl, ct, cr, cb = reaper.JS_Window_GetClientRect(hwnd)
      reaper.ShowConsoleMsg(string.format(
        "%s\nventana: x=%d y=%d w=%d h=%d\ncliente: x=%d y=%d w=%d h=%d\n",
        name, wl, wt, wr - wl, wb - wt, cl, ct, cr - cl, cb - ct))
    else
      reaper.ShowConsoleMsg(name .. ": sin ventana flotante\n")
    end
  end
end

if not found then
  reaper.ShowConsoleMsg("No hay FX que coincida con " .. FX_NAME_PATTERN .. "\n")
end