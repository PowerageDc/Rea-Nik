-- NikRemote_ReaPitch_Read.lua
-- Wrapper delgado sobre ReaPitchBus_common_logic.write_aggregated_state().
-- Se mantiene como script standalone por si hace falta dispararlo solo
-- (Action List, footswitch), fuera del poll consolidado del remoto.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local ReaPitchBus = dofile(script_dir .. "ReaPitchBus_common_logic.lua")

ReaPitchBus.write_aggregated_state()