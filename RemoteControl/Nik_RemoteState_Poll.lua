-- @description Nik RemoteState Poll — lectura consolidada de estado para control remoto web
-- @version 1.1
-- @author Nik
-- @provides
--   ActiveProject_common_logic.lua
--   MarkerBars_common_logic.lua
--   ProjectTabs_common_logic.lua
--   ../_Shared/ReaPitchBus_common_logic.lua
--   ../_Shared/StemBus_common_logic.lua
-- Nik_RemoteState_Poll.lua
-- Lee todo el estado que necesita el control remoto (proyecto activo,
-- playrate/preserve pitch, semitonos/enabled de ReaPitch) y lo escribe a
-- ExtState en una sola corrida -- un solo Command ID, sea invocado desde
-- el poll de fondo o puntual (tab, apertura de modal, commit de slider).
--
-- Escalar a futuro = agregar una sección nueva acá adentro, sin tocar el
-- HTML del remoto ni sumar otro _RS a la cola (evita el parpadeo que
-- aparece al empaquetar varios scripts en el mismo tick -- ver
-- DEBUG_CONTEXTO_undo_remoto.md).

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local ActiveProject = dofile(script_dir .. "ActiveProject_common_logic.lua")
local ReaPitchBus   = dofile(script_dir .. "../_Shared/ReaPitchBus_common_logic.lua")
local MarkerBars    = dofile(script_dir .. "MarkerBars_common_logic.lua")

local PRESERVEPITCH_CMD = 40671

-- 1) Proyecto activo ---------------------------------------------------
ActiveProject.write_active_project_name()

-- 2) Playrate + preserve pitch ------------------------------------------
local playrate = reaper.Master_GetPlayRate(0)
local pct = math.floor((playrate * 100) + 0.5)
reaper.SetExtState("NikRemote", "playrate", tostring(pct), false)

local ppState = reaper.GetToggleCommandStateEx(0, PRESERVEPITCH_CMD)
reaper.SetExtState("NikRemote", "preservepitch", (ppState == 1) and "on" or "off", false)

-- 3) ReaPitch: semitonos + enabled ---------------------------------------
ReaPitchBus.write_aggregated_state()

-- 4) Cantidad de compases entre cada marker y el siguiente ----------------
MarkerBars.write_aggregated_state()