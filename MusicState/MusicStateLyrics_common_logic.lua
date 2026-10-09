local M = {}

M.TRACK_NAME_PATTERN = "lyrics"

function M.FindLyricsTrack(proj)
  proj = proj or 0
  for i = 0, reaper.CountTracks(proj) - 1 do
    local tr = reaper.GetTrack(proj, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if name:lower():find(M.TRACK_NAME_PATTERN, 1, true) then
      return tr, name
    end
  end
  return nil
end

M.END_MARK = "·"
M.DEFAULT_TRACK_NAME = "🎤 Lyrics"
M.EPS_TIME = 0.01
M.PAD_TIME = 5

function M.CreateLyricsTrack()
  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  local tr = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", M.DEFAULT_TRACK_NAME, true)
  return tr
end

function M.CollectEvents(track)
  local list = {}
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local take = reaper.GetActiveTake(reaper.GetTrackMediaItem(track, i))
    if take and reaper.TakeIsMIDI(take) then
      local _, _, _, textCnt = reaper.MIDI_CountEvts(take)
      for e = 0, textCnt - 1 do
        local _, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, e)
        if etype == 5 then
          list[#list + 1] = {
            take = take,
            idx = e,
            text = msg,
            time = reaper.MIDI_GetProjTimeFromPPQPos(take, ppq),
          }
        end
      end
    end
  end
  table.sort(list, function(a, b) return a.time < b.time end)
  return list
end

function M.EventsNear(list, t)
  local out = {}
  for _, ev in ipairs(list) do
    if math.abs(ev.time - t) <= M.EPS_TIME then out[#out + 1] = ev end
  end
  return out
end

function M.EventsBetween(list, t1, t2)
  local out = {}
  for _, ev in ipairs(list) do
    if ev.time > t1 + M.EPS_TIME and ev.time < t2 - M.EPS_TIME then
      out[#out + 1] = ev
    end
  end
  return out
end

function M.DeleteEvents(list)
  local byTake = {}
  for _, ev in ipairs(list) do
    byTake[ev.take] = byTake[ev.take] or {}
    table.insert(byTake[ev.take], ev.idx)
  end
  for take, idxs in pairs(byTake) do
    table.sort(idxs, function(a, b) return a > b end)
    for _, idx in ipairs(idxs) do
      reaper.MIDI_DeleteTextSysexEvt(take, idx)
    end
    reaper.MIDI_Sort(take)
  end
end

function M.EnsureTake(track, t_from, t_to)
  local last = math.max(t_from, t_to)
  local need_end = last + M.PAD_TIME
  local prev, prev_pos
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local it = reaper.GetTrackMediaItem(track, i)
    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    if pos <= t_from + M.EPS_TIME and (not prev_pos or pos > prev_pos) then
      local tk = reaper.GetActiveTake(it)
      if tk and reaper.TakeIsMIDI(tk) then
        prev, prev_pos = it, pos
      end
    end
  end
  if not prev then
    -- Sin item previo al destino: si ya hay items MIDI, se extiende el inicio
    -- del primero hasta 0 (los eventos conservan su tiempo de proyecto, probe
    -- E0 T4). Un item nuevo desde 0 se solaparia con ellos (T5a).
    local first, first_pos
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
      local it = reaper.GetTrackMediaItem(track, i)
      local tk = reaper.GetActiveTake(it)
      local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      if tk and reaper.TakeIsMIDI(tk) and (not first_pos or pos < first_pos) then
        first, first_pos = it, pos
      end
    end
    if not first then
      prev = reaper.CreateNewMIDIItemInProj(track, 0, need_end, false)
      return reaper.GetActiveTake(prev)
    end
    local first_end = first_pos + reaper.GetMediaItemInfo_Value(first, "D_LENGTH")
    reaper.MIDI_SetItemExtents(first, reaper.TimeMap2_timeToQN(0, 0),
      reaper.TimeMap2_timeToQN(0, first_end))
    prev, prev_pos = first, reaper.GetMediaItemInfo_Value(first, "D_POSITION")
  end
  local len = reaper.GetMediaItemInfo_Value(prev, "D_LENGTH")
  if prev_pos + len < last + M.EPS_TIME then
    -- La extension no pasa del inicio del item siguiente (T5b: lo solapaba).
    local cap
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
      local it = reaper.GetTrackMediaItem(track, i)
      local tk = reaper.GetActiveTake(it)
      local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      if tk and reaper.TakeIsMIDI(tk) and pos > prev_pos + M.EPS_TIME
        and (not cap or pos < cap) then
        cap = pos
      end
    end
    if cap and cap > last + M.EPS_TIME and need_end > cap then need_end = cap end
    reaper.MIDI_SetItemExtents(
      prev,
      reaper.TimeMap2_timeToQN(0, prev_pos),
      reaper.TimeMap2_timeToQN(0, need_end)
    )
  end
  return reaper.GetActiveTake(prev)
end

function M.CleanText(s)
  s = s:gsub("[\t\r\n]+", " ")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.GetTimeContext()
  local s, e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if e - s > M.EPS_TIME * 2 then return s, e end
  return reaper.GetCursorPosition(), nil
end

function M.InsertAt(track, t_from, t_to, time, text)
  local take = M.EnsureTake(track, t_from, t_to)
  local ppq = reaper.MIDI_GetPPQPosFromProjTime(take, time)
  reaper.MIDI_InsertTextSysexEvt(take, false, false, ppq, 5, text)
  reaper.MIDI_Sort(take)
end

function M.PlanLine(track, t1, t2)
  local has_sel = t2 ~= nil
  local end_time = has_sel and t2 or t1
  local events = track and M.CollectEvents(track) or {}
  local ctx = {
    t1 = t1,
    t2 = t2,
    has_sel = has_sel,
    end_time = end_time,
    events = events,
    at_start = M.EventsNear(events, t1),
    at_end = M.EventsNear(events, end_time),
    inside = has_sel and M.EventsBetween(events, t1, t2) or {},
    prefill = "",
  }
  for _, ev in ipairs(ctx.at_start) do
    if ev.text ~= M.END_MARK then
      ctx.prefill = ev.text
      break
    end
  end
  return ctx
end

function M.ApplyLine(track, ctx, text, opts)
  opts = opts or {}
  if text == "" and #ctx.at_end > 0 then
    return false, "end_occupied"
  end
  local undo_name = text == "" and "Lyrics: marcador de fin" or "Lyrics: ingresar línea"
  reaper.Undo_BeginBlock()
  if not track then track = M.CreateLyricsTrack() end
  if text == "" then
    M.InsertAt(track, ctx.t1, ctx.end_time, ctx.end_time, M.END_MARK)
  else
    local to_delete = {}
    for _, ev in ipairs(ctx.at_start) do to_delete[#to_delete + 1] = ev end
    if opts.replace_inside then
      for _, ev in ipairs(ctx.inside) do to_delete[#to_delete + 1] = ev end
    end
    if #to_delete > 0 then M.DeleteEvents(to_delete) end
    M.InsertAt(track, ctx.t1, ctx.end_time, ctx.t1, text)
    local keeps_inside = not opts.replace_inside and #ctx.inside > 0
    if ctx.has_sel and #ctx.at_end == 0 and not keeps_inside then
      M.InsertAt(track, ctx.t1, ctx.end_time, ctx.t2, M.END_MARK)
    end
  end
  reaper.UpdateArrange()
  reaper.Undo_EndBlock(undo_name, -1)
  return true, track
end

-- Decide como agregar una linea a partir del ctx de PlanLine y el texto ya
-- limpio. Sin UI. kind: apply | confirm_line | confirm_inside | reject.
function M.DecideAdd(ctx, text)
  if text == M.END_MARK then return { kind = "reject", code = "reserved" } end
  if text == "" then
    if #ctx.at_end > 0 then return { kind = "reject", code = "end_occupied" } end
    return { kind = "apply" }
  end
  local has_line, has_end = false, false
  for _, ev in ipairs(ctx.at_start) do
    if ev.text == M.END_MARK then has_end = true else has_line = true end
  end
  local n = #ctx.inside
  local kind = "apply"
  if n > 0 then kind = "confirm_inside" elseif has_line then kind = "confirm_line" end
  return { kind = kind, n = n, has_line = has_line, replaces_end = has_end }
end

-- 3c: pares y edicion. Las funciones de edicion reciben una clave
-- {time, is_end} y releen el track al ejecutarse (ev.take/ev.idx caducan
-- con cualquier edicion).

-- Deriva el par linea/fin por posicion (no se guarda). En un grupo de
-- eventos a menos de EPS_TIME entre si, los fines cierran la linea anterior
-- y las lineas abren una nueva. Un fin sin linea previa queda sin owner.
function M.PairEvents(events)
  for _, ev in ipairs(events) do
    ev.is_end = (ev.text == M.END_MARK)
    ev.end_idx, ev.owner = nil, nil
  end
  local cur = nil
  local i, n = 1, #events
  while i <= n do
    local j = i
    while j < n and events[j + 1].time - events[j].time <= M.EPS_TIME do j = j + 1 end
    for k = i, j do
      local ev = events[k]
      if ev.is_end and cur and not events[cur].end_idx then
        events[cur].end_idx = k
        ev.owner = cur
      end
    end
    for k = i, j do
      if not events[k].is_end then cur = k end
    end
    i = j + 1
  end
end

-- Indice en list del evento que coincide con key (tolerancia EPS_TIME).
function M.Resolve(list, key)
  local best, best_d = nil, nil
  for i, ev in ipairs(list) do
    if (ev.text == M.END_MARK) == key.is_end then
      local d = math.abs(ev.time - key.time)
      if d <= M.EPS_TIME and (not best_d or d < best_d) then best, best_d = i, d end
    end
  end
  return best
end

local function freshList()
  local track = M.FindLyricsTrack(0)
  if not track then return nil end
  local list = M.CollectEvents(track)
  M.PairEvents(list)
  return list
end

local function deleteList(victims, name)
  reaper.Undo_BeginBlock()
  M.DeleteEvents(victims)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock(name, -1)
end

-- Cambia el texto en el lugar. typeIn=5 explicito: con nil la API ignora el
-- mensaje (verificado en el probe de E0).
function M.SetText(key, text)
  text = M.CleanText(text or '')
  if text == '' then return false, 'empty' end
  if text == M.END_MARK then return false, 'reserved' end
  if key.is_end then return false, 'not_found' end
  local list = freshList()
  if not list then return false, 'no_track' end
  local i = M.Resolve(list, key)
  if not i then return false, 'not_found' end
  local ev = list[i]
  if ev.text ~= text then
    reaper.Undo_BeginBlock()
    reaper.MIDI_SetTextSysexEvt(ev.take, ev.idx, nil, nil, nil, 5, text, nil)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock('Lyrics: editar texto', -1)
  end
  return true, { kind = 'text', time = ev.time }
end

-- Borra una linea junto con su fin (el par se deriva por posicion), en un
-- solo bloque de undo. Dejar el fin suelto lo haria cerrar la linea anterior.
function M.DeleteLine(key)
  if key.is_end then return false, 'not_found' end
  local list = freshList()
  if not list then return false, 'no_track' end
  local i = M.Resolve(list, key)
  if not i then return false, 'not_found' end
  local ev = list[i]
  local victims = { ev }
  local change = { kind = 'delete', which = 'start', old_time = ev.time }
  if ev.end_idx then
    victims[2] = list[ev.end_idx]
    change.end_time = list[ev.end_idx].time
  end
  deleteList(victims, 'Lyrics: borrar linea')
  return true, change
end

-- Borra un fin: key puede ser el propio fin o su linea.
function M.DeleteEnd(key)
  local list = freshList()
  if not list then return false, 'no_track' end
  local i = M.Resolve(list, key)
  if not i then return false, 'not_found' end
  local ev = list[i]
  local end_ev = ev.is_end and ev or (ev.end_idx and list[ev.end_idx])
  if not end_ev then return false, 'no_end' end
  deleteList({ end_ev }, 'Lyrics: borrar fin')
  return true, { kind = 'delete', which = 'end', old_time = end_ev.time }
end

-- Separacion minima entre eventos vecinos: mayor que EPS_TIME, para que dos
-- eventos nunca cuenten como "misma posicion" (EventsNear).
M.MIN_SEP = M.EPS_TIME * 2

-- Mueve el inicio de una linea (opts.with_end: junto con su fin) o un fin.
-- Un evento nunca cruza ni pisa a un vecino: no hay reordenamiento ni
-- colisiones. opts.clamp: se detiene en el tope en vez de rechazar.
-- Mover = borrar + insertar por la misma ruta que los taps (EnsureTake).
function M.MoveEvent(key, new_time, opts)
  opts = opts or {}
  local list = freshList()
  if not list then return false, 'no_track' end
  local i = M.Resolve(list, key)
  if not i then return false, 'not_found' end
  local ev = list[i]
  local end_ev = (not ev.is_end and opts.with_end and ev.end_idx) and list[ev.end_idx] or nil
  local prev = list[i - 1]
  local nxt
  if end_ev then nxt = list[ev.end_idx + 1] else nxt = list[i + 1] end
  local lo = prev and (prev.time + M.MIN_SEP) or 0
  local hi = nxt and (nxt.time - M.MIN_SEP) or math.huge
  if end_ev then hi = hi - (end_ev.time - ev.time) end
  if lo > hi then return false, 'blocked' end

  local dir = new_time - ev.time
  local t, clamped = new_time, false
  if t < lo or t > hi then
    if not opts.clamp then return false, 'out_of_range' end
    t = math.min(math.max(t, lo), hi)
    clamped = true
  end
  if (t - ev.time) * dir <= 0 then
    return false, clamped and 'at_limit' or 'same'
  end

  local d = t - ev.time
  local victims = { ev }
  if end_ev then victims[2] = end_ev end
  local track = M.FindLyricsTrack(0)
  reaper.Undo_BeginBlock()
  M.DeleteEvents(victims)
  if end_ev then
    local t_end = end_ev.time + d
    M.InsertAt(track, t, t_end, t, ev.text)
    M.InsertAt(track, t, t_end, t_end, M.END_MARK)
  else
    M.InsertAt(track, t, t, t, ev.text)
  end
  reaper.UpdateArrange()
  reaper.Undo_EndBlock(ev.is_end and 'Lyrics: mover fin' or 'Lyrics: mover linea', -1)
  return true, {
    kind = 'move', which = ev.is_end and 'end' or 'start',
    old_time = ev.time, new_time = t,
    end_old = end_ev and end_ev.time or nil,
    end_new = end_ev and (end_ev.time + d) or nil,
    clamped = clamped,
  }
end

-- Agrega el fin de una linea que no lo tiene, en el tiempo t (rango estricto).
function M.AddEnd(key, t)
  if key.is_end then return false, 'not_found' end
  local list = freshList()
  if not list then return false, 'no_track' end
  local i = M.Resolve(list, key)
  if not i then return false, 'not_found' end
  local ev = list[i]
  if ev.end_idx then return false, 'has_end' end
  local nxt = list[i + 1]
  local hi = nxt and (nxt.time - M.MIN_SEP) or math.huge
  if t < ev.time + M.MIN_SEP or t > hi then return false, 'out_of_range' end
  reaper.Undo_BeginBlock()
  M.InsertAt(M.FindLyricsTrack(0), ev.time, t, t, M.END_MARK)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock('Lyrics: agregar fin', -1)
  return true, { kind = 'endadd', line_time = ev.time, new_time = t }
end

return M