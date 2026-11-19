local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Mvsep = dofile(script_dir .. "../MvsepImporter/MvsepImporter_common_logic.lua")

local M = {}

local SR = 22050
local HOP = 0.002
local CONTEXT = 0.3
local MEDIAN_EPS = 1e-4
local PEAK_RADIUS = 2
local PAST_BLOCKS = 3

local DEFAULTS = { min_ratio = 2.5, abs_floor = 0.003 }

local function median_of(list)
  local s = {}
  for i, v in ipairs(list) do s[i] = v end
  table.sort(s)
  local n = #s
  if n == 0 then return 0 end
  if n % 2 == 1 then return s[(n + 1) // 2] end
  return (s[n // 2] + s[n // 2 + 1]) / 2
end

-- Amplitud (valor eficaz) por bloques de HOP segundos entre t0 y t1, en tiempo de
-- proyecto. Devuelve la lista, o nil si el item no tiene audio en ese rango.
local function block_amplitude(info, t0, t1)
  local take = reaper.GetActiveTake(info.item)
  if not take or reaper.TakeIsMIDI(take) then return nil end
  local n_blocks = math.floor((t1 - t0) / HOP)
  if n_blocks < 8 then return nil end
  local per_block = math.floor(SR * HOP + 0.5)
  local n = n_blocks * per_block

  local acc = reaper.CreateTakeAudioAccessor(take)
  local buf = reaper.new_array(n * 2)
  local ok = reaper.GetAudioAccessorSamples(acc, SR, 2, t0 - info.pos, n, buf)
  reaper.DestroyAudioAccessor(acc)
  if ok ~= 1 then return nil end

  local s = buf.table()
  local amp = {}
  local idx = 1
  for b = 1, n_blocks do
    local sum = 0
    for _ = 1, per_block do
      local m = (s[idx] + s[idx + 1]) * 0.5
      sum = sum + m * m
      idx = idx + 2
    end
    amp[b] = math.sqrt(sum / per_block)
  end
  return amp
end

local function summed_amplitude(items, t0, t1)
  local total
  for _, info in ipairs(items) do
    local amp = block_amplitude(info, t0, t1)
    if amp then
      if not total then
        total = amp
      else
        for i = 1, #amp do total[i] = total[i] + amp[i] end
      end
    end
  end
  return total
end

-- Ataques cerca de t_center, dentro de ±half_window, ordenados por cercanía.
-- items: lista de items de audio cuya amplitud se suma.
-- Cada ataque: { t, ratio }. ratio = subida de amplitud / amplitud mediana local.
function M.candidates(items, t_center, half_window, opts)
  opts = opts or {}
  local min_ratio = opts.min_ratio or DEFAULTS.min_ratio
  local floor = opts.abs_floor or DEFAULTS.abs_floor

  local t0 = t_center - half_window - CONTEXT
  local t1 = t_center + half_window + CONTEXT
  local amp = summed_amplitude(items, t0, t1)
  if not amp then return {} end

  local level = median_of(amp) + MEDIAN_EPS
  local flux = {}
  for k = 1, #amp do
    local past, count = 0, 0
    for j = math.max(1, k - PAST_BLOCKS), k - 1 do
      past = past + amp[j]
      count = count + 1
    end
    local base = count > 0 and past / count or amp[k]
    flux[k] = math.max(0, amp[k] - base)
  end

  local out = {}
  for k = 1, #flux do
    local t = t0 + (k - 0.5) * HOP
    if flux[k] > 0 and amp[k] >= floor and math.abs(t - t_center) <= half_window then
      local is_peak = true
      for j = math.max(1, k - PEAK_RADIUS), math.min(#flux, k + PEAK_RADIUS) do
        if flux[j] > flux[k] then
          is_peak = false
          break
        end
      end
      local ratio = flux[k] / level
      if is_peak and ratio >= min_ratio then
        out[#out + 1] = { t = t, ratio = ratio }
      end
    end
  end
  table.sort(out, function(a, b)
    return math.abs(a.t - t_center) < math.abs(b.t - t_center)
  end)
  return out
end

-- Items de stems que corresponden a una referencia del config: nombre de track
-- (sin distinguir mayúsculas), "@instrumental" o "@all".
function M.resolve(coll, token)
  local list = {}
  local wanted = token:lower()
  for _, s in ipairs(coll.stems) do
    if token == "@all"
      or (token == "@instrumental" and Mvsep.is_instrumental(s.track))
      or s.track:lower() == wanted then
      list[#list + 1] = s
    end
  end
  return list
end

return M