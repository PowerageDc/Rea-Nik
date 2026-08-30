-- ReaPitchBus_common_logic.lua
-- Lógica específica de ReaPitch sobre los hijos del Stem Bus: encontrar la
-- instancia de FX y aplicar/leer el parámetro de semitonos.
-- Depende de StemBus_common_logic.lua para el discovery del Bus (genérico).

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local StemBus = dofile(script_dir .. "StemBus_common_logic.lua")

local M = {}

M.SEMITONE_PARAM = 5 -- "1: Shift (semitones)" en ReaPitch
M.SEMITONE_RANGE = 18 -- rango real confirmado empíricamente: ±18 semitonos -> 0.0-1.0

-- Re-exponer lo del módulo genérico para que los consumidores de
-- ReaPitchBus_common_logic no necesiten hacer dofile de StemBus aparte.
M.find_bus_track = StemBus.find_bus_track
M.get_folder_children = StemBus.get_folder_children

function M.find_reapitch_fx(track)
  local fx_count = reaper.TrackFX_GetCount(track)
  for fx = 0, fx_count - 1 do
    local _, fx_name = reaper.TrackFX_GetFXName(track, fx, "")
    if fx_name:find("ReaPitch") then
      return fx
    end
  end
  return nil
end

-- Devuelve la lista de instancias {track=, fx=} encontradas entre los hijos
-- del Bus. Atajo usado por varios consumidores (Read, SetSemitones,
-- ToggleEnable, y el panel nuevo) para no repetir el loop de discovery.
function M.find_all_instances()
  local bus = M.find_bus_track()
  if not bus then return {} end

  local children = M.get_folder_children(bus)
  local instances = {}
  for _, tr in ipairs(children) do
    local fx = M.find_reapitch_fx(tr)
    if fx then
      table.insert(instances, {track = tr, fx = fx})
    end
  end
  return instances
end

function M.semitones_to_normalized(semitones)
  return 0.5 + semitones / (M.SEMITONE_RANGE * 2)
end

function M.normalized_to_semitones(normalized)
  return (normalized - 0.5) * (M.SEMITONE_RANGE * 2)
end

function M.read_aggregated_state()
  local instances = M.find_all_instances()

  if #instances == 0 then
    return "none", "none"
  end

  local semitone_values = {}
  local enabled_values = {}

  for _, inst in ipairs(instances) do
    local _, formatted = reaper.TrackFX_GetFormattedParamValue(inst.track, inst.fx, M.SEMITONE_PARAM, "")
    table.insert(semitone_values, formatted)
    table.insert(enabled_values, reaper.TrackFX_GetEnabled(inst.track, inst.fx))
  end

  local semitone_out = semitone_values[1]
  for i = 2, #semitone_values do
    if semitone_values[i] ~= semitone_values[1] then
      semitone_out = "mixed"
      break
    end
  end

  local all_on, all_off = true, true
  for _, e in ipairs(enabled_values) do
    if e then all_off = false else all_on = false end
  end
  local enabled_out
  if all_on then enabled_out = "on"
  elseif all_off then enabled_out = "off"
  else enabled_out = "mixed" end

  return semitone_out, enabled_out
end

function M.write_aggregated_state()
  local semitone_out, enabled_out = M.read_aggregated_state()
  reaper.SetExtState("NikRemote", "reapitch_semitone", semitone_out, false)
  reaper.SetExtState("NikRemote", "reapitch_enabled", enabled_out, false)
  return semitone_out, enabled_out
end

return M