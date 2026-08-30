-- MarkerBars_common_logic.lua
-- Cantidad de compases entre cada marker y el siguiente. Usa TimeMap2_timeToQN +
-- TimeMap_QNToMeasures (no division simple de segundos) para que el numero sea
-- correcto aunque el proyecto tenga tempo map con varios tempo markers y/o
-- cambios de time signature en el medio -- ver 01_CONVENCIONES.md / notas de
-- remote_control.md sobre este calculo.

local M = {}

-- Devuelve "id1:compases1;id2:compases2;..." -- un par por cada marker que
-- tiene un siguiente marker (el ultimo marker del proyecto no genera par,
-- no hay nada contra que medirlo).
function M.read_aggregated_state()
  local proj = 0
  local total = reaper.CountProjectMarkers(proj)
  local markers = {}

  for i = 0, total - 1 do
    local retval, isrgn, pos, _, _, markrgnindexnumber = reaper.EnumProjectMarkers2(proj, i)
    if retval > 0 and not isrgn then
      table.insert(markers, { id = markrgnindexnumber, pos = pos })
      end
    end

  table.sort(markers, function(a, b) return a.pos < b.pos end)

  local parts = {}
  for i = 1, #markers - 1 do
    -- +1e-6 QN: protege contra markers que caen una fraccion de float antes del
    -- downbeat real (precision), sin afectar posiciones genuinamente fuera de grid.
    local qnStart = reaper.TimeMap2_timeToQN(proj, markers[i].pos) + 1e-6
    local qnEnd   = reaper.TimeMap2_timeToQN(proj, markers[i + 1].pos) + 1e-6
    local measureStart = reaper.TimeMap_QNToMeasures(proj, qnStart)
    local measureEnd   = reaper.TimeMap_QNToMeasures(proj, qnEnd)
    table.insert(parts, markers[i].id .. ":" .. (measureEnd - measureStart))
    end

  return table.concat(parts, ";")
end

function M.write_aggregated_state()
  local out = M.read_aggregated_state()
  reaper.SetExtState("NikRemote", "marker_bars", out, false)
  return out
end

return M