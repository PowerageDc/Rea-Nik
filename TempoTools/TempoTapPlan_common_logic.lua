local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Read = dofile(script_dir .. "TempoTapRead_common_logic.lua")

local M = {}

local COMPOUND_FACTOR = 0.75
local PREROLL_TOLERANCE = 0.15
local INIT_MEASURES = 4

-- Relación entre pulsos por minuto y el BPM que recibe REAPER.
-- nil si el compás no tiene conversión validada.
local function bpm_factor(num, den)
  if den == 4 then
    return 1
  end
  if den == 8 and num > 3 and num % 3 == 0 then
    return COMPOUND_FACTOR
  end
  return nil
end

local function median(list)
  local s = {}
  for i, v in ipairs(list) do s[i] = v end
  table.sort(s)
  local n = #s
  if n % 2 == 1 then
    return s[(n + 1) // 2]
  end
  return (s[n // 2] + s[n // 2 + 1]) / 2
end

-- measures: salida de TempoTapRead.group.
-- opts: proj_num, proj_den, proj_bpm (tempo actual del proyecto, en negras si
-- proj_den es 4) y preroll_bars (opcional, evita deducirlos).
-- Devuelve (plan, warnings); plan es nil si no se pudo calcular.
-- plan = { delta, preroll_bars, bar, init = {num, den, bpm},
--          markers = { {pos, bpm, num, den, closing} }, first_pos, last_pos }
-- Las posiciones del plan ya están desplazadas por delta.
function M.build(measures, opts)
  local warnings = {}
  local function warn(pos, level, text)
    warnings[#warnings + 1] = { pos = pos, level = level, text = text }
  end

  local usable = {}
  for _, m in ipairs(measures) do
    local expected = Read.pulses(m.num, m.den)
    if not bpm_factor(m.num, m.den) then
      warn(m.start, "warn", string.format(
        "compás %d/%d sin conversión de BPM validada: omitido", m.num, m.den))
    elseif #m.beats ~= expected then
      warn(m.start, "warn", string.format(
        "compás %d/%d con %d beats (esperados %d): omitido", m.num, m.den, #m.beats, expected))
    else
      usable[#usable + 1] = m
    end
  end

  if #usable == 0 or usable[1] ~= measures[1] then
    warn(measures[1] and measures[1].start or 0, "warn",
      "el primer compás no es utilizable: no se puede calcular el tempo inicial")
    return nil, warnings
  end

  local first = usable[1]
  local durs = {}
  for i = 1, math.min(INIT_MEASURES, #usable) do
    local m = usable[i]
    if m.num == first.num and m.den == first.den then
      durs[#durs + 1] = m.finish - m.start
    end
  end
  local bar = median(durs)

  local n_bars = opts.preroll_bars
  if not n_bars then
    if opts.proj_den ~= 4 then
      warn(first.start, "warn", "el compás del proyecto no es /4: indicar preroll_bars")
      return nil, warnings
    end
    local bar_cur = opts.proj_num * 60 / opts.proj_bpm
    local ratio = first.start / bar_cur
    n_bars = math.floor(ratio + 0.5)
    if n_bars < 1 or math.abs(ratio - n_bars) > PREROLL_TOLERANCE then
      warn(first.start, "warn", string.format(
        "el primer downbeat equivale a %.2f compases del tempo actual: no es un número entero", ratio))
      return nil, warnings
    end
  end

  local delta = n_bars * bar - first.start
  local init = {
    num = first.num,
    den = first.den,
    bpm = Read.pulses(first.num, first.den) * 60 / bar * bpm_factor(first.num, first.den),
  }

  local markers = {}
  local prev_num, prev_den = init.num, init.den
  local last_bpm
  for _, m in ipairs(usable) do
    local factor = bpm_factor(m.num, m.den)
    local sig_changed = m.num ~= prev_num or m.den ~= prev_den
    if m.mode == "bar" then
      local bpm = #m.beats * 60 / (m.finish - m.start) * factor
      markers[#markers + 1] = {
        pos = m.start + delta,
        bpm = bpm,
        num = sig_changed and m.num or nil,
        den = sig_changed and m.den or nil,
      }
      last_bpm = bpm
    else
      for j, b in ipairs(m.beats) do
        local nxt = m.beats[j + 1] and m.beats[j + 1].pos or m.finish
        local bpm = 60 / (nxt - b.pos) * factor
        local with_sig = j == 1 and sig_changed
        markers[#markers + 1] = {
          pos = b.pos + delta,
          bpm = bpm,
          num = with_sig and m.num or nil,
          den = with_sig and m.den or nil,
        }
        last_bpm = bpm
      end
    end
    prev_num, prev_den = m.num, m.den
  end

  local last = usable[#usable]
  markers[#markers + 1] = { pos = last.finish + delta, bpm = last_bpm, closing = true }

  return {
    delta = delta,
    preroll_bars = n_bars,
    bar = bar,
    init = init,
    markers = markers,
    first_pos = first.start + delta,
    last_pos = last.finish + delta,
  }, warnings
end

return M