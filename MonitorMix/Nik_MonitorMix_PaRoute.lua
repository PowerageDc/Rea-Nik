-- Nik_MonitorMix_PaRoute.lua
-- One-shot: lee NikMonitorMix/pa_cmd, corta o activa el PA de los tracks hoja
-- del filtro de Monitor Mix (B_MAINSEND) y publica NikMonitorMix/pa_state.
-- Sin orden pendiente solo republica el estado. Lógica y formato de las
-- órdenes: MonitorMixPa_common_logic.lua.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local PA = dofile(script_dir .. "MonitorMixPa_common_logic.lua")

PA.run_command()