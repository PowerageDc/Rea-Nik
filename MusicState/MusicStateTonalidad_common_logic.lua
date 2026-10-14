-- MusicStateTonalidad_common_logic.lua
-- Tab "Tonalidad" de Nik_MusicState_Helper.lua -- extraido para modularizar
-- el contenedor (patron dofile + M={}). Consumido solo por el Helper, no vive en _Shared/.

local M = {}

function M.draw(ctx, H, helpers)
  local _
  _, H.key.tonic_idx = helpers.KeyCombo.combo(ctx, 'Tonica', H.key.tonic_idx,
    helpers.TONICS_STR_BY_MODE[H.key.mode_idx + 1])
  reaper.ImGui_Text(ctx, 'Modo')
  reaper.ImGui_SameLine(ctx)
  local mode = H.key.mode_idx
  _, mode = reaper.ImGui_RadioButtonEx(ctx, 'Mayor', mode, 0)
  reaper.ImGui_SameLine(ctx)
  _, mode = reaper.ImGui_RadioButtonEx(ctx, 'Menor', mode, 1)
  H.key.mode_idx = mode
  if not H.key_set then
    reaper.ImGui_TextDisabled(ctx, 'Sin tonalidad publicada en este proyecto. Guardar y Publicar publica la de arriba.')
  end
end

return M