-- StemBus_common_logic.lua
-- Lógica genérica de discovery del Stem Bus y sus tracks hijos.
-- Dominio: ubicar el folder track "Stem Bus" (o alias) y enumerar sus hijos.
-- Reusable por cualquier feature que necesite este discovery (ReaPitch,
-- Snapshots, batch render, etc.) -- no depende de nada específico de ReaPitch.

local M = {}

M.BUS_ALIASES = {
  ["stem bus"] = true,
  ["stems bus"] = true,
}
-- Para agregar un alias nuevo (ej. de un template viejo), sumar una línea:
-- ["nombre en minúsculas"] = true,

function M.find_bus_track()
  local n = reaper.CountTracks(0)
  for i = 0, n - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(tr)
    if M.BUS_ALIASES[name:lower()] then
      return tr
    end
  end
  return nil
end

function M.get_folder_children(parent_track)
  local children = {}
  local n = reaper.CountTracks(0)
  local parent_idx = -1
  for i = 0, n - 1 do
    if reaper.GetTrack(0, i) == parent_track then
      parent_idx = i
      break
    end
  end
  if parent_idx == -1 then return children end

  local depth = 1
  for i = parent_idx + 1, n - 1 do
    local tr = reaper.GetTrack(0, i)
    table.insert(children, tr)
    local fd = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    depth = depth + fd
    if depth <= 0 then break end
  end
  return children
end

return M