-- MusicStateCues_common_logic.lua
-- Tab "Cues" de Nik_MusicState_Helper.lua -- ver 01_CONVENCIONES.md,
-- patron dofile + M={}. Consumido solo por el Helper, no vive en _Shared/.

local M = {}

function M.draw(ctx, H, helpers)
  reaper.ImGui_TextDisabled(ctx, '(roles separados por coma; "todos" es un valor valido, sin validar por ahora)')
  reaper.ImGui_Spacing(ctx)

  local remove_idx = nil

  if reaper.ImGui_BeginTable(ctx, 'cues_table', 8, reaper.ImGui_TableFlags_SizingFixedFit()) then
    reaper.ImGui_TableSetupColumn(ctx, 'Compas')
    reaper.ImGui_TableSetupColumn(ctx, 'Beat')
    reaper.ImGui_TableSetupColumn(ctx, 'Cent.')
    reaper.ImGui_TableSetupColumn(ctx, 'Roles')
    reaper.ImGui_TableSetupColumn(ctx, 'Texto')
    reaper.ImGui_TableSetupColumn(ctx, 'Dur.(QN)')
    reaper.ImGui_TableSetupColumn(ctx, '')
    reaper.ImGui_TableSetupColumn(ctx, '')
    reaper.ImGui_TableHeadersRow(ctx)

    for i, row in ipairs(H.cues) do
      reaper.ImGui_TableNextRow(ctx)
      reaper.ImGui_PushID(ctx, i)

      helpers.RowInputs.drawPositionInputs(ctx, row)

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, 120)
      local changed_r
      changed_r, row.roles_str = reaper.ImGui_InputText(ctx, '##roles', row.roles_str)

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, 140)
      local changed_t
      changed_t, row.text = reaper.ImGui_InputText(ctx, '##texto', row.text)

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, 70)
      local changed_d
      changed_d, row.duration_qn = reaper.ImGui_InputDouble(ctx, '##duracion', row.duration_qn)

      reaper.ImGui_TableNextColumn(ctx)
      if helpers.RowInputs.drawCursorButton(ctx) then
        helpers.RowInputs.applyCursorToRow(row, helpers.captureCursorPosition())
      end

      reaper.ImGui_TableNextColumn(ctx)
      if reaper.ImGui_Button(ctx, 'Borrar') then
        remove_idx = i
      end

      reaper.ImGui_PopID(ctx)
    end

    reaper.ImGui_EndTable(ctx)
  end

  if remove_idx then
    table.remove(H.cues, remove_idx)
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  if reaper.ImGui_Button(ctx, '+ Agregar fila (cursor actual)', 220, 0) then
    local pos = helpers.captureCursorPosition()
    table.insert(H.cues, {
      measure = pos.measure,
      beat = pos.beat,
      hundredths = pos.hundredths,
      roles_str = '',
      text = '',
      duration_qn = 1.0,
    })
  end
end

return M