-- Nik_Tests_CursorPositionProbe.lua
-- Test puntual: valida TimeMap2_timeToQN + TimeMap_QNToMeasures + TimeMap_GetMeasureInfo
-- contra la posicion actual del cursor de edicion. Imprime TODOS los retornos crudos.
-- Uso: posicionar el cursor de edicion en un compas conocido (doble click en la barra
-- de transporte, tipear compas.beat.centesimas) y correr esta accion.

local proj = 0

reaper.ClearConsole()

local cursor_time = reaper.GetCursorPosition()
reaper.ShowConsoleMsg(string.format("cursor_time (segundos) = %.6f\n", cursor_time))

-- 1) time -> QN absoluto
local qn = reaper.TimeMap2_timeToQN(proj, cursor_time)
reaper.ShowConsoleMsg(string.format("TimeMap2_timeToQN -> qn = %.6f\n", qn))

-- 2) QN -> compas (imprime TODOS los retornos, tipo y valor, sin asumir cuales importan)
reaper.ShowConsoleMsg("\n-- TimeMap_QNToMeasures(proj, qn) --\n")
local r1, r2, r3, r4, r5 = reaper.TimeMap_QNToMeasures(proj, qn)
local vals = {r1, r2, r3, r4, r5}
for i, v in ipairs(vals) do
  reaper.ShowConsoleMsg(string.format("  retorno %d: tipo=%s valor=%s\n", i, type(v), tostring(v)))
end

-- Asumiendo que el primer retorno es el numero de compas (a confirmar con la salida de arriba)
local measure_guess = r1
reaper.ShowConsoleMsg(string.format("\n(asumiendo measure_guess = retorno 1 = %s)\n", tostring(measure_guess)))

-- 3) compas -> qn_start / qn_end / timesig (imprime TODOS los retornos)
reaper.ShowConsoleMsg("\n-- TimeMap_GetMeasureInfo(proj, measure_guess) --\n")
local m1, m2, m3, m4, m5, m6 = reaper.TimeMap_GetMeasureInfo(proj, measure_guess)
local mvals = {m1, m2, m3, m4, m5, m6}
for i, v in ipairs(mvals) do
  reaper.ShowConsoleMsg(string.format("  retorno %d: tipo=%s valor=%s\n", i, type(v), tostring(v)))
end

-- 4) Si el retorno 2 de GetMeasureInfo parece ser qn_start, calculamos el offset
reaper.ShowConsoleMsg("\n-- Calculo tentativo de qn_offset --\n")
if type(m2) == "number" then
  local qn_offset_guess = qn - m2
  reaper.ShowConsoleMsg(string.format("qn - retorno2(GetMeasureInfo) = %.6f\n", qn_offset_guess))
else
  reaper.ShowConsoleMsg("retorno 2 no es number, no se puede calcular offset con esta hipotesis\n")
end

reaper.ShowConsoleMsg("\n-- FIN DEL TEST --\n")
reaper.ShowConsoleMsg("Comparar manualmente: compas esperado (segun donde pusiste el cursor) vs measure_guess.\n")
reaper.ShowConsoleMsg("Comparar: beat esperado (tok del campo de posicion) vs qn_offset_guess convertido a beats.\n")