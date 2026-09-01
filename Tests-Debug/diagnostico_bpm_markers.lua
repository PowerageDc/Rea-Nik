-- diagnostico_bpm_markers.lua
-- Lista todos los tempo/timesig markers del proyecto con su BPM crudo (API)
local count = reaper.CountTempoTimeSigMarkers(0)
reaper.ShowConsoleMsg("--- Tempo/TimeSig Markers ---\n")
for i = 0, count - 1 do
  local retval, timepos, measurepos, beatpos, bpm, num, denom, lineartempo =
    reaper.GetTempoTimeSigMarker(0, i)
  reaper.ShowConsoleMsg(string.format(
    "idx=%d  timepos=%.4f  bpm=%.6f  timesig=%d/%d\n",
    i, timepos, bpm, num, denom
  ))
end