-- bulk_edit_timesig_ui.lua
-- UI ReaImGui para bulk_edit_timesig_logic.lua
-- Tabla de markers con checkbox + shift-click multiseleccion, inputs num/denom
-- editables por fila, y dos acciones de grupo sobre las filas tildadas:
--   - "Aplicar a ancla + heredar resto": la fila de menor indice tildada
--     recibe el compas tipeado arriba, el resto queda en 0/0 (heredar).
--   - "Heredar (0/0) en tildadas": todas las tildadas quedan en 0/0.

local script_path = ({reaper.get_action_context()})[2]:match('^(.*[\\/])')
local logic = dofile(script_path .. 'bulk_edit_timesig_logic.lua')

local proj = 0
local ctx = reaper.ImGui_CreateContext('Editar compases (bulk)')

-- Colores de resaltado de fila (0xRRGGBBAA)
local COLOR_CHECKED = 0x2E5FAA33   -- azul tenue: tildada, no ancla
local COLOR_ANCHOR  = 0xCC880055   -- ambar: fila ancla (recibe el valor explicito)

local candidates = {}
local has_sel = false
local last_clicked_row = nil
local pending_num, pending_denom = 4, 4

local function rescan()
  candidates, has_sel = logic.scan_candidates(proj)
  last_clicked_row = nil
end

rescan()

local function selectable_cell(label, timepos, cell_id)
  reaper.ImGui_TableNextColumn(ctx)
  if reaper.ImGui_Selectable(ctx, label .. '##' .. cell_id, false) then
    reaper.SetEditCurPos(timepos, true, false)
  end
end

-- Aplica un valor (num/denom) a la fila ancla y 0/0 (heredar) al resto de las tildadas
local function apply_anchor_inherit(num, denom)
  local anchor = logic.get_anchor_row(candidates)
  if not anchor then return end
  for i, c in ipairs(candidates) do
    if c.checked then
      if i == anchor then
        c.new_num, c.new_denom = num, denom
      else
        c.new_num, c.new_denom = 0, 0
      end
    end
  end
end

-- Pone 0/0 (heredar) en todas las filas tildadas, sin distinguir ancla
local function apply_inherit_all()
  for _, c in ipairs(candidates) do
    if c.checked then
      c.new_num, c.new_denom = 0, 0
    end
  end
end

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 760, 480, reaper.ImGui_Cond_FirstUseEver())
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 6, 6)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 10, 6)
  local visible, open = reaper.ImGui_Begin(ctx, 'Editar compases (bulk)', true)
  reaper.ImGui_PopStyleVar(ctx, 2)

  if visible then
    -- Reenvio de teclas de transporte/navegacion a Reaper (atajos custom).
    -- Se ignora mientras haya un input de texto con foco, para no interferir
    -- con la edicion de los campos num/denom.
    if reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_RootAndChildWindows())
       and not reaper.ImGui_IsAnyItemActive(ctx) then
      local key_actions = {
        [reaper.ImGui_Key_Space()]      = 40044,
        [reaper.ImGui_Key_Enter()]      = 40073,
        [reaper.ImGui_Key_W()]          = 40042,
        [reaper.ImGui_Key_End()]        = 40043,
        [reaper.ImGui_Key_LeftArrow()]  = 41041,
        [reaper.ImGui_Key_RightArrow()] = 41040,
      }
      for key, cmd_id in pairs(key_actions) do
        if reaper.ImGui_IsKeyPressed(ctx, key, false) then
          reaper.Main_OnCommand(cmd_id, 0)
        end
      end
    end

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TextDisabled(), 0x999999FF)
    local scope_label = has_sel and 'seleccion de tiempo activa' or 'todo el proyecto (sin seleccion)'
    reaper.ImGui_Text(ctx, string.format('Markers: %d  |  scope: %s', #candidates, scope_label))
    reaper.ImGui_PopStyleColor(ctx)

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Re-escanear') then rescan() end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Todos') then
      for _, c in ipairs(candidates) do c.checked = true end
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Ninguno') then
      for _, c in ipairs(candidates) do c.checked = false end
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    -- Bloque: definir valor a aplicar a la fila ancla + acciones de grupo
    reaper.ImGui_Text(ctx, 'Compas a aplicar (fila ancla):')
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_PushItemWidth(ctx, 70)
    local ch1, v1 = reaper.ImGui_InputInt(ctx, '##num', pending_num, 0, 0)
    if ch1 then pending_num = math.max(0, v1) end
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, '/')
    reaper.ImGui_SameLine(ctx)
    local ch2, v2 = reaper.ImGui_InputInt(ctx, '##denom', pending_denom, 0, 0)
    if ch2 then pending_denom = math.max(0, v2) end
    reaper.ImGui_PopItemWidth(ctx)

    local any_checked = logic.get_anchor_row(candidates) ~= nil

    reaper.ImGui_Spacing(ctx)
    local btn_w = 235
    if not any_checked then reaper.ImGui_BeginDisabled(ctx) end
    if reaper.ImGui_Button(ctx, 'Aplicar a ancla + heredar resto', btn_w, 0) then
      apply_anchor_inherit(pending_num, pending_denom)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Heredar (0/0) en tildadas', btn_w, 0) then
      apply_inherit_all()
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Congelar heredado en tildadas', btn_w, 0) then
      logic.freeze_inherited(candidates)
    end
    if not any_checked then reaper.ImGui_EndDisabled(ctx) end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    if reaper.ImGui_Button(ctx, 'Preview en consola') then
      logic.preview_console(candidates)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Aplicar seleccion') then
      logic.preview_console(candidates)
      local n = logic.count_changes(candidates)
      if n == 0 then
        reaper.ShowMessageBox('No hay cambios para aplicar (ver consola).', 'Info', 0)
      else
        local ok = reaper.ShowMessageBox(
          n .. ' markers van a cambiar (ver consola).\n\nContinuar?',
          'Confirmar edicion', 4)
        if ok == 6 then
          logic.apply_changes(proj, candidates)
          rescan()
        end
      end
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    -- Tabla en region con scroll propio: la botonera de arriba queda fija
    -- aunque haya muchas filas (ej. 145 markers en una cancion larga).
    reaper.ImGui_BeginChild(ctx, 'tbl_scroll', 0, 0)
    local flags = reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg()
    if reaper.ImGui_BeginTable(ctx, 'tbl', 8, flags) then
      reaper.ImGui_TableSetupColumn(ctx, '')
      reaper.ImGui_TableSetupColumn(ctx, 'idx')
      reaper.ImGui_TableSetupColumn(ctx, 'timepos')
      reaper.ImGui_TableSetupColumn(ctx, 'compas.tiempo')
      reaper.ImGui_TableSetupColumn(ctx, 'actual')
      reaper.ImGui_TableSetupColumn(ctx, 'bpm')
      reaper.ImGui_TableSetupColumn(ctx, 'nuevo num')
      reaper.ImGui_TableSetupColumn(ctx, 'nuevo denom')
      reaper.ImGui_TableHeadersRow(ctx)

      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x00000000)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x00000000)

      local anchor = logic.get_anchor_row(candidates)

      for row_i, c in ipairs(candidates) do
        reaper.ImGui_TableNextRow(ctx)

        if row_i == anchor then
          reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_RowBg1(), COLOR_ANCHOR)
        elseif c.checked then
          reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_RowBg1(), COLOR_CHECKED)
        end

        reaper.ImGui_TableNextColumn(ctx)
        local changed, new_val = reaper.ImGui_Checkbox(ctx, '##chk' .. row_i, c.checked)
        if changed then
          reaper.SetEditCurPos(c.timepos, true, false)
          -- Shift+click: togglea todo el rango entre la ultima fila clickeada
          -- y la actual al mismo estado del click actual (mismo patron que
          -- convert_simple_to_compound.lua).
          local shift_down = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
          if shift_down and last_clicked_row then
            local lo = math.min(last_clicked_row, row_i)
            local hi = math.max(last_clicked_row, row_i)
            for k = lo, hi do candidates[k].checked = new_val end
          else
            c.checked = new_val
          end
          last_clicked_row = row_i
        end

        selectable_cell(tostring(c.idx), c.timepos, 'idx' .. row_i)
        selectable_cell(string.format('%.3f', c.timepos), c.timepos, 'tp' .. row_i)
        selectable_cell(reaper.format_timestr_pos(c.timepos, '', 2), c.timepos, 'mb' .. row_i)
        local old_label = c.has_explicit and string.format('%d/%d', c.old_num, c.old_denom)
          or string.format('(hereda %d/%d)', c.effective_num, c.effective_denom)
        selectable_cell(old_label, c.timepos, 'old' .. row_i)
        selectable_cell(string.format('%.3f', c.bpm), c.timepos, 'bpm' .. row_i)

        reaper.ImGui_TableNextColumn(ctx)
        reaper.ImGui_PushItemWidth(ctx, 70)
        local chn, vn = reaper.ImGui_InputInt(ctx, '##newnum' .. row_i, c.new_num, 0, 0)
        if chn then c.new_num = math.max(0, vn) end
        reaper.ImGui_PopItemWidth(ctx)

        reaper.ImGui_TableNextColumn(ctx)
        reaper.ImGui_PushItemWidth(ctx, 70)
        local chd, vd = reaper.ImGui_InputInt(ctx, '##newdenom' .. row_i, c.new_denom, 0, 0)
        if chd then c.new_denom = math.max(0, vd) end
        reaper.ImGui_PopItemWidth(ctx)
      end

      reaper.ImGui_PopStyleColor(ctx, 2)
      reaper.ImGui_EndTable(ctx)
    end
    reaper.ImGui_EndChild(ctx)

    reaper.ImGui_End(ctx)
  end

  if open then reaper.defer(loop) end
end

reaper.defer(loop)
