-- MusicStateArmonia_common_logic.lua
-- Tab "Armonia" de Nik_MusicState_Helper.lua -- ver 01_CONVENCIONES.md,
-- patron dofile + M={}. Consumido solo por el Helper, no vive en _Shared/.

local M = {}

function M.draw(ctx, H, helpers)
  reaper.ImGui_TextDisabled(ctx, '(acorde vacio = silencio explicito / sentinel "null")')
  reaper.ImGui_Spacing(ctx)

  local remove_idx = nil
  local navigate_row = nil

  local _, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
  local own_footer_h = reaper.ImGui_GetFrameHeightWithSpacing(ctx) * 2
  local container_footer_h = helpers.getListFooterReserveH()
  local table_h = math.max(avail_h - own_footer_h - container_footer_h, 60)

  local table_flags = reaper.ImGui_TableFlags_SizingFixedFit() | reaper.ImGui_TableFlags_ScrollY()

  if reaper.ImGui_BeginTable(ctx, 'harmony_table', 7, table_flags, 0, table_h) then
    reaper.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
    reaper.ImGui_TableSetupColumn(ctx, 'Compas')
    reaper.ImGui_TableSetupColumn(ctx, 'Beat')
    reaper.ImGui_TableSetupColumn(ctx, 'Cent.')
    reaper.ImGui_TableSetupColumn(ctx, 'Acorde')
    reaper.ImGui_TableSetupColumn(ctx, '')
    reaper.ImGui_TableSetupColumn(ctx, '')
    reaper.ImGui_TableSetupColumn(ctx, '')
    reaper.ImGui_TableHeadersRow(ctx)

    for i, row in ipairs(H.harmony) do
      reaper.ImGui_TableNextRow(ctx)
      reaper.ImGui_PushID(ctx, i)

      helpers.RowInputs.drawPositionInputs(ctx, row)

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, 100)
      local changed_c
      changed_c, row.chord = reaper.ImGui_InputText(ctx, '##acorde', row.chord)

      reaper.ImGui_TableNextColumn(ctx)
      if helpers.RowInputs.drawCursorButton(ctx) then
        helpers.RowInputs.applyCursorToRow(row, helpers.captureCursorPosition())
      end

      reaper.ImGui_TableNextColumn(ctx)
      if reaper.ImGui_Button(ctx, 'Ir') then
        navigate_row = row
      end

      reaper.ImGui_TableNextColumn(ctx)
      if reaper.ImGui_Button(ctx, 'Borrar') then
        remove_idx = i
      end

      reaper.ImGui_PopID(ctx)
    end

    reaper.ImGui_EndTable(ctx)
  end

  if navigate_row then
    helpers.moveCursorToRow(navigate_row)
  end

  if remove_idx then
    table.remove(H.harmony, remove_idx)
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  if reaper.ImGui_Button(ctx, '+ Agregar fila (cursor actual)', 220, 0) then
    local pos = helpers.captureCursorPosition()
    table.insert(H.harmony, {
      measure = pos.measure,
      beat = pos.beat,
      hundredths = pos.hundredths,
      chord = '',
    })
  end
end

return M