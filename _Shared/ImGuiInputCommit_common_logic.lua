-- ImGuiInputCommit_common_logic.lua
-- Commit real de InputText (Enter, no deactivation por click afuera).
-- Los atajos globales los despacha MusicStateKeys_common_logic.lua.
-- Ver ARQ_captura_keys_reaimgui_ruteo_reaper.md (patron A).

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

return M