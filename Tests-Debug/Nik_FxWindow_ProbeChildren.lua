local FX_NAME_PATTERN = "MODO BASS"

if not reaper.JS_Window_ListAllChild then
  reaper.ShowMessageBox("Falta JS_ReaScriptAPI (instalar desde ReaPack).", "FxWindow Probe", 0)
  return
end

local track = reaper.GetSelectedTrack(0, 0)
if not track then
  reaper.ShowMessageBox("Seleccioná el track con el VSTi.", "FxWindow Probe", 0)
  return
end

local function text_of(fn, hwnd)
  local ok, a, b = pcall(fn, hwnd, "")
  if not ok then ok, a, b = pcall(fn, hwnd) end
  if not ok then return "?" end
  if type(b) == "string" then return b end
  return type(a) == "string" and a or "?"
end

local function rect_text(getter, hwnd)
  local _, l, t, r, b = getter(hwnd)
  return string.format("x=%d y=%d w=%d h=%d", l, t, r - l, b - t)
end

reaper.ClearConsole()
for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
  local _, name = reaper.TrackFX_GetFXName(track, fx, "")
  if name:upper():find(FX_NAME_PATTERN, 1, true) then
    reaper.TrackFX_Show(track, fx, 3)
    local hwnd = reaper.TrackFX_GetFloatingWindow(track, fx)
    if hwnd then
      reaper.ShowConsoleMsg(name .. "\n")
      reaper.ShowConsoleMsg("ventana: " .. rect_text(reaper.JS_Window_GetRect, hwnd) .. "\n")
      reaper.ShowConsoleMsg("cliente: " .. rect_text(reaper.JS_Window_GetClientRect, hwnd) .. "\n")
      local _, list = reaper.JS_Window_ListAllChild(hwnd)
      for addr in (list or ""):gmatch("[^,]+") do
        local child = reaper.JS_Window_HandleFromAddress(tonumber(addr))
        if child then
          reaper.ShowConsoleMsg(string.format(
            "  hija clase=%s titulo=%s visible=%s %s\n",
            text_of(reaper.JS_Window_GetClassName, child),
            text_of(reaper.JS_Window_GetTitle, child),
            tostring(reaper.JS_Window_IsVisible(child)),
            rect_text(reaper.JS_Window_GetRect, child)))
        end
      end
    end
  end
end