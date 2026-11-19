local BPM = 120
local CASES = { { 4, 4 }, { 3, 4 }, { 2, 4 }, { 6, 8 }, { 9, 8 }, { 12, 8 }, { 5, 8 }, { 2, 2 } }

local function log(s)
  reaper.ShowConsoleMsg(s .. "\n")
end

reaper.ClearConsole()

if reaper.CountTempoTimeSigMarkers(0) > 0 or reaper.CountMediaItems(0) > 0 then
  reaper.ShowMessageBox("Correr en un proyecto vacío, sin tempo markers ni items.", "Probe", 0)
  return
end

reaper.Undo_BeginBlock2(0)
for i, c in ipairs(CASES) do
  local num, den = c[1], c[2]
  reaper.SetTempoTimeSigMarker(0, i > 1 and 0 or -1, 0, -1, -1, BPM, num, den, false)
  local t = 100
  local beats, measure, cml, _, cdenom = reaper.TimeMap2_timeToBeats(0, t)
  local bar_s = t / (measure + beats / cml)
  log(string.format("%d/%-2d a %d bpm: compás de %.4f s = %.3f negras (cml %s, denom %s)",
    num, den, BPM, bar_s, bar_s * BPM / 60, tostring(cml), tostring(cdenom)))
end
reaper.Undo_EndBlock2(0, "Probe compás y bpm", -1)