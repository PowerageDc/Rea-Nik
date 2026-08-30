-- Nik_ProjectTabs_Read.lua
-- Wrapper delgado sobre ProjectTabs_common_logic.write_aggregated_state().
-- Disparado por el remoto (PROJECTTABS_CMD_READ) solo al abrir el popup de
-- selección de proyecto — no forma parte del poll de fondo (NIK_SLOW_POLL).
-- Registrar en el Action List y completar PROJECTTABS_CMD_READ en el HTML.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local ProjectTabs = dofile(script_dir .. "ProjectTabs_common_logic.lua")

ProjectTabs.write_aggregated_state()
