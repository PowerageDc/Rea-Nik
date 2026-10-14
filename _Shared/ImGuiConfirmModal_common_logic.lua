-- ImGuiConfirmModal_common_logic.lua
-- Ciclo de vida comun de un modal de confirmacion en ReaImGui (NoNav: Esc no
-- cierra un popup por si solo). Generico: el cuerpo, los botones y lo que
-- hace cada uno quedan en quien lo usa.
--
-- El modal se describe con una tabla "pendiente" (p) que el llamador crea al
-- pedir la confirmacion, con p.open = true. Es la fuente congelada de lo que
-- el modal muestra (patron del modal de pegado de Armonia: nunca el estado
-- vivo). El helper maneja solo dos campos de p:
--   p.open   true = abrir el popup (se apaga solo, abre una unica vez)
--   p.armed  false en el primer frame visible: ahi Esc/Enter se ignoran, para
--            que la misma tecla que abrio el modal no lo cierre de inmediato
--
-- Uso:
--   local visible, cancel, confirm, stale = Modal.begin(ctx, 'Titulo###id', p, keys)
--   if visible then
--     if not p then reaper.ImGui_CloseCurrentPopup(ctx)  -- pendiente descartado
--     else
--       ... cuerpo y botones; si cancel/confirm o un boton: resolver y
--       reaper.ImGui_CloseCurrentPopup(ctx)
--     end
--     reaper.ImGui_EndPopup(ctx)  -- solo si visible
--   elseif stale then p_owner.pending = nil end
-- stale: el popup ya no esta abierto (se cerro por otra via) pero el
-- pendiente sigue: el llamador lo descarta.

local M = {}

-- Lectura de teclas por defecto: Esc cancela, Enter/KeypadEnter confirma,
-- una sola vez por press (sin repeticion). Un panel con su propia config de
-- teclas pasa su lector como 4to parametro (ctx -> cancel, confirm).
function M.default_keys(ctx)
  local cancel = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape(), false)
  local confirm = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter(), false)
    or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter(), false)
  return cancel, confirm
end

-- Devuelve visible, cancel, confirm, stale. cancel y confirm son siempre
-- false mientras el modal no este visible, p sea nil o sea su primer frame.
function M.begin(ctx, id, p, keys)
  if p and p.open then
    reaper.ImGui_OpenPopup(ctx, id)
    p.open = false
  end
  local visible = reaper.ImGui_BeginPopupModal(ctx, id, nil,
    reaper.ImGui_WindowFlags_AlwaysAutoResize())
  if not visible then
    return false, false, false, p ~= nil
  end
  local cancel, confirm = false, false
  if p then
    if p.armed then
      cancel, confirm = (keys or M.default_keys)(ctx)
    end
    p.armed = true
  end
  return true, cancel and true or false, confirm and true or false, false
end

return M