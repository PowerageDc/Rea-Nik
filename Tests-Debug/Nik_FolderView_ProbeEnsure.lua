local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local FV = dofile(script_dir .. "../_Shared/FolderView_common_logic.lua")
local ok, msg = FV.ensure_folder("D:\\Prueba Canción\\Media\\Samples", "Documents")
reaper.ShowConsoleMsg(tostring(ok) .. " " .. tostring(msg) .. "\n")