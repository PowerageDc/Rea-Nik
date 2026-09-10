-- ImGuiInputCommit_common_logic.lua
-- Commit real de InputText (Enter, no deactivation por click afuera) +
-- guards de teclado global sin colision con widgets activos.
-- Ver ARQ_captura_keys_reaimgui_ruteo_reaper.md (patrones A y B).

local M = {}

-- Patron A. Llamar inmediatamente despues de dibujar un InputText.
-- commit: true solo si Enter causo la deactivation ese mismo frame.
-- enter_key: true si Enter se presiono ese frame (para marcar consumo).
function M.resolveEnterCommit(ctx)
  local deact_edit = reaper.ImGui_IsItemDeactivatedAfterEdit(ctx)
  local enter_key = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter(), false)
    or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter(), false)
  return deact_edit and enter_key, enter_key
end

-- Patron B.2 + B.3 + B.4 combinado, para atajos globales.
-- consumed: true si esta tecla ya fue usada por un commit puntual este
-- frame (pasar false para teclas sin colision posible, ej. flechas).
function M.globalKeyPressed(ctx, key, consumed)
  if consumed then return false end
  if reaper.ImGui_IsAnyItemActive(ctx) then return false end
  if not reaper.ImGui_IsWindowFocused(ctx) then return false end
  return reaper.ImGui_IsKeyPressed(ctx, key, false)
end

return M