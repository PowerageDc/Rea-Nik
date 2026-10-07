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

return M