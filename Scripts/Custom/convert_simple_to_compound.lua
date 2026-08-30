-- convert_simple_to_compound.lua
-- Convierte tempo/timesig markers de ReaBeat mal-etiquetados en compas simple (X/4)
-- a su equivalente compuesto ternario (X*3 / 8), con BPM x0.75 (formula validada).
-- Aplica con doble pasada para evitar drift en cascada sobre markers posteriores.

local ctx = reaper.ImGui_CreateContext('Convertir a compas compuesto')

local BPM_FACTOR = 0.75
local MIN_NUM, MAX_NUM = 2, 7
local TARGET_DENOM = 8

local candidates = {}
local last_clicked_row = nil

local function scan_candidates()
  candidates = {}
  local has_sel = false
  local ts, te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if te > ts then has_sel = true end

  local count = reaper.CountTempoTimeSigMarkers(0)
  for i = 0, count - 1 do
    local retval, timepos, _, _, bpm, num, denom = reaper.GetTempoTimeSigMarker(0, i)
    if retval then
      local in_scope = true
      if has_sel then
        in_scope = timepos >= ts and timepos < te
      end
      if in_scope and denom == 4 and num >= MIN_NUM and num <= MAX_NUM then
        table.insert(candidates, {
          idx = i, timepos = timepos,
          old_num = num, old_denom = denom, old_bpm = bpm,
          new_num = num * 3, new_denom = TARGET_DENOM, new_bpm = bpm * BPM_FACTOR,
          checked = true,
        })
      end
    end
  end
end

local function capture_all_timepos()
  local snap = {}
  local count = reaper.CountTempoTimeSigMarkers(0)
  for i = 0, count - 1 do
    local retval, timepos = reaper.GetTempoTimeSigMarker(0, i)
    snap[i] = timepos
  end
  return snap
end

local function preview_console()
  reaper.ClearConsole()
  reaper.ShowConsoleMsg('--- Preview conversion (tildados) ---\n')
  local n = 0
  for _, c in ipairs(candidates) do
    if c.checked then
      n = n + 1
      reaper.ShowConsoleMsg(string.format(
        'idx=%d  t=%.4f  %d/%d @ %.4f  ->  %d/%d @ %.4f\n',
        c.idx, c.timepos, c.old_num, c.old_denom, c.old_bpm,
        c.new_num, c.new_denom, c.new_bpm))
    end
  end
  reaper.ShowConsoleMsg(string.format('Total a convertir: %d\n', n))
end

local function apply_conversion()
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local original_timepos = capture_all_timepos() -- todos, no solo candidatos

  -- Pasada 1: compas/bpm nuevo solo en tildados
  for _, c in ipairs(candidates) do
    if c.checked then
      reaper.SetTempoTimeSigMarker(0, c.idx, c.timepos, -1, -1,
        c.new_bpm, c.new_num, c.new_denom, false)
    end
  end

  -- Pasada 2: restaurar timepos original de TODOS los markers (corrige drift)
  local count = reaper.CountTempoTimeSigMarkers(0)
  for i = 0, count - 1 do
    local retval, timepos, _, _, bpm, num, denom, lineartempo = reaper.GetTempoTimeSigMarker(0, i)
    if retval and original_timepos[i] then
      reaper.SetTempoTimeSigMarker(0, i, original_timepos[i], -1, -1, bpm, num, denom, lineartempo)
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.UpdateTimeline()
  reaper.Undo_EndBlock('Convertir markers a compas compuesto', -1)
end

scan_candidates()

local function selectable_cell(label, timepos, cell_id)
  reaper.ImGui_TableNextColumn(ctx)
  if reaper.ImGui_Selectable(ctx, label .. '##' .. cell_id, false) then
    reaper.SetEditCurPos(timepos, true, false)
  end
end

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 680, 420, reaper.ImGui_Cond_FirstUseEver())
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 6, 6)
  local visible, open = reaper.ImGui_Begin(ctx, 'Convertir a compas compuesto', true)
  reaper.ImGui_PopStyleVar(ctx)
  if visible then
    reaper.ImGui_Text(ctx, string.format('Candidatos: %d', #candidates))
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Todos') then
      for _, c in ipairs(candidates) do c.checked = true end
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Ninguno') then
      for _, c in ipairs(candidates) do c.checked = false end
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Re-escanear') then
      scan_candidates()
    end

    -- OJO: combinacion de flags con "|" -- si tu binding de ReaImGui no expone
    -- estas funciones con estos nombres exactos, avisame el error de consola.
    local flags = reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg()
    if reaper.ImGui_BeginTable(ctx, 'tbl', 8, flags) then
      reaper.ImGui_TableSetupColumn(ctx, '')
      reaper.ImGui_TableSetupColumn(ctx, 'idx')
      reaper.ImGui_TableSetupColumn(ctx, 'timepos')
      reaper.ImGui_TableSetupColumn(ctx, 'compas.tiempo')
      reaper.ImGui_TableSetupColumn(ctx, 'actual')
      reaper.ImGui_TableSetupColumn(ctx, 'bpm actual')
      reaper.ImGui_TableSetupColumn(ctx, 'nuevo')
      reaper.ImGui_TableSetupColumn(ctx, 'bpm nuevo')
      reaper.ImGui_TableHeadersRow(ctx)

      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x00000000)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x00000000)
      for row_i, c in ipairs(candidates) do
        reaper.ImGui_TableNextRow(ctx)

        reaper.ImGui_TableNextColumn(ctx)
        local changed, new_val = reaper.ImGui_Checkbox(ctx, '##chk' .. row_i, c.checked)
        if changed then
          reaper.SetEditCurPos(c.timepos, true, false)
          -- OJO: nombre de funcion/constante para detectar Shift puede variar
          -- segun version de ReaImGui. Si tira error, probar
          -- reaper.ImGui_GetKeyMods(ctx) y comparar contra ImGui_Mod_Shift().
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
        selectable_cell(string.format('%d/%d', c.old_num, c.old_denom), c.timepos, 'old' .. row_i)
        selectable_cell(string.format('%.3f', c.old_bpm), c.timepos, 'obpm' .. row_i)
        selectable_cell(string.format('%d/%d', c.new_num, c.new_denom), c.timepos, 'new' .. row_i)
        selectable_cell(string.format('%.3f', c.new_bpm), c.timepos, 'nbpm' .. row_i)
      end
      reaper.ImGui_PopStyleColor(ctx, 2)
      reaper.ImGui_EndTable(ctx)
    end

    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_Button(ctx, 'Preview en consola') then
      preview_console()
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Aplicar seleccion') then
      preview_console()
      local ok = reaper.ShowMessageBox(
        'Se van a convertir los markers tildados (ver consola).\n\nContinuar?',
        'Confirmar conversion', 4)
      if ok == 6 then
        apply_conversion()
        scan_candidates()
      end
    end

    reaper.ImGui_End(ctx)
  end

  if open then reaper.defer(loop) end
end

reaper.defer(loop)