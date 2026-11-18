local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "MidiGen_config.lua")
local Gliss = dofile(script_dir .. "MidiGenGliss_common_logic.lua")

Gliss.run(Config)
