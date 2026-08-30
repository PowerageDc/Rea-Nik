-- bulk_edit_timesig_logic.lua
-- Modulo de logica pura (sin UI) para edicion en bloque de tempo/timesig markers.
-- Usado por bulk_edit_timesig_ui.lua

local M = {}

-- Escanea TODOS los tempo/timesig markers (con o sin compas explicito)
-- dentro de la seleccion de tiempo activa, o todo el proyecto si no hay
-- seleccion. Orden = cronologico
-- (mismo orden que CountTempoTimeSigMarkers), por lo que la fila de menor
-- indice en la tabla resultante es siempre la mas temprana en el tiempo.
function M.scan_candidates(proj)
  proj = proj or 0
  local candidates = {}
  local sel_start, sel_end = reaper.GetSet_LoopTimeRange2(proj, false, false, 0, 0, false)
  local has_sel = sel_end > sel_start

  local scope_start, scope_end = sel_start, sel_end
  if not has_sel then
    scope_start, scope_end = 0, reaper.GetProjectLength(proj)
  end

  local count = reaper.CountTempoTimeSigMarkers(proj)
  for i = 0, count - 1 do
    local retval, timepos, _, _, bpm, num, denom, lineartempo = reaper.GetTempoTimeSigMarker(proj, i)
    if retval and timepos >= scope_start and timepos < scope_end then
      local has_explicit = num > 0
      local norm_num = has_explicit and num or 0
      local norm_denom = has_explicit and denom or 0

      -- Compas efectivo en este punto (resuelve la herencia real, no solo
      -- el flag propio del marker). Para markers ya explicitos, coincide
      -- con su propio valor.
      local eff_num, eff_denom = norm_num, norm_denom
      if not has_explicit then
        eff_num, eff_denom = reaper.TimeMap_GetTimeSigAtTime(proj, timepos)
      end

      table.insert(candidates, {
        idx = i,
        timepos = timepos,
        bpm = bpm,
        has_explicit = has_explicit,
        old_num = norm_num,
        old_denom = norm_denom,
        effective_num = eff_num,
        effective_denom = eff_denom,
        lineartempo = lineartempo,
        new_num = norm_num,
        new_denom = norm_denom,
        checked = false,
      })
    end
  end

  return candidates, has_sel
end

-- Snapshot de timepos de TODOS los markers del proyecto (no solo candidatos),
-- usado para restaurar posiciones tras el drift en cascada (ver tempo_mapping.md).
function M.capture_all_timepos(proj)
  proj = proj or 0
  local snap = {}
  local count = reaper.CountTempoTimeSigMarkers(proj)
  for i = 0, count - 1 do
    local retval, timepos = reaper.GetTempoTimeSigMarker(proj, i)
    snap[i] = timepos
  end
  return snap
end

-- Indice (dentro de candidates) de la fila "ancla": la de menor indice entre
-- las tildadas. Devuelve nil si no hay ninguna tildada. Se recalcula en cada
-- llamada -- no es un estado propio, es derivado del set de checkboxes.
function M.get_anchor_row(candidates)
  for i, c in ipairs(candidates) do
    if c.checked then return i end
  end
  return nil
end

-- "Congela" el compas efectivo actual (heredado o propio) como valor
-- explicito en las filas tildadas. Usar en el marker siguiente a un rango
-- que se va a reconvertir, para que conserve su metrica real aunque el
-- bloque anterior cambie de compas.
function M.freeze_inherited(candidates)
  for _, c in ipairs(candidates) do
    if c.checked then
      c.new_num, c.new_denom = c.effective_num, c.effective_denom
    end
  end
end

-- Cuenta cuantos markers tildados tienen un cambio real respecto al valor actual.
function M.count_changes(candidates)
  local n = 0
  for _, c in ipairs(candidates) do
    if c.checked and (c.new_num ~= c.old_num or c.new_denom ~= c.old_denom) then
      n = n + 1
    end
  end
  return n
end

function M.preview_console(candidates)
  reaper.ClearConsole()
  reaper.ShowConsoleMsg('--- Preview edicion de compases (tildados) ---\n')
  local n = 0
  for _, c in ipairs(candidates) do
    if c.checked then
      n = n + 1
      local new_label
      if c.new_num == 0 then
        new_label = '(heredar)'
      else
        new_label = string.format('%d/%d', c.new_num, c.new_denom)
      end
      local old_label = c.has_explicit and string.format('%d/%d', c.old_num, c.old_denom)
        or string.format('(hereda %d/%d)', c.effective_num, c.effective_denom)
      reaper.ShowConsoleMsg(string.format(
        'idx=%d  t=%.4f  %s  ->  %s\n',
        c.idx, c.timepos, old_label, new_label))
    end
  end
  reaper.ShowConsoleMsg(string.format('Total a aplicar: %d\n', n))
end

-- Aplica los cambios de compas de las filas tildadas, con doble pasada
-- para evitar drift en cascada (ver tempo_mapping.md, gotcha SetTempoTimeSigMarker).
function M.apply_changes(proj, candidates)
  proj = proj or 0
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local original_timepos = M.capture_all_timepos(proj)

  -- Pasada 1: aplicar compas nuevo solo en filas tildadas
  for _, c in ipairs(candidates) do
    if c.checked then
      reaper.SetTempoTimeSigMarker(proj, c.idx, c.timepos, -1, -1,
        c.bpm, c.new_num, c.new_denom, c.lineartempo)
    end
  end

  -- Pasada 2: restaurar timepos original de TODOS los markers del proyecto
  local count = reaper.CountTempoTimeSigMarkers(proj)
  for i = 0, count - 1 do
    local retval, timepos, _, _, bpm, num, denom, lineartempo = reaper.GetTempoTimeSigMarker(proj, i)
    if retval and original_timepos[i] then
      reaper.SetTempoTimeSigMarker(proj, i, original_timepos[i], -1, -1, bpm, num, denom, lineartempo)
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.UpdateTimeline()
  reaper.Undo_EndBlock('Editar compases de tempo markers en bloque', -1)
end

return M
