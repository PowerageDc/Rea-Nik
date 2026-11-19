local M = {}

local EPS = 1e-6
local POS_TOLERANCE = 0.001
local BEAT_TOLERANCE = 0.01

local function read_markers()
  local list = {}
  for i = 0, reaper.CountTempoTimeSigMarkers(0) - 1 do
    local _, pos, _, _, bpm, num, den, linear = reaper.GetTempoTimeSigMarker(0, i)
    list[#list + 1] = { idx = i, pos = pos, bpm = bpm, num = num, den = den, linear = linear }
  end
  return list
end

-- Reemplaza el mapa de tempo desde el inicio hasta el último downbeat del plan.
-- Los markers posteriores se conservan y se vuelven a su posición original
-- en una segunda pasada. Devuelve esos markers posteriores tal como estaban.
function M.apply(plan)
  local existing = read_markers()
  local in_range, tail = {}, {}
  local has_zero = false
  for _, mk in ipairs(existing) do
    if mk.pos <= EPS then
      has_zero = true
    elseif mk.pos <= plan.last_pos + EPS then
      in_range[#in_range + 1] = mk.idx
    else
      tail[#tail + 1] = mk
    end
  end

  for k = #in_range, 1, -1 do
    reaper.DeleteTempoTimeSigMarker(0, in_range[k])
  end

  reaper.SetTempoTimeSigMarker(0, has_zero and 0 or -1, 0, -1, -1,
    plan.init.bpm, plan.init.num, plan.init.den, false)

  for _, mk in ipairs(plan.markers) do
    reaper.SetTempoTimeSigMarker(0, -1, mk.pos, -1, -1, mk.bpm, mk.num or 0, mk.den or 0, false)
  end

  local first_tail = reaper.CountTempoTimeSigMarkers(0) - #tail
  for k, mk in ipairs(tail) do
    reaper.SetTempoTimeSigMarker(0, first_tail + k - 1, mk.pos, -1, -1,
      mk.bpm, mk.num, mk.den, mk.linear)
  end

  return tail
end

-- Compara el mapa resultante con el plan. No modifica nada.
function M.verify(plan, tail)
  local report = {
    inserted = 0,
    expected = #plan.markers,
    max_dev = 0,
    off_grid = 0,
    bad_seq = 0,
    tail_dev = 0,
  }

  local current = read_markers()
  for _, mk in ipairs(current) do
    if mk.pos > EPS and mk.pos <= plan.last_pos + POS_TOLERANCE then
      report.inserted = report.inserted + 1
      local planned = plan.markers[report.inserted]
      if planned then
        report.max_dev = math.max(report.max_dev, math.abs(mk.pos - planned.pos))
      end
    end
  end

  local prev_measure
  for _, t in ipairs(plan.downbeats) do
    local beats, measure, cml = reaper.TimeMap2_timeToBeats(0, t)
    local off = beats
    if cml and cml > 0 and beats > cml / 2 then
      off = cml - beats
    end
    if off > BEAT_TOLERANCE then
      report.off_grid = report.off_grid + 1
    end
    if prev_measure and measure - prev_measure ~= 1 then
      report.bad_seq = report.bad_seq + 1
    end
    prev_measure = measure
  end

  local n = #current
  for k, mk in ipairs(tail) do
    local now = current[n - #tail + k]
    if now then
      report.tail_dev = math.max(report.tail_dev, math.abs(now.pos - mk.pos))
    end
  end

  return report
end

return M