local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "MidiGen_config.lua")
local CcCurve = dofile(script_dir .. "MidiGenCcCurve_common_logic.lua")

CcCurve.run(Config)