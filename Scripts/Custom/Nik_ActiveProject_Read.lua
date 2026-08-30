local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local ActiveProject = dofile(script_dir .. "ActiveProject_common_logic.lua")

ActiveProject.write_active_project_name()