-- Nik_MusicState_PublishAll.lua
-- (renombrado desde Nik_MusicState_PublishHarmony.lua -- ver
-- IMPL_MusicState.md seccion 10.5/11: paso de publicar solo armonia a
-- publicar las 4 piezas de datos de la feature MusicState en la misma
-- pasada, ya que comparten el mismo trigger -- conexion de UI /
-- cambio de proyecto, seccion 1.)
--
-- One-shot: simula los helpers de carga (aun no implementados, pendiente
-- para sesion aparte) escribiendo datos de prueba en ProjExtState, y
-- luego los puentea a ExtState global para que el Web Control pueda
-- leerlos via GET/EXTSTATE -- ProjExtState no es accesible directo desde
-- ahi (confirmado con Nik_Tests_ExtStateProbe.lua, Tests-Debug/).
--
-- Disparado on-demand (conexion de UI de instrumentista / cambio de
-- proyecto), no vive en el poll de fondo.
--
-- Namespace ProjExtState: NSAUDIOMUSIC. Puente a ExtState global:
-- namespace NikMusicState, una key por dato:
--   harmony_data    -- spec seccion 6-8, IMPL seccion 4
--   project_key     -- IMPL seccion 10.2
--   project_roles   -- IMPL seccion 11.1
--   cues_data       -- IMPL seccion 11.2
--
-- TODO: reemplazar los 4 sample_* por lectura real desde los helpers de
-- carga cuando existan (armonia: IMPL seccion 8.3; roles/cues: sesion
-- aparte, aun no planificada).

local proj = 0
local namespace = "NSAUDIOMUSIC"

-- JSON en una sola linea a proposito en los 4 casos: el Web Control de
-- REAPER escapa saltos de linea reales a "\n" literal al servir la
-- respuesta (protocolo linea-por-registro), lo cual rompe JSON.parse()
-- del lado del cliente. Confirmado con prueba real -- IMPL seccion 3.

local sample_harmony = '{"12":[{"qn_offset":0.0,"chord":"Cmaj7"},{"qn_offset":2.5,"chord":"Dm7"}],"13":[{"qn_offset":0.0,"chord":"G7"},{"qn_offset":3.75,"chord":"Cmaj7"}]}'
local sample_project_key = '{"tonic":"G","mode":"major"}'
local sample_project_roles = '["coordinador","cantantes","guitarristas","bajistas","bateria"]'
local sample_cues = '{"12":[{"qn_offset":0.0,"roles":["cantantes"],"text":"respirar","duration_qn":2.0}]}'

local function publish(key, sample_value)
    reaper.SetProjExtState(proj, namespace, key, sample_value)

    local retval, value_from_proj = reaper.GetProjExtState(proj, namespace, key)

    if retval > 0 and value_from_proj ~= "" then
        reaper.SetExtState("NikMusicState", key, value_from_proj, false)
        reaper.ShowConsoleMsg("Nik_MusicState_PublishAll: " .. key .. " publicado OK.\n")
        return true
    else
        reaper.ShowConsoleMsg("Nik_MusicState_PublishAll: no se pudo leer ProjExtState (" .. key .. ").\n")
        return false
    end
end

publish("harmony_data", sample_harmony)
publish("project_key", sample_project_key)
publish("project_roles", sample_project_roles)
publish("cues_data", sample_cues)