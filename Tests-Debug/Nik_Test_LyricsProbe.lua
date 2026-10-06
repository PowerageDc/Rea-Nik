local PROJ = 0
local TYPES = {[1]="text",[2]="copyright",[3]="trackname",[4]="instrument",[5]="LYRIC",[6]="marker",[7]="cue"}
local function log(s) reaper.ShowConsoleMsg(s .. "\n") end
local function esc(s) return (s:gsub("\t", "<TAB>"):gsub("\n", "<LF>")) end
local function hex(s) return (s:gsub(".", function(c) return string.format("%02X ", c:byte()) end)) end

reaper.ClearConsole()
local track
for i = 0, reaper.CountTracks(PROJ) - 1 do
  local t = reaper.GetTrack(PROJ, i)
  local _, name = reaper.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
  if name:lower():find("lyrics", 1, true) then
    track = t
    log("Track: " .. name .. " (indice web: " .. (i + 1) .. ")")
    break
  end
end
if not track then log("No hay track con 'Lyrics' en el nombre"); return end

for i = 0, reaper.CountTrackMediaItems(track) - 1 do
  local item = reaper.GetTrackMediaItem(track, i)
  local take = reaper.GetActiveTake(item)
  if take and reaper.TakeIsMIDI(take) then
    local _, notes, _, texts = reaper.MIDI_CountEvts(take)
    log(("Item %d: pos=%.3fs notas=%d textEvts=%d"):format(i, reaper.GetMediaItemInfo_Value(item, "D_POSITION"), notes, texts))
    for k = 0, texts - 1 do
      local _, _, _, ppq, typ, msg = reaper.MIDI_GetTextSysexEvt(take, k, false, false, 0, 0, "")
      local qn = reaper.MIDI_GetProjQNFromPPQPos(take, ppq)
      local m, qs = reaper.TimeMap_QNToMeasures(PROJ, qn)
      local h = msg:find("[\128-\255]") and (" HEX: " .. hex(msg)) or ""
      log(("  [%d] tipo=%s ppq=%.1f qn=%.4f measure_ret=%s off=%.4f | '%s'%s"):format(k, TYPES[typ] or typ, ppq, qn, tostring(m), qn - (qs or 0), esc(msg), h))
    end
  end
end

for flag = 0, 3 do
  local ok, r, buf = pcall(reaper.GetTrackMIDILyrics, track, flag)
  log(("GetTrackMIDILyrics flag=%d ok=%s ret=%s | %s"):format(flag, tostring(ok), tostring(r), esc(tostring(buf))))
end