local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
dofile(script_dir .. "MidiNavGap_common_logic.lua").run("prev")