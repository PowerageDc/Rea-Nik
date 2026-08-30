local track = reaper.GetSelectedTrack(0, 0)
if not track then reaper.ShowConsoleMsg("No hay track seleccionado\n") return end
local fxCount = reaper.TrackFX_GetCount(track)
for fx = 0, fxCount - 1 do
  local _, fxName = reaper.TrackFX_GetFXName(track, fx, "")
  reaper.ShowConsoleMsg("FX " .. fx .. ": " .. fxName .. "\n")
  local paramCount = reaper.TrackFX_GetNumParams(track, fx)
  for p = 0, paramCount - 1 do
    local _, paramName = reaper.TrackFX_GetParamName(track, fx, p, "")
    local val = reaper.TrackFX_GetParam(track, fx, p)
    reaper.ShowConsoleMsg("  param " .. p .. ": " .. paramName .. " = " .. val .. "\n")
  end
end