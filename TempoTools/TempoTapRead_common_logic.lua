local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Base = dofile(script_dir .. "TempoTools_common_logic.lua")

local M = {}

local DEFAULTS = {
  num = 4,
  den = 4,
  min_gap = 0.08,
}

local VALID_DEN = { [1] = true, [2] = true, [4] = true, [8] = true, [16] = true, [32] = true }

-- "TAP1 6/8" -> 6, 8. Devuelve nil si no hay compás o no es válido.
local function parse_timesig(name)
  local n, d = name:match("^" .. Base.NAME_DOWNBEAT .. "%s+(%d+)/(%d+)$")
  n, d = tonumber(n), tonumber(d)
  if n and d and n >= 1 and VALID_DEN[d] then
    return n, d
  end
  return nil
end

-- Pulsos que se sienten por compás: los compuestos ternarios (6/8, 9/8, 12/8)
-- cuentan de a tres corcheas.
local function pulses(num, den)
  if den == 8 and num > 3 and num % 3 == 0 then
    return num // 3
  end
  return num
end

function M.pulses(num, den)
  return pulses(num, den)
end

-- Todos los markers TAP / TAP1 del proyecto activo, ordenados por posición.
function M.read_taps()
  local taps = {}
  local i = 0
  while true do
    local ret, is_region, pos, _, name = reaper.EnumProjectMarkers3(0, i)
    if ret == 0 then break end
    if not is_region and Base.is_tap_name(name) then
      local is_down = name ~= Base.NAME_BEAT
      local num, den
      if is_down then
        num, den = parse_timesig(name)
      end
      taps[#taps + 1] = {
        pos = pos,
        is_down = is_down,
        num = num,
        den = den,
        bad_sig = is_down and not num and name ~= Base.NAME_DOWNBEAT,
      }
    end
    i = i + 1
  end
  table.sort(taps, function(a, b) return a.pos < b.pos end)
  return taps
end

-- Agrupa los taps en compases, de downbeat a downbeat.
-- opts: num, den (compás inicial, 4/4 por defecto), min_gap (segundos).
-- Devuelve (measures, warnings).
-- measure = { start, finish, num, den, declared, mode, beats }
--   mode  = "beat" (hay taps de beat entre los downbeats) o "bar" (solo downbeats)
--   beats = lista de { pos, origin } con origin "tapped" o "interpolated"
-- warning = { pos, level, text } con level "info" o "warn"
function M.group(taps, opts)
  opts = opts or {}
  local cur_num = opts.num or DEFAULTS.num
  local cur_den = opts.den or DEFAULTS.den
  local min_gap = opts.min_gap or DEFAULTS.min_gap
  local measures, warnings = {}, {}

  local function warn(pos, level, text)
    warnings[#warnings + 1] = { pos = pos, level = level, text = text }
  end

  local downs = {}
  for i, t in ipairs(taps) do
    if t.is_down then downs[#downs + 1] = i end
    if i > 1 and t.pos - taps[i - 1].pos < min_gap then
      warn(t.pos, "warn", "dos taps casi superpuestos (posible doble pulsación)")
    end
    if t.bad_sig then
      warn(t.pos, "warn", "compás del nombre no válido, se ignora")
    end
  end

  if #downs < 2 then
    warn(taps[1] and taps[1].pos or 0, "warn", "hacen falta al menos dos downbeats")
    return measures, warnings
  end
  if downs[1] > 1 then
    warn(taps[1].pos, "warn", "taps antes del primer downbeat: ignorados")
  end
  if downs[#downs] < #taps then
    warn(taps[downs[#downs] + 1].pos, "warn", "taps después del último downbeat: ignorados")
  end

  for d = 1, #downs - 1 do
    local first, last = taps[downs[d]], taps[downs[d + 1]]
    local mid = {}
    for k = downs[d] + 1, downs[d + 1] - 1 do
      mid[#mid + 1] = taps[k]
    end

    local declared = first.num ~= nil
    if declared then
      cur_num, cur_den = first.num, first.den
    end
    local expected = pulses(cur_num, cur_den)
    local mode = #mid > 0 and "beat" or "bar"
    local count = expected

    if mode == "beat" then
      count = #mid + 1
      if count ~= expected then
        if declared then
          warn(first.pos, "warn", string.format(
            "compás declarado %d/%d espera %d pulsos y hay %d taps",
            cur_num, cur_den, expected, count))
        else
          cur_num, cur_den = count, 4
          warn(first.pos, "info", string.format(
            "compás inferido por conteo: %d/4", count))
        end
      end
    end

    local beats = { { pos = first.pos, origin = "tapped" } }
    if mode == "beat" then
      for _, t in ipairs(mid) do
        beats[#beats + 1] = { pos = t.pos, origin = "tapped" }
      end
    else
      local span = last.pos - first.pos
      for j = 1, count - 1 do
        beats[#beats + 1] = { pos = first.pos + span * j / count, origin = "interpolated" }
      end
    end

    measures[#measures + 1] = {
      start = first.pos,
      finish = last.pos,
      num = cur_num,
      den = cur_den,
      declared = declared,
      mode = mode,
      beats = beats,
    }
  end

  return measures, warnings
end

return M