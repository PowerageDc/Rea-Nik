-- Nik_Playrate_ReadBaseTempo.lua
-- Lee el tempo de referencia de la cancion: bpm del primer marker de tempo
-- (GetTempoTimeSigMarker, no Master_GetTempo -- este ultimo depende de la
-- posicion del cursor de edicion, confirmado empiricamente) o, si no hay
-- ningun marker de tempo, Master_GetTempo() (estable en ese caso, ya que
-- sin markers no hay "marker a la izquierda del cursor" que lo altere).
-- Escribe NikRemote/base_tempo. Disparado on-demand al abrir el popup de
-- Playrate -- no vive en Nik_RemoteState_Poll (ver diseño en playrate.js).

local proj = 0
local bpm

if reaper.CountTempoTimeSigMarkers(proj) > 0 then
    local retval, timepos, measurepos, beatpos, markerbpm = reaper.GetTempoTimeSigMarker(proj, 0)
    bpm = markerbpm
else
    bpm = reaper.Master_GetTempo()
end

reaper.SetExtState("NikRemote", "base_tempo", tostring(bpm), false)