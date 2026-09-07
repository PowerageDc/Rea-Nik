-- Nik_MusicState_PublishHarmony.lua
-- One-shot: simula el helper de carga de armonia (aun no implementado,
-- pendiente para sesion aparte) escribiendo datos de prueba en
-- ProjExtState, y luego los puentea a ExtState global
-- (NikMusicState/harmony_data) para que el Web Control pueda leerlos via
-- GET/EXTSTATE -- ProjExtState no es accesible directo desde ahi
-- (confirmado con Nik_Tests_ExtStateProbe.lua, Tests-Debug/).
--
-- Disparado on-demand (conexion de UI de instrumentista / cambio de
-- proyecto), no vive en el poll de fondo.
--
-- Formato de harmony_data: JSON, un array de eventos por compas, cada
-- evento con qn_offset (negras desde el downbeat del compas, grilla 0.25)
-- y chord. Ver spec REAPER Musical Metadata & Web Controller, seccion 6-8.
--
-- TODO: reemplazar sample_harmony por lectura real desde el helper de
-- carga de armonia cuando exista.

local proj = 0
local namespace = "NSAUDIOMUSIC"
local key = "harmony_data"

-- Datos de prueba (simulan lo que el helper habria guardado en ProjExtState)
-- JSON en una sola linea a proposito: el Web Control de REAPER escapa
-- saltos de linea reales a "\n" literal al servir la respuesta (protocolo
-- linea-por-registro), lo cual rompe JSON.parse() del lado del cliente.
-- Confirmado con prueba real -- ver notas de sesion MusicState.
local sample_harmony = '{"12":[{"qn_offset":0.0,"chord":"Cmaj7"},{"qn_offset":2.5,"chord":"Dm7"}],"13":[{"qn_offset":0.0,"chord":"G7"},{"qn_offset":3.75,"chord":"Cmaj7"}]}'

reaper.SetProjExtState(proj, namespace, key, sample_harmony)

local retval, harmony_json = reaper.GetProjExtState(proj, namespace, key)

if retval > 0 and harmony_json ~= "" then
    reaper.SetExtState("NikMusicState", "harmony_data", harmony_json, false)
    reaper.ShowConsoleMsg("Nik_MusicState_PublishHarmony: publicado OK.\n")
else
    reaper.ShowConsoleMsg("Nik_MusicState_PublishHarmony: no se pudo leer ProjExtState.\n")
end