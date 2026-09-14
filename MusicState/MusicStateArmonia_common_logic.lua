-- MusicStateArmonia_common_logic.lua
-- Tab "Armonia" de Nik_MusicState_Helper.lua -- ver 01_CONVENCIONES.md,
-- patron dofile + M={}. Consumido solo por el Helper, no vive en _Shared/.

local M = {}

local COLUMN_WIDTHS = { measure = 100, beat = 90, hundredths = 100, chord = 100, cursor_btn = 110, go_btn = 50, delete_btn = 70 }

local function setupHarmonyColumns(ctx)
  local fixed = reaper.ImGui_TableColumnFlags_WidthFixed()
  reaper.ImGui_TableSetupColumn(ctx, 'Compas', fixed, COLUMN_WIDTHS.measure)
  reaper.ImGui_TableSetupColumn(ctx, 'Beat', fixed, COLUMN_WIDTHS.beat)
  reaper.ImGui_TableSetupColumn(ctx, 'Cent.', fixed, COLUMN_WIDTHS.hundredths)
  reaper.ImGui_TableSetupColumn(ctx, 'Acorde', fixed, COLUMN_WIDTHS.chord)
  reaper.ImGui_TableSetupColumn(ctx, '', fixed, COLUMN_WIDTHS.cursor_btn)
  reaper.ImGui_TableSetupColumn(ctx, '', fixed, COLUMN_WIDTHS.go_btn)
  reaper.ImGui_TableSetupColumn(ctx, '', fixed, COLUMN_WIDTHS.delete_btn)
end

function M.draw(ctx, H, helpers)
  reaper.ImGui_TextDisabled(ctx, '(acorde vacio = silencio explicito / sentinel "null")')
  reaper.ImGui_Spacing(ctx)

  local remove_idx = nil
  local navigate_row = nil

  local _, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
  local header_h = reaper.ImGui_GetFrameHeightWithSpacing(ctx)
  local own_footer_h = reaper.ImGui_GetFrameHeightWithSpacing(ctx) * 2
  local container_footer_h = helpers.getListFooterReserveH()
  local body_h = math.max(avail_h - header_h - own_footer_h - container_footer_h, 60)

  local table_flags = reaper.ImGui_TableFlags_SizingFixedFit()

  if reaper.ImGui_BeginTable(ctx, 'harmony_header', 7, table_flags) then
    setupHarmonyColumns(ctx)
    reaper.ImGui_TableHeadersRow(ctx)
    reaper.ImGui_EndTable(ctx)
  end

  local body_visible = reaper.ImGui_BeginChild(ctx, 'harmony_body', 0, body_h, 0, reaper.ImGui_WindowFlags_NoNav())
  if body_visible then
    if reaper.ImGui_BeginTable(ctx, 'harmony_table', 7, table_flags) then
      setupHarmonyColumns(ctx)

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
        if reaper.ImGui_Button(ctx, 'Ir', COLUMN_WIDTHS.go_btn - 8, 0) then
          navigate_row = row
        end

        reaper.ImGui_TableNextColumn(ctx)
        if reaper.ImGui_Button(ctx, 'Borrar', COLUMN_WIDTHS.delete_btn - 8, 0) then
          remove_idx = i
        end

        reaper.ImGui_PopID(ctx)
      end

      reaper.ImGui_EndTable(ctx)
    end
  end
  reaper.ImGui_EndChild(ctx)

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