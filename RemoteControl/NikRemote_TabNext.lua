local projects = {}
local i = 0
while true do
  local proj = reaper.EnumProjects(i, "")
  if not proj then break end
  projects[#projects+1] = proj
  i = i + 1
end

local current = reaper.EnumProjects(-1, "")
for idx, proj in ipairs(projects) do
  if proj == current then
    local next_idx = idx + 1
    if next_idx > #projects then next_idx = 1 end
    reaper.SelectProjectInstance(projects[next_idx])
    break
  end
end

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local ActiveProject = dofile(script_dir .. "ActiveProject_common_logic.lua")
ActiveProject.write_active_project_name()
