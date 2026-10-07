local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Lyrics = dofile(script_dir .. "MusicStateLyrics_common_logic.lua")

local TITLE = "Lyrics"

local function cleanText(s)
  s = s:gsub("[\t\r\n]+", " ")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function describe(list)
  local parts = {}
  for i = 1, math.min(3, #list) do
    parts[i] = "\"" .. list[i].text .. "\""
  end
  local s = table.concat(parts, ", ")
  if #list > 3 then s = s .. " y " .. (#list - 3) .. " más" end
  return s
end

local function getTimeContext()
  local s, e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if e - s > Lyrics.EPS_TIME * 2 then return s, e, true end
  return reaper.GetCursorPosition(), nil, false
end

local function fmtPos(t)
  return reaper.format_timestr_pos(t, "", 2)
end

local function insertAt(track, t_from, t_to, time, text)
  local take = Lyrics.EnsureTake(track, t_from, t_to)
  local ppq = reaper.MIDI_GetPPQPosFromProjTime(take, time)
  reaper.MIDI_InsertTextSysexEvt(take, false, false, ppq, 5, text)
  reaper.MIDI_Sort(take)
end

local function main()
  local track = Lyrics.FindLyricsTrack(0)
  local create = false
  if not track then
    local ans = reaper.MB(
      "No se encontró el track de Lyrics.\n¿Crear \"" .. Lyrics.DEFAULT_TRACK_NAME .. "\"?",
      TITLE, 4)
    if ans ~= 6 then return end
    create = true
  end

  local t1, t2, has_sel = getTimeContext()
  local events = track and Lyrics.CollectEvents(track) or {}
  local end_time = has_sel and t2 or t1
  local at_start = Lyrics.EventsNear(events, t1)
  local at_end = Lyrics.EventsNear(events, end_time)

  local prefill = ""
  for _, ev in ipairs(at_start) do
    if ev.text ~= Lyrics.END_MARK then prefill = ev.text break end
  end

  local title = TITLE .. "  " .. fmtPos(t1)
  if has_sel then title = title .. " → " .. fmtPos(t2) end
  local ok, csv = reaper.GetUserInputs(
    title, 1, "extrawidth=350,separator=\n,Texto (vacío = solo fin)", prefill)
  if not ok then return end
  local text = cleanText(csv)

  local range_to = has_sel and t2 or t1

  if text == "" then
    if #at_end > 0 then
      reaper.MB("Ya hay un evento en esa posición; no se insertó el marcador de fin.", TITLE, 0)
      return
    end
    reaper.Undo_BeginBlock()
    if create then track = Lyrics.CreateLyricsTrack() end
    insertAt(track, t1, range_to, end_time, Lyrics.END_MARK)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Lyrics: marcador de fin", -1)
    return
  end

  local to_delete = {}
  for _, ev in ipairs(at_start) do to_delete[#to_delete + 1] = ev end

  if has_sel then
    local inside = Lyrics.EventsBetween(events, t1, t2)
    if #inside > 0 then
      local ans = reaper.MB(
        "Hay " .. #inside .. " evento(s) dentro de la selección: " .. describe(inside) ..
        ".\n\nSí = reemplazarlos\nNo = conservarlos e insertar igual\nCancelar = no hacer nada",
        TITLE, 3)
      if ans == 2 then return end
      if ans == 6 then
        for _, ev in ipairs(inside) do to_delete[#to_delete + 1] = ev end
      end
    end
  end

  reaper.Undo_BeginBlock()
  if create then track = Lyrics.CreateLyricsTrack() end
  if #to_delete > 0 then Lyrics.DeleteEvents(to_delete) end
  insertAt(track, t1, range_to, t1, text)
  if has_sel and #at_end == 0 then
    insertAt(track, t1, range_to, t2, Lyrics.END_MARK)
  end
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Lyrics: ingresar línea", -1)
end

main()