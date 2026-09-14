-- Nik_ImGui_Template.lua
-- Plantilla base para tests nuevos de ImGui. Duplicar este archivo, renombrar
-- a Nik_ImGui_<NombreDelTest>.lua y registrar la copia en el Action List
-- (Load ReaScript...) -- no hace falta re-registrar el original.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Harness = dofile(script_dir .. "Harness_common_logic.lua")

Harness.Run({
  title = 'Nombre de la ventana',
  body = function(ImGui, ctx)
    -- Codigo a probar

  end,
})
