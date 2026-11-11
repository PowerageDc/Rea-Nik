local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Pack = dofile(script_dir .. "../ProjectPack/ProjectPack_common_logic.lua")

local function msg(s) reaper.ShowConsoleMsg(s .. "\n") end

reaper.ClearConsole()
local dest = Pack.resolve_dest()
local problems = Pack.preflight(dest)
if #problems > 0 then
  for _, p in ipairs(problems) do msg("PROBLEMA: " .. p) end
  return
end

local active = reaper.EnumProjects(-1)
local items = Pack.build_plan(dest)
local chosen = {}
for _, it in ipairs(items) do
  if it.proj == active then chosen[1] = it end
end
if #chosen == 0 then
  msg("La pestaña activa no está guardada.")
  return
end

msg("Empaquetando " .. chosen[1].name .. " en " .. dest)
local ok, err = Pack.run_async(chosen, dest,
  function(e) msg(Pack.describe(e)) end,
  function(summary)
    if summary.error then msg("ERROR: " .. summary.error) end
    msg("Terminado.")
  end)
if not ok then msg("No se pudo lanzar: " .. tostring(err)) end