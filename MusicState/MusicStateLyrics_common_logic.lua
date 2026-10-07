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
    prev = reaper.CreateNewMIDIItemInProj(track, 0, need_end, false)
  else
    local len = reaper.GetMediaItemInfo_Value(prev, "D_LENGTH")
    if prev_pos + len < last + M.EPS_TIME then
      reaper.MIDI_SetItemExtents(
        prev,
        reaper.TimeMap2_timeToQN(0, prev_pos),
        reaper.TimeMap2_timeToQN(0, need_end)
      )
    end
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
    if ctx.has_sel and #ctx.at_end == 0 then
      M.InsertAt(track, ctx.t1, ctx.end_time, ctx.t2, M.END_MARK)
    end
  end
  reaper.UpdateArrange()
  reaper.Undo_EndBlock(undo_name, -1)
  return true, track
end

return M