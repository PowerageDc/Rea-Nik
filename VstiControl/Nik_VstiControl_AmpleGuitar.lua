local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Ui = dofile(script_dir .. "VstiControlUi_common_logic.lua")
local cfg = dofile(script_dir .. "VstiControl_AmpleGuitar_config.lua")

Ui.run(cfg)