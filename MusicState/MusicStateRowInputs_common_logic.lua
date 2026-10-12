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

-- Perfil de flechas por campo (musicstate_keys.md 9.4): arriba suma, abajo
-- resta, Shift = paso grande. Un InputInt activo ignora el valor que se le
-- pasa desde afuera: se cambia el ID del widget (row._ver_<campo>) y se pide
-- el foco de nuevo con hold (la fila sigue "activa" para Armonia y no se
-- reordena hasta que se salga del campo).
local ARROW_STEPS = {
  measure    = { small = 1, big = 4 },
  beat       = { small = 1, big = 4 },
  hundredths = { small = 5, big = 25 },
}

local value_profiles = nil  -- se arma una vez; guarda ring y get_max_beats

local function getValueProfiles(ring, get_max_beats)
  if not value_profiles then
    value_profiles = { ring = ring }
    local function bounds(field, row)
      if field == 'measure' then return 1, math.huge end
      if field == 'hundredths' then return 0, 99 end
      local mx = value_profiles.get_max_beats and value_profiles.get_max_beats(row.measure)
      return 1, mx or math.huge
    end
    local function make(field)
      local st = ARROW_STEPS[field]
      local function move(sign)
        return function(row, _, shift)
          local lo, hi = bounds(field, row)
          local v = clamp(row[field] + sign * (shift and st.big or st.small), lo, hi)
          if v == row[field] then return end
          row[field] = v
          row['_ver_' .. field] = (row['_ver_' .. field] or 0) + 1
          value_profiles.ring.ring_request(row, field, true)
        end
      end
      return { on_up = move(1), on_down = move(-1) }
    end
    for field in pairs(ARROW_STEPS) do value_profiles[field] = make(field) end
  end
  value_profiles.get_max_beats = get_max_beats
  return value_profiles
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
-- ring: opcional (la tabla Keys); registra los 3 campos en el anillo de foco
-- de la tab con (fila, 'measure' | 'beat' | 'hundredths'). nil = sin anillo.
function M.drawPositionInputs(ctx, row, widths, get_max_beats, ring, arrow_values)
  widths = widths or M.DEFAULT_WIDTHS
  local active = false
  -- arrow_values: opcional, activa el perfil de flechas (cambian el valor);
  -- requiere ring. Cada tab decide si lo quiere.
  local prof = arrow_values and ring and getValueProfiles(ring, get_max_beats)

  reaper.ImGui_TableNextColumn(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, widths.measure or M.DEFAULT_WIDTHS.measure)
  if ring then ring.ring_focus(ctx, row, 'measure') end
  local ver = row._ver_measure or 0
  local _, measure = reaper.ImGui_InputInt(ctx, '##compas' .. ver, row.measure, 1, 10)
  row.measure = measure
  if ring then ring.ring_item(ctx, row, 'measure', nil, prof and prof.measure) end
  active = active or reaper.ImGui_IsItemActive(ctx)

  reaper.ImGui_TableNextColumn(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, widths.beat or M.DEFAULT_WIDTHS.beat)
  if ring then ring.ring_focus(ctx, row, 'beat') end
  local _, beat = reaper.ImGui_InputInt(ctx, '##beat' .. (row._ver_beat or 0), row.beat, 1, 4)
  local max_beats = get_max_beats and get_max_beats(row.measure)
  row.beat = clamp(beat, 1, max_beats or beat)
  if ring then ring.ring_item(ctx, row, 'beat', nil, prof and prof.beat) end
  active = active or reaper.ImGui_IsItemActive(ctx)

  reaper.ImGui_TableNextColumn(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, widths.hundredths or M.DEFAULT_WIDTHS.hundredths)
  if ring then ring.ring_focus(ctx, row, 'hundredths') end
  local _, hundredths = reaper.ImGui_InputInt(ctx, '##centesimas' .. (row._ver_hundredths or 0), row.hundredths, 5, 25)
  row.hundredths = clamp(hundredths, 0, 99)
  if ring then ring.ring_item(ctx, row, 'hundredths', nil, prof and prof.hundredths) end
  active = active or reaper.ImGui_IsItemActive(ctx)

  if ring and ring.ring_holds(row) then active = true end
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