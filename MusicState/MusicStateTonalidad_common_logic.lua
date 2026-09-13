-- MusicStateTonalidad_common_logic.lua
-- Tab "Tonalidad" de Nik_MusicState_Helper.lua -- extraido para modularizar
-- el contenedor (ver 01_CONVENCIONES.md, patron dofile + M={}). Consumido
-- solo por el Helper, no vive en _Shared/.

local M = {}

function M.draw(ctx, H, helpers)
  local changed
  changed, H.key.tonic_idx = reaper.ImGui_Combo(ctx, 'Tonica', H.key.tonic_idx, helpers.TONICS_STR)
  changed, H.key.mode_idx = reaper.ImGui_Combo(ctx, 'Modo', H.key.mode_idx, helpers.MODES_STR)
end

return M