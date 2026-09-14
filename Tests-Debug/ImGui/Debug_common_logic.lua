-- Debug_common_logic.lua
-- Helpers de logging y captura de errores para scripts de prueba (Tests-Debug/ImGui/).
-- Patrón de módulo: tabla única (M), sin funciones/variables sueltas en global scope
-- (ver "Patrón de módulos de lógica compartida" en 01_CONVENCIONES.md).

local M = {}

-- Flag global de módulo: permite silenciar todos los Msg() sin tocar cada call site.
M.enabled = true

--- Loguea a la consola de REAPER, concatenando args con tab.
-- Uso: Debug.Msg(rv, clipper)
function M.Msg(...)
  if not M.enabled then return end
  local args = {...}
  local n = select("#", ...)
  for i = 1, n do
    args[i] = tostring(args[i])
  end
  reaper.ShowConsoleMsg(table.concat(args, "\t", 1, n) .. "\n")
end

--- Envuelve una función (típicamente el cuerpo del loop de reaper.defer) con pcall
-- y traceback. Si fn tira error, lo imprime completo con stack y devuelve false
-- (para que el caller pueda cortar el defer en vez de reintentar con el mismo error).
-- Uso:
--   local function loop()
--     if not Debug.pcallLoop(function()
--       -- ImGui.Begin/End, etc.
--     end) then return end
--     reaper.defer(loop)
--   end
function M.pcallLoop(fn)
  local ok, err = pcall(fn)
  if not ok then
    reaper.ShowConsoleMsg(debug.traceback(tostring(err)) .. "\n")
    return false
  end
  return true
end

return M
