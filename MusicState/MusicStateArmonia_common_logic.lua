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

-- Devuelve el indice (dentro de `sections`, orden cronologico) de la ULTIMA
-- seccion cuyo marker es anterior o igual a `time`, o nil si no hay ninguna
-- (el tiempo cae antes del primer marker -> "Sin seccion"). Compartido
-- entre el agrupado de filas existentes y "+ Agregar fila" (necesita saber
-- a que seccion va la fila nueva, para forzar su apertura si esta colapsada).
local function findSectionIdx(sections, time)
  for s_idx = #sections, 1, -1 do
    if sections[s_idx].time <= time then
      return s_idx
    end
  end
  return nil
end

-- Tiempo de una fila para AGRUPADO/highlight -- congelado mientras la fila
-- esta en edicion (H._armonia_active_row), en vez de leer el valor en vivo
-- de row.measure/beat/hundredths (que el InputInt muta tecla por tecla).
-- Sin esto, cada digito tipeado puede recolocar la fila en otro
-- CollapsingHeader a mitad de edicion -- le corre el PushID y pierde el
-- foco de inmediato (bug real, confirmado: fallaba salvo que la fila ya
-- fuera la primera del colapsable, caso en que un digito de mas no la
-- saca de grupo). El snapshot se toma al ENTRAR en edicion (ver bloque
-- post-EndChild) y se descarta al salir, momento en que resortAndFocusRow
-- ya usa el valor final real, no este congelado.
local function activeAwareRowTime(H, helpers, row)
  if row == H._armonia_active_row then
    return H._armonia_active_row_time
  end
  return helpers.rowToTime(row)
end

-- Reordena H.harmony cronologicamente y deja la fila dada enfocada: fuerza
-- apertura de la seccion que le corresponde AHORA (puede haber cambiado si
-- se edito el compas) y su scroll. Llamar SIEMPRE despues de EndChild, nunca
-- durante el loop de filas -- correr el indice de una fila con foco activo
-- a mitad de edicion le hace perder el foco (PushID(ctx, i) usa ese indice).
-- target_row se ubica por identidad de tabla, no por indice viejo -- el
-- indice es justo lo que el sort corre. Garantiza el orden cronologico que
-- asume el loop de "fila activa" mas abajo.
local function resortAndFocusRow(H, helpers, target_row)
  table.sort(H.harmony, function(a, b) return helpers.rowToTime(a) < helpers.rowToTime(b) end)

  local new_idx = nil
  for i, row in ipairs(H.harmony) do
    if row == target_row then
      new_idx = i
      break
    end
  end
  if not new_idx then return end

  local sections = helpers.getSections()
  H._armonia_force_open_id = findSectionIdx(sections, helpers.rowToTime(target_row)) or 0
  H._armonia_scroll_target_idx = new_idx
end

function M.draw(ctx, H, helpers)
  reaper.ImGui_TextDisabled(ctx, '(acorde vacio = silencio explicito / sentinel "null")')
  reaper.ImGui_Spacing(ctx)

  local remove_idx = nil
  local navigate_row = nil
  local active_row_this_frame = nil  -- fila (si alguna) con foco en algun campo de posicion, ESTE frame

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
    local sections = helpers.getSections()

    -- Etapa 2 (auto-scroll): si la seccion del cursor de REAPER cambio desde
    -- el frame anterior, se fuerza apertura + se guarda a que seccion hay
    -- que scrollear (la fila mas cercana se calcula mas abajo, una vez
    -- agrupadas las filas). Comparte H._armonia_force_open_id con
    -- "+ Agregar fila" -- ambos casos son "esta seccion se abre este frame
    -- si o si"; no colisionan porque Agregar corre al final de M.draw,
    -- despues de que esto ya se consumio este frame.
    local cursor_pos = helpers.captureCursorPosition()
    local cursor_time = helpers.rowToTime(cursor_pos)
    local cursor_section_idx = findSectionIdx(sections, cursor_time) or 0
    local section_changed = H._armonia_last_section_idx ~= cursor_section_idx
    if section_changed then
      H._armonia_force_open_id = cursor_section_idx
      H._armonia_last_section_idx = cursor_section_idx
    end

    -- Cada fila va a la ULTIMA seccion cuyo marker es anterior o igual a su
    -- tiempo. Sin marker anterior -> "unsectioned". Se agrupa por indice de
    -- seccion (no por nombre) porque la nomenclatura estandar repite
    -- nombres (INTRO, PRECORO aparecen 2 veces, ver 01_CONVENCIONES.md).
    local section_groups = {}
    for s_idx = 1, #sections do
      section_groups[s_idx] = { name = sections[s_idx].name, rows = {}, stable_id = s_idx }
    end
    local unsectioned = { name = 'Sin seccion', rows = {}, stable_id = 0 }

    H._armonia_seen_groups = H._armonia_seen_groups or {}

    for i, row in ipairs(H.harmony) do
      local assigned = findSectionIdx(sections, activeAwareRowTime(H, helpers, row))
      local target = assigned and section_groups[assigned] or unsectioned
      table.insert(target.rows, { idx = i, row = row })
    end

    if section_changed then
      local target_group = (cursor_section_idx == 0) and unsectioned or section_groups[cursor_section_idx]
      local nearest_idx, nearest_diff = nil, nil
      for _, entry in ipairs(target_group.rows) do
        local diff = math.abs(activeAwareRowTime(H, helpers, entry.row) - cursor_time)
        if not nearest_diff or diff < nearest_diff then
          nearest_idx, nearest_diff = entry.idx, diff
        end
      end
      H._armonia_scroll_target_idx = nearest_idx
    end

    -- Fila "activa" para highlight: la ULTIMA fila de TODO H.harmony (no
    -- solo la seccion actual -- cubre el caso de recien entrar a una
    -- seccion sin acorde propio todavia, sigue sonando el carry-over de la
    -- fila anterior) con tiempo <= tiempo del cursor. exact=true si el
    -- cursor cae justo sobre esa fila (igualdad estricta measure/beat/
    -- hundredths, son enteros -- no hace falta tolerancia).
    local active_idx, active_exact = nil, false
    for i, row in ipairs(H.harmony) do
      if activeAwareRowTime(H, helpers, row) <= cursor_time then
        active_idx = i
        active_exact = (row.measure == cursor_pos.measure and row.beat == cursor_pos.beat and row.hundredths == cursor_pos.hundredths)
      else
        break
      end
    end

    local ordered_groups = {}
    if #unsectioned.rows > 0 then table.insert(ordered_groups, unsectioned) end
    for _, g in ipairs(section_groups) do
      if #g.rows > 0 then table.insert(ordered_groups, g) end
    end

    for _, group in ipairs(ordered_groups) do
      reaper.ImGui_PushID(ctx, group.stable_id)

      local force_open = (not H._armonia_seen_groups[group.stable_id])
        or (H._armonia_force_open_id == group.stable_id)
      if force_open then
        reaper.ImGui_SetNextItemOpen(ctx, true)
      end
      H._armonia_seen_groups[group.stable_id] = true
      if H._armonia_force_open_id == group.stable_id then
        H._armonia_force_open_id = nil  -- consumido: no se repite en frames siguientes
      end

      -- "###header" fija el ID del CollapsingHeader a algo que no depende
      -- del texto visible -- el conteo "(%d)" puede cambiar (agregar/borrar
      -- fila) sin que ImGui lo trate como un widget nuevo y pierda el
      -- estado abierto/cerrado. El stable_id en el PushID de arriba ya
      -- garantiza que no colisiona entre grupos.
      local header_label = string.format('%s (%d)###header', group.name, #group.rows)
      if reaper.ImGui_CollapsingHeader(ctx, header_label) then
        if reaper.ImGui_BeginTable(ctx, 'harmony_group_table', 7, table_flags) then
          setupHarmonyColumns(ctx)

          for _, entry in ipairs(group.rows) do
            local i, row = entry.idx, entry.row
            reaper.ImGui_TableNextRow(ctx)
            reaper.ImGui_PushID(ctx, i)

            if i == active_idx then
              local color = active_exact and 0x3FBF3FA0 or 0x3FBF3F40  -- verde: solido en match exacto, tenue en carry-over
              reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_RowBg0(), color)
            end

            if helpers.RowInputs.drawPositionInputs(ctx, row, nil, helpers.getMaxBeats) then
              active_row_this_frame = row
            end

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

            if H._armonia_scroll_target_idx == i then
              reaper.ImGui_SetScrollHereY(ctx)
              H._armonia_scroll_target_idx = nil
            end

            reaper.ImGui_PopID(ctx)
          end

          reaper.ImGui_EndTable(ctx)
        end
      end
      reaper.ImGui_PopID(ctx)
    end
  end
  reaper.ImGui_EndChild(ctx)

  if navigate_row then
    helpers.moveCursorToRow(navigate_row)
  end

  if remove_idx then
    table.remove(H.harmony, remove_idx)
  end

  -- Transicion de foco entre frames (no evento puntual de "commit", ver
  -- nota en drawPositionInputs). Dos casos, no excluyentes si el foco
  -- salta de una fila a otra en el mismo frame:
  -- - SALE de edicion (habia activa, ya no es la misma): recalcula con el
  --   valor FINAL real (ya no el congelado) y recien ahi reordena. Si esa
  --   fila ya se borro este mismo frame (remove_idx), resortAndFocusRow no
  --   la encuentra por identidad en H.harmony y no hace nada.
  -- - ENTRA en edicion (fila nueva activa): congela su tiempo ANTES de que
  --   el proximo frame la empiece a mutar por tipeo -- esto es lo que
  --   evita el churn de grupo/PushID mientras el foco sigue activo.
  if active_row_this_frame ~= H._armonia_active_row then
    if H._armonia_active_row then
      resortAndFocusRow(H, helpers, H._armonia_active_row)
    end
    if active_row_this_frame then
      H._armonia_active_row_time = helpers.rowToTime(active_row_this_frame)
    end
    H._armonia_active_row = active_row_this_frame
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  if reaper.ImGui_Button(ctx, '+ Agregar fila (cursor actual)', 220, 0) then
    local pos = helpers.captureCursorPosition()
    local new_row = {
      measure = pos.measure,
      beat = pos.beat,
      hundredths = pos.hundredths,
      chord = '',
    }
    table.insert(H.harmony, new_row)
    resortAndFocusRow(H, helpers, new_row)
  end
end

return M