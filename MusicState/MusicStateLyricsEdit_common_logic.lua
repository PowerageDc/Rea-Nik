-- MusicStateLyricsEdit_common_logic.lua
-- Panel de edicion de la fila seleccionada de la tab Lyrics (paso 3c).
-- Consumido solo por la tab (helpers.LyricsEdit). Estado en S.edit
-- (S = H._lyrics). La logica vive en MusicStateLyrics_common_logic.lua;
-- cada cambio se avisa a la cola de tap con helpers.LyricsSync.

local M = {}

local MSG = {
  empty = 'El texto no puede quedar vacio (usa Borrar).',
  reserved = 'El simbolo de fin no es un texto valido.',
  not_found = 'La linea ya no existe.',
  no_track = 'No hay un track de Lyrics.',
  no_end = 'La linea no tiene fin.',
  has_end = 'La linea ya tiene fin.',
  same = 'Ya esta en esa posicion.',
  at_limit = 'Tope: hay un evento vecino.',
  blocked = 'No hay margen entre los eventos vecinos.',
  out_of_range = 'Fuera de rango: cruzaria o pisaria un evento vecino.',
}

local function getEd(S)
  if not S.edit then
    S.edit = { key_time = nil, key_end = false, buf = '', orig = '',
               active = false, msg = ' ' }
  end
  return S.edit
end

-- Ejecuta una edicion con el contrato de la cola: vacia el fin pendiente
-- antes, avisa del cambio despues y fuerza el refresh del cache de la tab
-- (state_count = -1: la tab recarga al inicio del proximo frame).
local function run(S, Ed, helpers, fn, key, a, b)
  helpers.LyricsSync.flush(S.sync, helpers.Lyrics)
  local ok, res = fn(key, a, b)
  if ok then
    helpers.LyricsSync.onEdit(S.sync, helpers.Lyrics, res)
    S.state_count = -1
    if res.kind == 'move' or res.kind == 'endadd'
      or (res.kind == 'delete' and res.which == 'end') then
      S.reselect = true
    end
  else
    Ed.msg = MSG[res] or 'No se pudo aplicar el cambio.'
  end
  return ok, res
end

local STEPS = { -100, -20, 20, 100 }

-- Aplica un movimiento y deja la UI coherente en el frame de transicion: el
-- cache de la tab recarga recien en el proximo frame, asi que se parchea el
-- tiempo del evento movido, la clave del borrador y la seleccion (que sigue
-- al evento) para que el panel no parpadee ni borre el aviso.
local function applyMove(S, Ed, helpers, key, new_time, opts)
  local Lyrics = helpers.Lyrics
  local ok, res = run(S, Ed, helpers, Lyrics.MoveEvent, key, new_time, opts)
  if not ok then return end
  local eps = Lyrics.EPS_TIME
  local ci = Lyrics.Resolve(S.events, key)
  if ci then
    S.events[ci].time = res.new_time
    S.events[ci].pos_str = reaper.format_timestr_pos(res.new_time, '', 2)
  end
  if Ed.key_time and Ed.key_end == key.is_end and math.abs(Ed.key_time - key.time) <= eps then
    Ed.key_time = res.new_time
  end
  if S.sel and S.sel.is_end == key.is_end and math.abs(S.sel.time - key.time) <= eps then
    S.sel = { time = res.new_time, is_end = key.is_end }
    S.scroll_sel = true
  end
  Ed.msg = res.clamped and 'Movido hasta el tope (evento vecino).'
    or ('Movido a ' .. reaper.format_timestr_pos(res.new_time, '', 2))
end

-- Fila de nudge + "Al cursor". key: evento a mover (nil = deshabilitado).
-- add_key: linea sin fin; con key nil, "Al cursor" crea su fin.
local function moveRow(ctx, S, Ed, helpers, id, label, key, add_key, with_end)
  reaper.ImGui_Text(ctx, label)
  reaper.ImGui_SameLine(ctx, 60)
  reaper.ImGui_BeginDisabled(ctx, not key)
  for _, d in ipairs(STEPS) do
    if reaper.ImGui_Button(ctx, string.format('%+d##%s%d', d, id, d), 48, 0) and key then
      applyMove(S, Ed, helpers, key, key.time + d / 1000, { clamp = true, with_end = with_end })
    end
    reaper.ImGui_SameLine(ctx)
  end
  reaper.ImGui_EndDisabled(ctx)
  reaper.ImGui_BeginDisabled(ctx, not (key or add_key))
  if reaper.ImGui_Button(ctx, 'Al cursor##' .. id, 90, 0) and (key or add_key) then
    local t = reaper.GetCursorPosition()
    if key then
      applyMove(S, Ed, helpers, key, t, { with_end = with_end })
    elseif run(S, Ed, helpers, helpers.Lyrics.AddEnd, add_key, t) then
      Ed.msg = 'Fin agregado.'
    end
  end
  reaper.ImGui_EndDisabled(ctx)
end

function M.draw(ctx, S, H, helpers)
  local Lyrics = helpers.Lyrics
  local Ed = getEd(S)
  local sel_i = S.sel and Lyrics.Resolve(S.events, S.sel) or nil
  local ev = sel_i and S.events[sel_i] or nil

  -- Borrador: se recarga solo con el campo inactivo, si cambio la fila
  -- seleccionada o el texto del evento (Ctrl+Z, edicion externa).
  if ev and not Ed.active then
    local same = Ed.key_time and Ed.key_end == ev.is_end
      and math.abs(Ed.key_time - ev.time) <= Lyrics.EPS_TIME
    if not same or Ed.orig ~= ev.text then
      if not same then Ed.msg = ' ' end
      Ed.key_time, Ed.key_end = ev.time, ev.is_end
      Ed.buf, Ed.orig = ev.text, ev.text
    end
  end

  if ev then
    local extra = ev.dur and string.format('  (%s %.2f s)', Lyrics.END_MARK, ev.dur) or ''
    reaper.ImGui_Text(ctx, string.format('%s en %s%s',
      ev.is_end and 'Fin' or 'Linea', ev.pos_str, extra))
  else
    reaper.ImGui_TextDisabled(ctx, 'Selecciona una linea o un fin de la lista para editarla.')
  end

  -- Commit al perder el foco (Enter, Tab o click afuera). Esc revierte el
  -- campo al original, asi que no hay cambio que aplicar. El commit usa la
  -- clave del borrador, no la seleccion actual: el click en otra fila
  -- desactiva el campo antes de que la seleccion cambie.
  reaper.ImGui_SetNextItemWidth(ctx, -1)
  reaper.ImGui_BeginDisabled(ctx, not ev or ev.is_end)
  local changed, v = reaper.ImGui_InputText(ctx, '##lyric_edit', Ed.buf)
  if changed then Ed.buf = v end
  local deact = reaper.ImGui_IsItemDeactivatedAfterEdit(ctx)
  Ed.active = reaper.ImGui_IsItemActive(ctx)
  reaper.ImGui_EndDisabled(ctx)
  if deact and Ed.key_time and not Ed.key_end then
    local text = Lyrics.CleanText(Ed.buf)
    if text ~= Ed.orig then
      local key = { time = Ed.key_time, is_end = false }
      if run(S, Ed, helpers, Lyrics.SetText, key, text) then
        Ed.orig = text
        Ed.msg = 'Texto actualizado.'
      end
    end
    Ed.buf = Ed.orig
  end

  reaper.ImGui_BeginDisabled(ctx, not ev)
  if reaper.ImGui_Button(ctx, 'Ir al inicio', 100, 0) and ev then
    reaper.SetEditCurPos(ev.time, true, false)
  end
  reaper.ImGui_SameLine(ctx)
  local del_label = (ev and ev.is_end) and 'Borrar fin' or 'Borrar linea'
  if reaper.ImGui_Button(ctx, del_label .. '###lyric_del', 110, 0) and ev then
    local key = { time = ev.time, is_end = ev.is_end }
    local fn = ev.is_end and Lyrics.DeleteEnd or Lyrics.DeleteLine
    if run(S, Ed, helpers, fn, key) then
      Ed.msg = ev.is_end and 'Fin borrado.' or 'Linea borrada.'
      S.sel = nil
      if S.autoselect and not ev.is_end then
        reaper.GetSet_LoopTimeRange(true, false, 0, 0, false)
        reaper.UpdateArrange()
      end
    end
  end
  reaper.ImGui_EndDisabled(ctx)

  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_BeginDisabled(ctx, not (ev and not ev.is_end and ev.end_idx))
  if reaper.ImGui_Button(ctx, 'Borrar solo el fin###lyric_delend', 140, 0) and ev then
    local key = { time = ev.time, is_end = false }
    if run(S, Ed, helpers, Lyrics.DeleteEnd, key) then Ed.msg = 'Fin borrado.' end
  end
  reaper.ImGui_EndDisabled(ctx)

  -- Posicion: nudge en ms y "Al cursor". Un evento nunca cruza ni pisa a un
  -- vecino: el nudge se detiene en el tope, "Al cursor" rechaza.
  local line_key, end_key, add_key
  if ev then
    if ev.is_end then
      end_key = { time = ev.time, is_end = true }
    else
      line_key = { time = ev.time, is_end = false }
      local e = ev.end_idx and S.events[ev.end_idx]
      if e then end_key = { time = e.time, is_end = true } else add_key = line_key end
    end
  end
  local has_end = ev and not ev.is_end and ev.end_idx ~= nil
  moveRow(ctx, S, Ed, helpers, 'start', 'Inicio', line_key, nil, Ed.with_end and has_end)
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_BeginDisabled(ctx, not has_end)
  local w_changed, w_val = reaper.ImGui_Checkbox(ctx, 'El fin acompaña', Ed.with_end or false)
  if w_changed then Ed.with_end = w_val end
  reaper.ImGui_EndDisabled(ctx)
  moveRow(ctx, S, Ed, helpers, 'end', 'Fin', end_key, add_key, false)

  -- Linea de aviso siempre reservada (08_REAIMGUI_PATTERNS.md §4).
  reaper.ImGui_TextDisabled(ctx, Ed.msg)
end

return M