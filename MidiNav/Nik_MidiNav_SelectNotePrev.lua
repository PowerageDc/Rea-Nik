local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
dofile(script_dir .. "MidiNavSelect_common_logic.lua").run("prev")