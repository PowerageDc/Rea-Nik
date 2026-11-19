local M = {}

M.NAME_BEAT = "TAP"
M.NAME_DOWNBEAT = "TAP1"

local COLOR_BEAT = reaper.ColorToNative(120, 170, 255) | 0x1000000
local COLOR_DOWNBEAT = reaper.ColorToNative(255, 140, 40) | 0x1000000

-- Durante la reproducción usa la posición ya compensada por latencia de salida;
-- detenido, usa el cursor de edición.
function M.tap_position()
  if reaper.GetPlayState() & 1 == 1 then
    return reaper.GetPlayPosition()
  end
  return reaper.GetCursorPosition()
end

-- Un downbeat puede llevar el compás después del nombre ("TAP1 6/8").
function M.is_tap_name(name)
  return name == M.NAME_BEAT
    or name == M.NAME_DOWNBEAT
    or name:sub(1, #M.NAME_DOWNBEAT + 1) == M.NAME_DOWNBEAT .. " "
end

function M.add_tap(is_downbeat)
  local name = is_downbeat and M.NAME_DOWNBEAT or M.NAME_BEAT
  local color = is_downbeat and COLOR_DOWNBEAT or COLOR_BEAT
  reaper.Undo_BeginBlock2(0)
  reaper.AddProjectMarker2(0, false, M.tap_position(), 0, name, -1, color)
  reaper.Undo_EndBlock2(0, "Tempo tap: " .. name, -1)
end

function M.clear_taps()
  local ids = {}
  local i = 0
  while true do
    local ret, is_region, _, _, name, idx = reaper.EnumProjectMarkers3(0, i)
    if ret == 0 then break end
    if not is_region and M.is_tap_name(name) then
      ids[#ids + 1] = idx
    end
    i = i + 1
  end
  if #ids == 0 then return 0 end
  reaper.Undo_BeginBlock2(0)
  for _, idx in ipairs(ids) do
    reaper.DeleteProjectMarker(0, idx, false)
  end
  reaper.Undo_EndBlock2(0, "Tempo tap: borrar taps", -1)
  return #ids
end

-- Desplaza todos los taps por delta segundos. Devuelve cuántos movió.
function M.shift_taps(delta)
  local found = {}
  local i = 0
  while true do
    local ret, is_region, pos, _, name, idx, color = reaper.EnumProjectMarkers3(0, i)
    if ret == 0 then break end
    if not is_region and M.is_tap_name(name) then
      found[#found + 1] = { idx = idx, pos = pos, name = name, color = color }
    end
    i = i + 1
  end
  for _, t in ipairs(found) do
    reaper.SetProjectMarker3(0, t.idx, false, t.pos + delta, 0, t.name, t.color)
  end
  return #found
end

return M