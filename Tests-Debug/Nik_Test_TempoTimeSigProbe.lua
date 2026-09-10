local proj = 0
local n = reaper.CountTempoTimeSigMarkers(proj)

reaper.ClearConsole()
reaper.ShowConsoleMsg(string.format("Total markers: %d\n\n", n))

local limit = math.min(10, n)
for i = 0, limit - 1 do
    local retval, timepos, measurepos, beatpos, bpm, tnum, tden, lineartempo =
        reaper.GetTempoTimeSigMarker(proj, i)

    reaper.ShowConsoleMsg(string.format(
        "i=%d  timepos=%.4f  measurepos=%d  beatpos=%.4f  bpm=%.4f  tnum=%d  tden=%d\n",
        i, timepos, measurepos, beatpos, bpm, tnum, tden
    ))
end