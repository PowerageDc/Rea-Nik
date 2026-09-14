-- Harness_common_logic.lua
-- Encapsula el boilerplate repetido de cada Nik_ImGui_*.lua de prueba: carga
-- del shim de ReaImGui, creación de contexto, loop de reaper.defer() envuelto
-- en Debug.pcallLoop, y cierre de ventana (open == false corta el loop).
-- Vive en Tests-Debug/ImGui/ junto a Debug_common_logic.lua (mismo dominio:
-- pruebas de ImGui). Si en el futuro otro dominio lo consume, migra a
-- _Shared/ (ver "Patrón de módulos de lógica compartida" en 01_CONVENCIONES.md).

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Debug = dofile(script_dir .. "Debug_common_logic.lua")

local M = {}

--- Carga el shim de ReaImGui. require 'imgui' no funciona sin agregar la
-- carpeta del shim a package.path a mano, así que se usa dofile directo
-- contra la ubicación fija que instala ReaPack. Devuelve nil (+ msgbox) si
-- la extensión no está instalada.
function M.LoadImGui(version)
  if not reaper.ImGui_CreateContext then
    reaper.MB('Falta instalar ReaImGui (ReaPack -> ReaTeam Extensions).', 'Error', 0)
    return nil
  end
  return dofile(reaper.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua')(version)
end

--- Arma y arranca el loop completo de un test.
-- opts:
--   title   (string, requerido)   Título de la ventana.
--   version (string, opcional)    Versión del shim de ReaImGui. Default '0.9.3'.
--   body    (function(ImGui, ctx), requerido)
--           Contenido a dibujar dentro del ImGui.Begin/End. Se llama una vez
--           por frame, ya envuelto en Debug.pcallLoop.
--
-- Uso mínimo desde un Nik_ImGui_<Test>.lua:
--   local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
--   local Harness = dofile(script_dir .. "Harness_common_logic.lua")
--
--   Harness.Run({
--     title = 'Mi Test',
--     body = function(ImGui, ctx)
--       ImGui.Text(ctx, 'Hola')
--     end,
--   })
function M.Run(opts)
  assert(opts and opts.title, "Harness.Run: falta opts.title")
  assert(opts.body, "Harness.Run: falta opts.body")

  local ImGui = M.LoadImGui(opts.version or '0.9.3')
  if not ImGui then return end

  local ctx = ImGui.CreateContext(opts.title)

  local function loop()
    local should_continue = true

    local ok = Debug.pcallLoop(function()
      local visible, open = ImGui.Begin(ctx, opts.title, true)
      if visible then
        opts.body(ImGui, ctx)
        ImGui.End(ctx)
      end
      should_continue = open
    end)

    if ok and should_continue then
      reaper.defer(loop)
    end
  end

  reaper.defer(loop)
end

return M
