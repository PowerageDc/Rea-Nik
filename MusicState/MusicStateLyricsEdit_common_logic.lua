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
  end_occupied = 'Ya hay un evento en la posicion del fin.',
}

local function getEd(S)
  if not S.edit then
    S.edit = { key_time = nil, key_end = false, buf = '', orig = '',
               active = false, msg = ' ', add_buf = '', add_active = false }
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

-- Alta de linea (campo "Agregar"). planAdd vacia el fin pendiente de la cola
-- ANTES de leer el track: si se insertara despues, el ctx quedaria viejo.
local function planAdd(S, helpers, t1, t2, text)
  local Lyrics = helpers.Lyrics
  helpers.LyricsSync.flush(S.sync, Lyrics)
  local track = Lyrics.FindLyricsTrack(0)
  local ctx = Lyrics.PlanLine(track, t1, t2)
  return track, ctx, Lyrics.DecideAdd(ctx, text)
end

-- Aplica el alta y deja la UI coherente: la seleccion pasa a la linea nueva
-- (o al fin creado, con texto vacio) y el cache recarga en el frame siguiente.
local function applyAdd(S, Ed, helpers, track, ctx, text, dec, replace_inside)
  local ok, res = helpers.Lyrics.ApplyLine(track, ctx, text, { replace_inside = replace_inside })
  if not ok then
    Ed.msg = MSG[res] or 'No se pudo agregar la linea.'
    return false
  end
  S.state_count = -1
  if text ~= '' then
    S.sel = { time = ctx.t1, is_end = false }
  else
    S.sel = { time = ctx.end_time, is_end = true }
  end
  S.scroll_sel = true
  if S.autoselect then S.reselect = true end
  Ed.add_buf = ''
  if text == '' then
    Ed.msg = 'Fin agregado.'
  elseif dec.has_line then
    Ed.msg = 'Linea reemplazada.'
  elseif dec.replaces_end then
    Ed.msg = 'Linea agregada (reemplazo el fin que estaba en el inicio).'
  else
    Ed.msg = 'Linea agregada.'
  end
  return true
end

local PREVIEW_MAX_ROWS = 5
local PREVIEW_MAX_CHARS = 50

-- Vista previa de lo que el alta va a pisar: lineas en el inicio y dentro de
-- la seleccion (los fines se cuentan aparte, no tienen texto). Se congela al
-- planificar: el modal muestra esto, no el ctx.
local function buildPreview(Lyrics, ctx)
  local rows, ends = {}, 0
  local function take(ev)
    if ev.text == Lyrics.END_MARK then
      ends = ends + 1
      return
    end
    local text = ev.text
    local cut = utf8.offset(text, PREVIEW_MAX_CHARS + 1)
    if cut then text = text:sub(1, cut - 1) .. '...' end
    rows[#rows + 1] = { pos = reaper.format_timestr_pos(ev.time, '', 2), text = text }
  end
  for _, ev in ipairs(ctx.at_start) do take(ev) end
  for _, ev in ipairs(ctx.inside) do take(ev) end
  local more = math.max(#rows - PREVIEW_MAX_ROWS, 0)
  for i = #rows, PREVIEW_MAX_ROWS + 1, -1 do rows[i] = nil end
  return { rows = rows, more = more, ends = ends }
end

local function tryAdd(S, Ed, helpers)
  local Lyrics = helpers.Lyrics
  local text = Lyrics.CleanText(Ed.add_buf or '')
  local t1, t2 = Lyrics.GetTimeContext()
  local track, ctx, dec = planAdd(S, helpers, t1, t2, text)
  if dec.kind == 'reject' then
    Ed.msg = MSG[dec.code] or 'No se pudo agregar la linea.'
  elseif dec.kind == 'apply' then
    applyAdd(S, Ed, helpers, track, ctx, text, dec, false)
  else
    Ed.add_pending = {
      t1 = t1, t2 = t2, text = text, proj = S.proj, open = true,
      kind = dec.kind, n = dec.n, has_line = dec.has_line,
      preview = buildPreview(Lyrics, ctx),
    }
    Ed.msg = 'Hay una linea o eventos en esa posicion (falta la confirmacion).'
  end
end

-- Resuelve el alta pendiente. Re-planifica con la misma posicion y texto, y
-- solo aplica si la decision sigue siendo la que el modal mostro: un tap, un
-- Ctrl+Z o una edicion con el modal abierto la cancelan en vez de aplicar a
-- ciegas. replace_inside: Reemplazar (true) o Conservar (false).
local function resolveAdd(S, Ed, helpers, replace_inside)
  local p = Ed.add_pending
  Ed.add_pending = nil
  if not p then return end
  local track, ctx, dec = planAdd(S, helpers, p.t1, p.t2, p.text)
  if dec.kind ~= p.kind or dec.n ~= p.n or dec.has_line ~= p.has_line then
    Ed.msg = 'Cambio el contenido en esa posicion: se cancelo el alta.'
    return
  end
  applyAdd(S, Ed, helpers, track, ctx, p.text, dec, replace_inside)
end

-- Modal de confirmacion del alta (patron del modal de pegado de Armonia).
-- Muestra la vista previa congelada de Ed.add_pending, no el ctx vivo.
local function drawAddModal(ctx, S, Ed, helpers)
  local p = Ed.add_pending
  if p and p.proj ~= S.proj then
    Ed.add_pending, p = nil, nil
  end
  if p and p.open then
    reaper.ImGui_OpenPopup(ctx, 'Agregar linea###lyrics_add_confirm')
    p.open = false
  end
  if reaper.ImGui_BeginPopupModal(ctx, 'Agregar linea###lyrics_add_confirm', nil,
      reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
    if not p then
      reaper.ImGui_CloseCurrentPopup(ctx)
    else
      local esc = p.armed and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape(), false)
      local enter = p.armed and (reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter(), false)
        or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter(), false))
      p.armed = true
      local pv = p.preview
      local lines = #pv.rows + pv.more
      if p.kind == 'confirm_line' then
        reaper.ImGui_Text(ctx, 'Ya hay una linea en esa posicion:')
      elseif lines == 0 then
        reaper.ImGui_Text(ctx, 'Dentro de la seleccion hay marcadores de fin.')
      elseif p.has_line then
        reaper.ImGui_Text(ctx, string.format(
          'Hay %d linea(s) en el inicio y dentro de la seleccion:', lines))
      else
        reaper.ImGui_Text(ctx, string.format(
          'Hay %d linea(s) dentro de la seleccion:', lines))
      end
      for _, r in ipairs(pv.rows) do
        reaper.ImGui_Text(ctx, string.format('%s   %s', r.pos, r.text))
      end
      if pv.more > 0 then
        reaper.ImGui_TextDisabled(ctx, string.format('... y %d mas', pv.more))
      end
      if pv.ends > 0 then
        reaper.ImGui_TextDisabled(ctx, string.format('Incluye %d marcador(es) de fin.', pv.ends))
      end
      if p.kind == 'confirm_inside' then
        reaper.ImGui_TextDisabled(ctx, 'Conservar: solo se reemplaza lo que haya en el inicio.')
      end
      reaper.ImGui_TextDisabled(ctx, p.kind == 'confirm_inside'
        and 'Enter o Esc: Cancelar' or 'Enter: Reemplazar  -  Esc: Cancelar')
      reaper.ImGui_Spacing(ctx)
      if p.kind == 'confirm_inside' then
        if reaper.ImGui_Button(ctx, 'Reemplazar todo##add_all', 130, 0) then
          resolveAdd(S, Ed, helpers, true)
          reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, 'Conservar##add_keep', 100, 0) then
          resolveAdd(S, Ed, helpers, false)
          reaper.ImGui_CloseCurrentPopup(ctx)
        end
      else
        if reaper.ImGui_Button(ctx, 'Reemplazar##add_one', 120, 0) then
          resolveAdd(S, Ed, helpers, true)
          reaper.ImGui_CloseCurrentPopup(ctx)
        end
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, 'Cancelar##add_cancel', 100, 0) or esc then
        Ed.add_pending = nil
        Ed.msg = ' '
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      if enter and Ed.add_pending == p then
        if p.kind == 'confirm_inside' then
          Ed.add_pending = nil
          Ed.msg = ' '
        else
          resolveAdd(S, Ed, helpers, true)
        end
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
    end
    reaper.ImGui_EndPopup(ctx)
  elseif p and not p.open then
    Ed.add_pending = nil
  end
end

local function drawAddRow(ctx, S, Ed, helpers)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx, 'Agregar')
  reaper.ImGui_SameLine(ctx, 60)
  reaper.ImGui_SetNextItemWidth(ctx, -110)
  local a_changed, a_val = reaper.ImGui_InputTextWithHint(ctx, '##lyric_add',
    'Texto de la linea (vacio = solo fin)', Ed.add_buf)
  if a_changed then Ed.add_buf = a_val end
  local a_deact = reaper.ImGui_IsItemDeactivated(ctx)
  Ed.add_active = reaper.ImGui_IsItemActive(ctx)
  local a_enter = a_deact
    and (reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter(), false)
      or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter(), false))
  reaper.ImGui_SameLine(ctx)
  local a_click = reaper.ImGui_Button(ctx, 'Agregar##lyric_add_btn', 100, 0)
  if a_click or a_enter then tryAdd(S, Ed, helpers) end
  drawAddModal(ctx, S, Ed, helpers)
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

  -- Alta de linea en el cursor o la seleccion de tiempo. Siempre habilitada.
  -- Enter agrega (igual que el boton, vacio = solo fin): Tab o click afuera no.
  drawAddRow(ctx, S, Ed, helpers)

  -- Linea de aviso siempre reservada (08_REAIMGUI_PATTERNS.md §4).
  reaper.ImGui_TextDisabled(ctx, Ed.msg)
end

-- Solo la fila de alta, para la tab sin track de Lyrics: el alta crea el track.
function M.drawAddOnly(ctx, S, H, helpers)
  local Ed = getEd(S)
  drawAddRow(ctx, S, Ed, helpers)
  reaper.ImGui_TextDisabled(ctx, Ed.msg)
end

return M