-- ImGuiHostFocus_common_logic.lua
-- Foco de teclado entre una ventana ReaImGui y la ventana principal de
-- REAPER. Generico: lo puede usar cualquier panel nativo, no solo el Helper.
-- SWS primero (dependencia declarada del proyecto), js_ReaScriptAPI de
-- respaldo. ImGui_SetNextWindowFocus NO sirve para esto: la ventana figura
-- como enfocada pero el teclado no le llega hasta hacer click (probe del
-- Paso 1). Ver 08_REAIMGUI_PATTERNS.md.

local M = {}

local warned = false
local function warnOnce(msg)
  if warned then return end
  warned = true
  reaper.ShowConsoleMsg('[ImGuiHostFocus] ' .. msg .. '\n')
end

-- ImGui -> REAPER: devuelve el foco del teclado a la ventana principal.
function M.toReaper()
  if reaper.BR_Win32_SetFocus and reaper.BR_Win32_GetMainHwnd then
    local ok = pcall(function() reaper.BR_Win32_SetFocus(reaper.BR_Win32_GetMainHwnd()) end)
    if ok then return true end
  end
  if reaper.JS_Window_SetFocus then
    local ok = pcall(function() reaper.JS_Window_SetFocus(reaper.GetMainHwnd()) end)
    if ok then return true end
  end
  warnOnce('Hace falta SWS (BR_Win32_SetFocus) o js_ReaScriptAPI para devolver el foco a REAPER.')
  return false
end

-- REAPER -> ImGui: enfoca la ventana flotante con ese titulo exacto (el
-- titulo que se le pasa a ImGui_Begin). false si no esta abierta.
function M.toWindow(title)
  if reaper.BR_Win32_FindWindowEx and reaper.BR_Win32_SetFocus then
    local ok, hwnd = pcall(reaper.BR_Win32_FindWindowEx, '0', '0', '', title, false, true)
    if ok and hwnd then
      local ok2 = pcall(reaper.BR_Win32_SetFocus, hwnd)
      if ok2 then return true end
    end
  end
  if reaper.JS_Window_Find and reaper.JS_Window_SetFocus then
    local ok, hwnd = pcall(reaper.JS_Window_Find, title, true)
    if ok and hwnd then
      local ok2 = pcall(reaper.JS_Window_SetFocus, hwnd)
      if ok2 then return true end
    end
  end
  if not (reaper.BR_Win32_FindWindowEx or reaper.JS_Window_Find) then
    warnOnce('Hace falta SWS (BR_Win32_FindWindowEx) o js_ReaScriptAPI para enfocar la ventana.')
  end
  return false
end

-- Anti-rebote por auto-repeat de la tecla. arm() abre una ventana de
-- window_s segundos (en ExtState no persistente, compartido entre scripts);
-- blocked() devuelve true si un press llega dentro de esa ventana y la
-- desliza slide_s mas, para que un hold largo no la atraviese.
function M.arm(sec, key, window_s)
  reaper.SetExtState(sec, key, tostring(reaper.time_precise() + window_s), false)
end

function M.blocked(sec, key, slide_s)
  local now = reaper.time_precise()
  local until_t = tonumber(reaper.GetExtState(sec, key))
  if not until_t or now >= until_t then return false end
  reaper.SetExtState(sec, key, tostring(math.max(until_t, now + slide_s)), false)
  return true
end

return M
