-- stem_fragment_capture.lua
-- Módulo de lógica (sin UI) para captura de fragmentos y split+glue
-- No ejecutar directamente: es consumido por stem_fragment_ui.lua vía require()

local M = {}

-- ============================================================
-- Estado global del módulo
-- ============================================================
M.state = {
  duplicated_track = nil,
  source_track = nil,
  fragments = {},
  next_id = 1,
}

-- ============================================================
-- Utilidades internas
-- ============================================================

-- Devuelve el primer item de un track (asume un solo item, según lo confirmado)
local function get_first_item(track)
  if not track then return nil end
  if reaper.CountTrackMediaItems(track) == 0 then return nil end
  return reaper.GetTrackMediaItem(track, 0)
end

-- Posición de inicio del primer item de un track
function M.get_item_start(track)
  local item = get_first_item(track)
  if not item then return 0 end
  return reaper.GetMediaItemInfo_Value(item, "D_POSITION")
end

-- Formatea una posición en segundos como compases:beats (para la tabla UI)
function M.format_time_compases(pos)
  return reaper.format_timestr_pos(pos, "", 2) -- modo 2 = measures.beats
end

-- ============================================================
-- Duplicar track
-- ============================================================

-- Duplica el track dado, lo nombra "<Original> (ReaBeat ref)" y lo deja seleccionado.
-- Devuelve el nuevo MediaTrack*, o nil si falla.
function M.duplicar_track(source_track)
  if not source_track then return nil end

  reaper.SetOnlyTrackSelected(source_track)
  reaper.Main_OnCommand(40062, 0) -- Track: Duplicate tracks

  local dup_track = reaper.GetSelectedTrack(0, 0)
  if not dup_track then return nil end

  local _, src_name = reaper.GetTrackName(source_track)
  reaper.GetSetMediaTrackInfo_String(dup_track, "P_NAME", src_name .. " (ReaBeat ref)", true)

  M.state.source_track = source_track
  M.state.duplicated_track = dup_track
  M.state.fragments = {}
  M.state.next_id = 1

  return dup_track
end

-- ============================================================
-- Captura de fragmentos ("Marcar corte")
-- ============================================================

-- Devuelve true si agregó un fragmento, false + mensaje de error si no.
function M.marcar_corte()
  if not M.state.duplicated_track then
    return false, "No hay track duplicado activo."
  end

  local time_sel_start, time_sel_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local has_time_selection = (time_sel_end - time_sel_start) > 0.0001

  local frag_start, frag_end

  if has_time_selection then
    frag_start = time_sel_start
    frag_end   = time_sel_end
  else
    local edit_cursor = reaper.GetCursorPosition()
    local last_frag = M.state.fragments[#M.state.fragments]
    frag_start = last_frag and last_frag.end_pos or M.get_item_start(M.state.duplicated_track)
    frag_end   = edit_cursor
  end

  if frag_end <= frag_start then
    return false, "El punto de corte debe ser posterior al inicio del fragmento."
  end

  local _, src_name = reaper.GetTrackName(M.state.source_track)

  table.insert(M.state.fragments, {
    id = M.state.next_id,
    start_pos = frag_start,
    end_pos = frag_end,
    source_track_name = src_name,
  })
  M.state.next_id = M.state.next_id + 1

  return true
end

-- Elimina un fragmento de la lista por id (no por índice)
function M.eliminar_fragmento(id)
  for i, frag in ipairs(M.state.fragments) do
    if frag.id == id then
      table.remove(M.state.fragments, i)
      return true
    end
  end
  return false
end

-- Indica si el fragmento en `index` es discontinuo respecto al anterior (para columna ⚠)
function M.es_discontinuo(index)
  if index <= 1 then return false end
  local prev = M.state.fragments[index - 1]
  local curr = M.state.fragments[index]
  if not prev or not curr then return false end
  return math.abs(curr.start_pos - prev.end_pos) > 0.0001
end

-- ============================================================
-- Aplicar: split + glue por fragmento
-- ============================================================

-- Texto de preview para consola/confirmación antes de ejecutar
function M.generar_preview()
  local lines = {}
  table.insert(lines, string.format("Se van a crear %d fragmentos sobre '%s':",
    #M.state.fragments, select(2, reaper.GetTrackName(M.state.duplicated_track))))
  for i, frag in ipairs(M.state.fragments) do
    table.insert(lines, string.format("  #%d  %s -> %s  (%.2fs)",
      i, M.format_time_compases(frag.start_pos), M.format_time_compases(frag.end_pos),
      frag.end_pos - frag.start_pos))
  end
  return table.concat(lines, "\n")
end

-- Ejecuta split + glue por fragmento sobre el track duplicado.
-- Asume M.state.fragments ya validado (llamar generar_preview + confirmación antes).
function M.aplicar_split_glue()
  local track = M.state.duplicated_track
  if not track then return false, "No hay track duplicado activo." end
  if #M.state.fragments == 0 then return false, "No hay fragmentos para aplicar." end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  -- Puntos de split únicos (inicio y fin de cada fragmento)
  local split_points, seen = {}, {}
  for _, frag in ipairs(M.state.fragments) do
    for _, pos in ipairs({ frag.start_pos, frag.end_pos }) do
      local key = string.format("%.6f", pos)
      if not seen[key] then
        seen[key] = true
        table.insert(split_points, pos)
      end
    end
  end
  table.sort(split_points)

  for _, pos in ipairs(split_points) do
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
      local candidate = reaper.GetTrackMediaItem(track, i)
      local s = reaper.GetMediaItemInfo_Value(candidate, "D_POSITION")
      local e = s + reaper.GetMediaItemInfo_Value(candidate, "D_LENGTH")
      if pos > s + 0.0001 and pos < e - 0.0001 then
        reaper.SplitMediaItem(candidate, pos)
      end
    end
  end

  -- Glue por fragmento
  reaper.SelectAllMediaItems(0, false)
  local _, src_name = reaper.GetTrackName(M.state.source_track)

  for i, frag in ipairs(M.state.fragments) do
    for j = 0, reaper.CountTrackMediaItems(track) - 1 do
      local candidate = reaper.GetTrackMediaItem(track, j)
      local s = reaper.GetMediaItemInfo_Value(candidate, "D_POSITION")
      if math.abs(s - frag.start_pos) < 0.0001 then
        reaper.SetMediaItemSelected(candidate, true)
      end
    end
    reaper.Main_OnCommand(40362, 0) -- Item: Glue items

    local glued = reaper.GetSelectedMediaItem(0, 0)
    if glued then
      local take = reaper.GetActiveTake(glued)
      if take then
        reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME",
          string.format("%s_frag%02d", src_name, i), true)
      end
    end
    reaper.SelectAllMediaItems(0, false)
  end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Split+Glue fragmentos ReaBeat", -1)
  reaper.UpdateArrange()

  return true
end

return M