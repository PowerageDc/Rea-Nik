-- MusicStateRowInputs_common_logic.lua
-- Trio de posicion (Compas/Beat/Cent.) + boton de cursor, reusado por las
-- tablas de Armonia y Cues en Nik_MusicState_Helper.lua. Separado en piezas
-- chicas a proposito (ver IMPL_MusicState.md seccion 13, sesion "trio de
-- posicion") para poder tocar boton o steppers por separado mas adelante,
-- sin reabrir el resto.

local M = {}

M.DEFAULT_WIDTHS = { measure = 100, beat = 90, hundredths = 100 }

-- Dibuja los 3 InputInt (Compas/Beat/Cent.) en 3 columnas consecutivas de
-- una tabla ya abierta -- llama TableNextColumn() 3 veces, una por campo.
-- Asume que el caller ya hizo TableNextRow()/PushID() antes de invocar
-- esta funcion, y que las 3 columnas siguientes le corresponden a esto.
-- Muta row.measure/row.beat/row.hundredths in-place.
function M.drawPositionInputs(ctx, row, widths)
  widths = widths or M.DEFAULT_WIDTHS

  reaper.ImGui_TableNextColumn(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, widths.measure or M.DEFAULT_WIDTHS.measure)
  local _, measure = reaper.ImGui_InputInt(ctx, '##compas', row.measure, 1, 10)
  row.measure = measure

  reaper.ImGui_TableNextColumn(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, widths.beat or M.DEFAULT_WIDTHS.beat)
  local _, beat = reaper.ImGui_InputInt(ctx, '##beat', row.beat, 1, 4)
  row.beat = beat

  reaper.ImGui_TableNextColumn(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, widths.hundredths or M.DEFAULT_WIDTHS.hundredths)
  local _, hundredths = reaper.ImGui_InputInt(ctx, '##centesimas', row.hundredths, 5, 25)
  row.hundredths = hundredths
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