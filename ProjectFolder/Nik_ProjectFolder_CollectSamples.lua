-- Nik_ProjectFolder_CollectSamples.lua
-- Recorre las pestañas abiertas y copia a <carpeta del .rpp>\Media\Samples
-- los archivos que usan los FX con lista de archivos (ReaSamplOmatic5000,
-- ReaVerb, etc.) y que están fuera de la carpeta del proyecto.
-- Solo Windows.

local RELINK = false                    -- true: apunta el FX a la copia

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Samples = dofile(script_dir .. "../_Shared/ProjectSamples_common_logic.lua")

local function msg(s) reaper.ShowConsoleMsg(s .. "\n") end

local function main()
  if not reaper.GetOS():find("Win") then
    reaper.MB("Este script solo funciona en Windows.", "CollectSamples", 0)
    return
  end
  reaper.ClearConsole()
  local i = 0
  while true do
    local proj, projfn = reaper.EnumProjects(i)
    if not proj then break end
    i = i + 1
    if projfn == "" then
      msg("Pestaña " .. i .. ": sin guardar, se omite")
    else
      Samples.collect(proj, projfn, msg, { relink = RELINK })
    end
  end
  msg("Listo.")
end

main()