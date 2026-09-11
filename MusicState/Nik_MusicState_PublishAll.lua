-- Nik_MusicState_PublishAll.lua
-- (renombrado desde Nik_MusicState_PublishHarmony.lua -- ver
-- IMPL_MusicState.md seccion 10.5/11: paso de publicar solo armonia a
-- publicar las 5 piezas de datos de la feature MusicState en la misma
-- pasada, ya que comparten el mismo trigger -- conexion de UI /
-- cambio de proyecto, seccion 1.)
--
-- One-shot: puentea las 5 piezas de datos de ProjExtState (namespace
-- NSAUDIOMUSIC, escritas por MusicState/Nik_MusicState_Helper.lua) a
-- ExtState global -- ProjExtState no es accesible directo desde el Web
-- Control (confirmado con Nik_Tests_ExtStateProbe.lua, Tests-Debug/).
-- Ya NO genera ni escribe ningun dato de muestra: el Helper es la unica
-- fuente de verdad de las 5 keys desde que implementa las 4 tabs
-- (Tonalidad/Roles/Armonia/Cues) + "Guardar y Publicar" (que ya hace su
-- propio SetProjExtState + Bridge.bridgeKey por key, sin pasar por este
-- script). Este script cubre el caso restante: el bridge global quedo
-- desactualizado (ej. cambio de project tab) sin que el Helper haya
-- vuelto a guardar nada en el medio -- puro refresco de puente, no una
-- fuente de datos.
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

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Bridge = dofile(script_dir .. "../_Shared/MusicStateBridge_common_logic.lua")

local proj = 0
local namespace = Bridge.NAMESPACE

-- JSON en una sola linea a proposito en los 5 casos: el Web Control de
-- REAPER escapa saltos de linea reales a "\n" literal al servir la
-- respuesta (protocolo linea-por-registro), lo cual rompe JSON.parse()
-- del lado del cliente. Confirmado con prueba real -- IMPL seccion 3.

local ok_count, failed = Bridge.bridgeAll(proj)
reaper.ShowConsoleMsg(string.format("Nik_MusicState_PublishAll: %d/%d keys publicadas OK.\n",
    ok_count, #Bridge.KEYS))
for _, key in ipairs(failed) do
    reaper.ShowConsoleMsg("Nik_MusicState_PublishAll: fallo (" .. key .. ").\n")
end