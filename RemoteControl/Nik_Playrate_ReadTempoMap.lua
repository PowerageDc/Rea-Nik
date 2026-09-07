-- Nik_Playrate_ReadTempoMap.lua
-- Reemplaza a Nik_Playrate_ReadBaseTempo.lua: en vez de un solo BPM de
-- referencia, publica el mapa de tempo completo del proyecto (posicion en
-- segundos + bpm de cada tempo/time-sig marker), para que el remoto pueda
-- calcular el BPM equivalente vigente en cada punto de la cancion -- no solo
-- en el primero -- en proyectos con mapa de tempo variable (intros atipicas
-- grabadas sin metronomo). Ver playrate.js.
--
-- Formato del ExtState (NikRemote/tempo_map): "pos1:bpm1,pos2:bpm2,..."
-- ordenado por posicion ascendente. Cambios de compas sin cambio de bpm
-- generan de todos modos un marker (mismo bpm repetido) -- no afecta el
-- lookup del lado del cliente, que solo usa bpm.
--
-- Sin ningun tempo marker: fallback a un unico punto en pos=0 con
-- Master_GetTempo() (estable en ese caso, igual que en la version anterior).
-- Funciona igual sobre proyectos sin guardar (proj=0 = proyecto activo,
-- sin depender de si esta guardado).
--
-- Disparado on-demand (boot / abrir popup de Playrate / cambio de
-- proyecto), no vive en el poll de fondo.
--
-- Ademas del tempo map, publica el mapa de time signature del proyecto
-- (NikRemote/timesig_map), reusando el mismo loop de markers para evitar
-- iterar dos veces. Formato: "measure1:num1:den1,measure2:num2:den2,..."
-- measure es 1-indexed (measurepos de la API es 0-indexed, se suma +1 aca).
-- Solo se agrega una entrada cuando el marker declara cambio real de
-- compas -- la API devuelve tnum=-1/tden=-1 en markers que son puramente
-- de tempo, sin tocar el time signature vigente (confirmado con test,
-- Nik_Tests_ExtStateProbe / Tests-Debug).

local proj = 0
local n = reaper.CountTempoTimeSigMarkers(proj)
local parts = {}
local timesig_parts = {}

if n > 0 then
    for i = 0, n - 1 do
        local retval, timepos, measurepos, beatpos, bpm, tnum, tden =
            reaper.GetTempoTimeSigMarker(proj, i)
        if retval then
            parts[#parts + 1] = string.format("%.6f:%.4f", timepos, bpm)
            if tnum ~= -1 then
                timesig_parts[#timesig_parts + 1] =
                    string.format("%d:%d:%d", measurepos + 1, tnum, tden)
            end
        end
    end
end

if #parts == 0 then
    parts[1] = string.format("%.6f:%.4f", 0.0, reaper.Master_GetTempo())
end

if #timesig_parts == 0 then
    local ok, num, den = reaper.GetProjectTimeSignature2(proj)
    if ok then
        timesig_parts[1] = string.format("%d:%d:%d", 1, num, den)
    end
end

reaper.SetExtState("NikRemote", "tempo_map", table.concat(parts, ","), false)
reaper.SetExtState("NikRemote", "timesig_map", table.concat(timesig_parts, ","), false)
