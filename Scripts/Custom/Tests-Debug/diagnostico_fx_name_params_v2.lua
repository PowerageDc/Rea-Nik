local track = reaper.GetSelectedTrack(0, 0)
if not track then reaper.ShowConsoleMsg("No hay track seleccionado\n") return end
local fx = 0
local retval, minval, maxval = reaper.TrackFX_GetParamEx(track, fx, 5)
reaper.ShowConsoleMsg("retval: " .. retval .. "\n")
reaper.ShowConsoleMsg("minval: " .. minval .. "\n")
reaper.ShowConsoleMsg("maxval: " .. maxval .. "\n")

local recalculated = minval + retval * (maxval - minval)
reaper.ShowConsoleMsg("semitono recalculado: " .. recalculated .. "\n")