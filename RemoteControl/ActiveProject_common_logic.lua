local M = {}

function M.get_active_project_name()
  local name = reaper.GetProjectName(0, "")
  if name == "" then name = "(sin guardar)" end
  return name
end

function M.write_active_project_name()
  local name = M.get_active_project_name()
  reaper.SetExtState("NikRemote", "active_project_name", name, false)
  return name
end

return M