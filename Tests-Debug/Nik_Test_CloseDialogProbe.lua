-- Nik_Test_CloseDialogProbe.lua
-- Sonda para confirmar/cerrar un diálogo de REAPER desde ReaScript con
-- JS_ReaScriptAPI. Referencia de uso real: autoConfirmScreensetDialog en
-- MvsepImporter/mvsep_stem_importer.lua.
--
-- USO: ajustar las constantes de abajo y ejecutar. Con LAUNCH_ACTION = false,
-- abrir el diálogo a mano antes de 30 s. El resultado se imprime en la
-- consola de REAPER (View > Show console output).
--
-- LO QUE FUNCIONA (validado con "Save Track View Screenset #1", botón Save):
--  * Encontrar el diálogo: JS_Window_Find(título, true).
--  * Confirmar: JS_Window_OnCommand(hwnd, ID_DEL_BOTON). Para descubrir los
--    IDs: JS_Window_ArrayAllChild + JS_Window_GetLong(hijo, "ID")
--    (el botón Save de ese diálogo tiene ID 1 = IDOK).
--  * Lanzar la acción SIN bloquear el script:
--    JS_WindowMessage_Post(GetMainHwnd(), "WM_COMMAND", ID_ACCION, 0, 0, 0),
--    y confirmar desde un reaper.defer.
--
-- LO QUE NO FUNCIONA:
--  * Main_OnCommand(ID) desde el mismo script que vigila: el diálogo bloquea
--    el script hasta que se cierra, y su defer no corre mientras tanto.
--  * BM_CLICK posteado al botón: devuelve true pero el diálogo lo ignora.
--
-- SIN PROBAR: método "mouse" (WM_LBUTTONDOWN / WM_LBUTTONUP sobre el botón).
--
-- NOTAS: el hwnd cambia en cada apertura (es normal). El defer debe
-- terminarse solo (return sin reprogramar) apenas la ventana se cierra.

local TITLE = "Save Track View Screenset #1"
local BUTTON_ID = 1                -- 1 = IDOK
local METHOD = "oncommand"         -- "oncommand" | "mouse" | "bm_click"
local ACTION_ID = 40464            -- Screenset: Save track view #01
local LAUNCH_ACTION = false        -- false: abrir el diálogo a mano

local t0 = reaper.time_precise()
local sentAt = nil

local function try(hwnd)
  local btn = reaper.JS_Window_FindChildByID(hwnd, BUTTON_ID)
  if METHOD == "oncommand" then
    reaper.JS_Window_OnCommand(hwnd, BUTTON_ID)
  elseif METHOD == "mouse" and btn then
    reaper.JS_WindowMessage_Send(btn, "WM_LBUTTONDOWN", 1, 0, 5, 5)
    reaper.JS_WindowMessage_Send(btn, "WM_LBUTTONUP", 0, 0, 5, 5)
  elseif METHOD == "bm_click" and btn then
    reaper.JS_WindowMessage_Post(btn, "BM_CLICK", 0, 0, 0, 0)
  else
    return false
  end
  return true
end

local function poll()
  local now = reaper.time_precise()
  local hwnd = reaper.JS_Window_Find(TITLE, true)
  if not sentAt then
    if hwnd and try(hwnd) then
      sentAt = now
      reaper.ShowConsoleMsg("enviado (" .. METHOD .. ")\n")
    end
  elseif now - sentAt > 1 then
    reaper.ShowConsoleMsg(hwnd and "RESULTADO: la ventana sigue abierta\n" or "RESULTADO: la ventana se cerró\n")
    return
  end
  if now - t0 < 30 then reaper.defer(poll) end
end

reaper.defer(poll)

if LAUNCH_ACTION then
  reaper.JS_WindowMessage_Post(reaper.GetMainHwnd(), "WM_COMMAND", ACTION_ID, 0, 0, 0)
end