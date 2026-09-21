-- MusicStateRowInputs_common_logic.lua
-- Trio de posicion (Compas/Beat/Cent.) + boton de cursor, reusado por las
-- tablas de Armonia y Cues en Nik_MusicState_Helper.lua. Separado en piezas
-- chicas a proposito (ver IMPL_MusicState.md seccion 13, sesion "trio de
-- posicion") para poder tocar boton o steppers por separado mas adelante,
-- sin reabrir el resto.

local M = {}

M.DEFAULT_WIDTHS = { measure = 100, beat = 90, hundredths = 100 }

-- Lua no trae clamp built-in.
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- Dibuja los 3 InputInt (Compas/Beat/Cent.) en 3 columnas consecutivas de
-- una tabla ya abierta -- llama TableNextColumn() 3 veces, una por campo.
-- Asume que el caller ya hizo TableNextRow()/PushID() antes de invocar
-- esta funcion, y que las 3 columnas siguientes le corresponden a esto.
-- Muta row.measure/row.beat/row.hundredths in-place.
-- Devuelve "active" (algun campo de la fila tiene foco este frame), no
-- "committed" -- IsItemDeactivatedAfterEdit en un InputInt con steppers
-- +/- disparo falsos positivos a mitad de tipeo en pruebas reales (bug:
-- reordenar con la fila todavia enfocada le corre el indice de PushID,
-- pierde el foco). El llamador detecta "termino de editar" por
-- TRANSICION de active entre frames (activo -> no activo), no por este
-- evento puntual -- ver resortAndFocusRow en MusicStateArmonia.
-- get_max_beats: funcion opcional (measure) -> timesig_num del compas dado
-- (ver helpers.getMaxBeats), usada para topear Beat. Se llama con
-- row.measure YA ACTUALIZADO en este mismo frame (el campo Compas se
-- dibuja arriba) -- si measure y beat cambian el mismo frame, valida
-- contra la metrica nueva, no la vieja. nil = sin tope superior (compat
-- con callers que todavia no la pasan, ej. Cues por ahora).
-- Beat: minimo 1 siempre (nunca 0). Hundredths: 0..99 siempre. El clamp
-- corre sobre el valor YA devuelto por InputInt, sin importar si vino de
-- tecleo o de los steppers +/- del propio widget -- ImGui no distingue
-- el origen en el valor de retorno, asi que no hace falta codigo aparte
-- por caso.
function M.drawPositionInputs(ctx, row, widths, get_max_beats)
  widths = widths or M.DEFAULT_WIDTHS
  local active = false

  reaper.ImGui_TableNextColumn(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, widths.measure or M.DEFAULT_WIDTHS.measure)
  local _, measure = reaper.ImGui_InputInt(ctx, '##compas', row.measure, 1, 10)
  row.measure = measure
  active = active or reaper.ImGui_IsItemActive(ctx)

  reaper.ImGui_TableNextColumn(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, widths.beat or M.DEFAULT_WIDTHS.beat)
  local _, beat = reaper.ImGui_InputInt(ctx, '##beat', row.beat, 1, 4)
  local max_beats = get_max_beats and get_max_beats(row.measure)
  row.beat = clamp(beat, 1, max_beats or beat)
  active = active or reaper.ImGui_IsItemActive(ctx)

  reaper.ImGui_TableNextColumn(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, widths.hundredths or M.DEFAULT_WIDTHS.hundredths)
  local _, hundredths = reaper.ImGui_InputInt(ctx, '##centesimas', row.hundredths, 5, 25)
  row.hundredths = clamp(hundredths, 0, 99)
  active = active or reaper.ImGui_IsItemActive(ctx)

  return active
end

-- Solo el boton -- devuelve true si se clickeo este frame. label opcional
-- para poder reemplazarlo por un icono despues sin tocar nada mas.
function M.drawCursorButton(ctx, label)
  return reaper.ImGui_Button(ctx, label or 'Usar cursor')
end

-- Logica pura (sin ImGui): copia measure/beat/hundredths de pos a row.
-- pos: shape de nikMusicStateCaptureCursorPosition (measure, beat,
-- hundredths, ...). Separado del boton por si en el futuro hace falta
-- aplicar el cursor a mas de una fila a la vez (seleccion multiple).
function M.applyCursorToRow(row, pos)
  row.measure = pos.measure
  row.beat = pos.beat
  row.hundredths = pos.hundredths
end

return M