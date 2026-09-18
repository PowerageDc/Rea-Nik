-- MusicStateArmonia_common_logic.lua
-- Tab "Armonia" de Nik_MusicState_Helper.lua -- ver 01_CONVENCIONES.md,
-- patron dofile + M={}. Consumido solo por el Helper, no vive en _Shared/.

local M = {}

local COLUMN_WIDTHS = { select = 36, measure = 100, beat = 90, hundredths = 100, chord = 100, cursor_btn = 110, go_btn = 50, delete_btn = 70 }

local function setupHarmonyColumns(ctx)
  local fixed = reaper.ImGui_TableColumnFlags_WidthFixed()
  reaper.ImGui_TableSetupColumn(ctx, '', fixed, COLUMN_WIDTHS.select)
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

-- Maneja el click de un checkbox de seleccion (rango contiguo, 2 clicks).
-- No usa el valor que devuelve Checkbox como fuente de verdad -- el
-- checkbox es solo el gatillo de "hubo click en esta fila", el estado real
-- lo decide esta logica:
-- 1) sin ancla + click -> arranca ancla (unica fila seleccionada, en
--    espera de completar el rango).
-- 2) ancla activa + click en la MISMA fila -> cancela (fila queda sin
--    seleccionar, ancla se limpia).
-- 3) ancla activa + click en OTRA fila -> completa el rango [ancla..fila]
--    inclusive, por posicion en H.harmony (garantizado cronologico por
--    resortAndFocusRow) -- no importa cual de las dos es mas temprana.
-- 4) sin ancla pero YA hay un rango completo seleccionado + click en
--    cualquier fila -> descarta la seleccion anterior y arranca una ancla
--    nueva en la fila clickeada.
local function toggleSelection(H, row)
  if H._armonia_selection_anchor == row then
    row.selected = false
    H._armonia_selection_anchor = nil
    return
  end

  if H._armonia_selection_anchor then
    local anchor_idx, row_idx = nil, nil
    for i, r in ipairs(H.harmony) do
      if r == H._armonia_selection_anchor then anchor_idx = i end
      if r == row then row_idx = i end
    end
    if anchor_idx and row_idx then
      local lo, hi = math.min(anchor_idx, row_idx), math.max(anchor_idx, row_idx)
      for i = lo, hi do H.harmony[i].selected = true end
    end
    H._armonia_selection_anchor = nil
    return
  end

  for _, r in ipairs(H.harmony) do r.selected = false end
  row.selected = true
  H._armonia_selection_anchor = row
end

-- Filas EXISTENTES en H.harmony cuya posicion (measure/beat/hundredths,
-- igualdad exacta de enteros -- mismo criterio que el highlight de fila
-- activa) coincide con alguna fila candidata de un pegado. Devuelve
-- referencias de fila (identidad), no indices -- se usan para remover
-- puntualmente en applyPaste sin tocar el resto del rango. set 'seen'
-- evita duplicar si dos candidatos coinciden con la misma fila existente.
local function findPositionCollisions(H, candidates)
  local collisions = {}
  local seen = {}
  for _, cand in ipairs(candidates) do
    for _, row in ipairs(H.harmony) do
      if row.measure == cand.measure and row.beat == cand.beat and row.hundredths == cand.hundredths then
        if not seen[row] then
          seen[row] = true
          table.insert(collisions, row)
        end
      end
    end
  end
  return collisions
end

-- Aplica un pegado ya resuelto: remueve las filas colisionadas (si las
-- hay, por identidad -- ver findPositionCollisions), inserta las filas
-- candidatas, reordena y enfoca la primera (candidates[1] siempre tiene
-- delta_qn=0 por construccion del clipboard, ver boton "Copiar seleccion").
local function applyPaste(H, helpers, candidates, rows_to_remove)
  if rows_to_remove and #rows_to_remove > 0 then
    local remove_set = {}
    for _, r in ipairs(rows_to_remove) do remove_set[r] = true end
    for i = #H.harmony, 1, -1 do
      if remove_set[H.harmony[i]] then
        table.remove(H.harmony, i)
      end
    end
  end
  for _, cand in ipairs(candidates) do
    table.insert(H.harmony, cand)
  end
  resortAndFocusRow(H, helpers, candidates[1])
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

  if reaper.ImGui_BeginTable(ctx, 'harmony_header', 8, table_flags) then
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
        if reaper.ImGui_BeginTable(ctx, 'harmony_group_table', 8, table_flags) then
          setupHarmonyColumns(ctx)

          for _, entry in ipairs(group.rows) do
            local i, row = entry.idx, entry.row
            reaper.ImGui_TableNextRow(ctx)
            reaper.ImGui_PushID(ctx, i)

            if i == active_idx then
              local color = active_exact and 0x3FBF3FA0 or 0x3FBF3F40  -- verde: solido en match exacto, tenue en carry-over
              reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_RowBg0(), color)
            end

            -- Checkbox de seleccion: apagado (frame/borde con alfa bajo)
            -- cuando NO esta tildado, para que no compita visualmente con
            -- las filas si tildadas -- estilo nativo (PushStyleColor), no
            -- un disabled real, sigue siendo clickeable normal.
            reaper.ImGui_TableNextColumn(ctx)
            local dimmed = not row.selected
            if dimmed then
              reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x80808025)
              reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), 0x80808055)
              reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), 0x80808085)
              reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0x80808040)
            end
            local sel_clicked = reaper.ImGui_Checkbox(ctx, '##sel', row.selected)
            if dimmed then
              reaper.ImGui_PopStyleColor(ctx, 4)
            end
            if sel_clicked then
              toggleSelection(H, row)
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
    local removed_row = table.remove(H.harmony, remove_idx)
    if removed_row == H._armonia_selection_anchor then
      H._armonia_selection_anchor = nil
    end
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

  reaper.ImGui_SameLine(ctx)
  local selected_rows = {}
  for _, row in ipairs(H.harmony) do
    if row.selected then table.insert(selected_rows, row) end
  end
  local copy_clicked = reaper.ImGui_Button(ctx, string.format('Copiar seleccion (%d)', #selected_rows), 170, 0)
  if copy_clicked and #selected_rows > 0 then
    -- Ancla = fila mas temprana de la seleccion (primera en orden
    -- cronologico, ya garantizado por H.harmony ordenado). delta_qn de
    -- cada fila queda relativo a esa ancla -- ver nikMusicStateRowToQN.
    local anchor_qn = helpers.rowToQN(selected_rows[1])
    local clipboard = {}
    for _, row in ipairs(selected_rows) do
      table.insert(clipboard, { delta_qn = helpers.rowToQN(row) - anchor_qn, chord = row.chord })
    end
    H._armonia_clipboard = clipboard
    for _, row in ipairs(H.harmony) do row.selected = false end
    H._armonia_selection_anchor = nil
  end

  local clipboard_count = H._armonia_clipboard and #H._armonia_clipboard or 0
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, string.format('Pegar en cursor (%d)', clipboard_count), 170, 0) then
    if clipboard_count > 0 then
      local cursor_qn = helpers.captureCursorQN()
      local candidates = {}
      for _, entry in ipairs(H._armonia_clipboard) do
        local new_row = helpers.qnToRow(cursor_qn + entry.delta_qn)
        new_row.chord = entry.chord
        table.insert(candidates, new_row)
      end
      local collisions = findPositionCollisions(H, candidates)
      if #collisions > 0 then
        H._armonia_paste_pending = { candidates = candidates, collisions = collisions }
        reaper.ImGui_OpenPopup(ctx, 'armonia_paste_conflict')
      else
        applyPaste(H, helpers, candidates, {})
      end
    end
  end

  -- Firma de BeginPopupModal (p_open opcional, flags) puede variar
  -- levemente segun version de ReaImGui -- mismo gotcha ya anotado para
  -- BeginChild en el WIP, confirmar contra la instalacion real. Igual que
  -- BeginTable (no como BeginChild): EndPopup solo se llama si
  -- BeginPopupModal devolvio true.
  if reaper.ImGui_BeginPopupModal(ctx, 'armonia_paste_conflict', nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
    local pending = H._armonia_paste_pending
    local n = pending and #pending.collisions or 0
    reaper.ImGui_Text(ctx, string.format('Hay %d fila(s) existentes en la posicion de destino.', n))
    reaper.ImGui_Text(ctx, 'Sobrescribir las reemplaza puntualmente; Cancelar no pega nada.')
    reaper.ImGui_Spacing(ctx)
    if reaper.ImGui_Button(ctx, 'Sobrescribir y pegar', 160, 0) then
      applyPaste(H, helpers, pending.candidates, pending.collisions)
      H._armonia_paste_pending = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Cancelar', 100, 0) then
      H._armonia_paste_pending = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
  end
end

return M