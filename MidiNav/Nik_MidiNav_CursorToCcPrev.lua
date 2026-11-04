local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
dofile(script_dir .. "MidiNavCc_common_logic.lua").run("prev")