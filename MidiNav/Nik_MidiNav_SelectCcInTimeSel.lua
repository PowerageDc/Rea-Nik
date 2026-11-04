local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
dofile(script_dir .. "MidiNavCcRange_common_logic.lua").run("time_selection")