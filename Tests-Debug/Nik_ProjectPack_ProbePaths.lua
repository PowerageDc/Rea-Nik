local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Paths = dofile(script_dir .. "../_Shared/ProjectPaths_common_logic.lua")
local Config = dofile(script_dir .. "../ProjectFolder/ProjectFolder_config.lua")

reaper.ClearConsole()
local i = 0
while true do
  local proj = reaper.EnumProjects(i)
  if not proj then break end
  i = i + 1
  local dir = Paths.project_dir(proj)
  if dir then
    reaper.ShowConsoleMsg(string.format("Pestaña %d: %s\n  media:  %s\n  render: %s\n",
      i, dir, Paths.media_dir(proj, dir), Paths.render_dir(proj, dir, Config.render_default)))
  else
    reaper.ShowConsoleMsg("Pestaña " .. i .. ": sin guardar\n")
  end
end