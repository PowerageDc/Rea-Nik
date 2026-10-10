local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local MM = dofile(script_dir .. "MonitorMix_common_logic.lua")

reaper.ClearConsole()
local res = MM.ensure_sends(MM.load_config())
for _, line in ipairs(res.log) do reaper.ShowConsoleMsg(line .. "\n") end