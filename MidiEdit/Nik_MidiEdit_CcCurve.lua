local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "MidiEdit_config.lua")
local CcCurve = dofile(script_dir .. "MidiEditCcCurve_common_logic.lua")

CcCurve.run(Config)