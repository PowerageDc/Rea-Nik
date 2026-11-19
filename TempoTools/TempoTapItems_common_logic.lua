local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local StemBus = dofile(script_dir .. "../_Shared/StemBus_common_logic.lua")
local Mvsep = dofile(script_dir .. "../MvsepImporter/MvsepImporter_common_logic.lua")

local M = {}

local QN_TOLERANCE = 0.01

local function track_name(tr)
  local _, name = reaper.GetTrackName(tr)
  return name
end

local function find_track_index(name)
  local wanted = name:lower()
  for i = 0, reaper.CountTracks(0) - 1 do
    if track_name(reaper.GetTrack(0, i)):lower() == wanted then
      return i
    end
  end
  return nil
end

local function item_info(tr, item)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local info = {
    item = item,
    track = track_name(tr),
    pos = pos,
    len = len,
    mode = reaper.GetMediaItemInfo_Value(item, "C_BEATATTACHMODE"),
    take = "",
    source = "",
    start_qn = reaper.TimeMap2_timeToQN(0, pos),
    end_qn = reaper.TimeMap2_timeToQN(0, pos + len),
  }
  local take = reaper.GetActiveTake(item)
  if take then
    info.take = reaper.GetTakeName(take)
    info.source = reaper.GetMediaSourceType(reaper.GetMediaItemTake_Source(take), "")
  end
  return info
end

-- Lee los items del proyecto agrupados por rol.
-- Devuelve { stems, click_items, count_in, others, fresh }.
-- fresh = true si el item de stem más temprano está en 0 (recién importados).
function M.collect(cfg)
  local coll = { stems = {}, click_items = {}, count_in = {}, others = 0, fresh = false }

  local role = {}
  local bus = StemBus.find_bus_track()
  if bus then
    for _, tr in ipairs(StemBus.get_folder_children(bus)) do
      role[tr] = "stem"
    end
  end
  local click_idx = find_track_index(cfg.click_track_name)
  if click_idx then role[reaper.GetTrack(0, click_idx)] = "click" end
  local count_idx = find_track_index(cfg.count_in_track_name)
  if count_idx then role[reaper.GetTrack(0, count_idx)] = "count_in" end

  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if not role[tr] and Mvsep.is_instrumental(track_name(tr)) then
      role[tr] = "stem"
    end
  end

  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local r = role[tr]
    for k = 0, reaper.CountTrackMediaItems(tr) - 1 do
      local info = item_info(tr, reaper.GetTrackMediaItem(tr, k))
      if r == "stem" then
        coll.stems[#coll.stems + 1] = info
      elseif r == "click" then
        coll.click_items[#coll.click_items + 1] = info
      elseif r == "count_in" then
        coll.count_in[#coll.count_in + 1] = info
      else
        coll.others = coll.others + 1
      end
    end
  end

  local earliest
  for _, s in ipairs(coll.stems) do
    if not earliest or s.pos < earliest then earliest = s.pos end
  end
  coll.fresh = earliest ~= nil and earliest < cfg.fresh_tolerance
  return coll
end

-- Qué pasaría con los items si se aplicara el plan. No modifica nada.
-- Devuelve { stems = {...}, click, count_in = {...}, warnings }.
function M.evaluate(coll, plan)
  local ev = { stems = {}, count_in = {}, warnings = {} }
  local function warn(text)
    ev.warnings[#ev.warnings + 1] = text
  end

  if #coll.stems == 0 then
    ev.blocking = true
    warn("no se encontraron items de stems bajo el folder del Stem Bus")
  end
  for _, s in ipairs(coll.stems) do
    local new_pos = s.pos + plan.delta
    ev.stems[#ev.stems + 1] = { track = s.track, take = s.take, pos = s.pos, new_pos = new_pos }
    if new_pos < 0 then
      ev.blocking = true
      warn(string.format("stem %s quedaría en %.3f s, antes de 0", s.track, new_pos))
    end
  end

  local c = coll.click_items[1]
  if not c then
    warn("no se encontró un item en la pista de click")
  else
    ev.click = { track = c.track, take = c.take, source = c.source, pos = c.pos, len = c.len, new_len = c.len + plan.delta }
    if #coll.click_items > 1 then
      warn("la pista de click tiene más de un item: se usaría solo el primero")
    end
    if c.source ~= "CLICK" then
      warn("el item de la pista de click no es un click source (tipo '" .. c.source .. "')")
    end
    if ev.click.new_len <= 0 then
      ev.blocking = true
      warn("el item de click quedaría con largo cero o negativo")
    end
  end

  if #coll.count_in == 0 then
    warn("no se encontró un item en la pista del count-in")
  else
    local first_qn, last_qn
    for _, ci in ipairs(coll.count_in) do
      ev.count_in[#ev.count_in + 1] = { take = ci.take, pos = ci.pos, len = ci.len, mode = ci.mode }
      first_qn = (not first_qn or ci.start_qn < first_qn) and ci.start_qn or first_qn
      last_qn = (not last_qn or ci.end_qn > last_qn) and ci.end_qn or last_qn
      if ci.mode ~= 1 then
        ev.to_convert = (ev.to_convert or 0) + 1
      end
      if ci.pos > 0.001 then
        warn("el item del count-in '" .. ci.take .. "' no empieza en 0")
      end
    end
    local expected_qn = plan.preroll_bars * plan.init.num * 4 / plan.init.den
    ev.count_in.qn = last_qn - first_qn
    ev.count_in.expected_qn = expected_qn
    if math.abs(ev.count_in.qn - expected_qn) > QN_TOLERANCE then
      warn(string.format(
        "el count-in mide %.2f negras y el pre-roll de %d compases de %d/%d necesita %.2f",
        ev.count_in.qn, plan.preroll_bars, plan.init.num, plan.init.den, expected_qn))
    end
  end

  return ev
end

-- Pasa el count-in a timebase beats, mueve los stems y alarga o acorta el click.
-- Devuelve la cantidad de items del count-in convertidos.
function M.apply(coll, plan)
  local converted = 0
  for _, ci in ipairs(coll.count_in) do
    if ci.mode ~= 1 then
      reaper.SetMediaItemInfo_Value(ci.item, "C_BEATATTACHMODE", 1)
      converted = converted + 1
    end
  end
  for _, s in ipairs(coll.stems) do
    reaper.SetMediaItemInfo_Value(s.item, "D_POSITION", s.pos + plan.delta)
  end
  local c = coll.click_items[1]
  if c then
    reaper.SetMediaItemInfo_Value(c.item, "D_LENGTH", c.len + plan.delta)
  end
  return converted
end

return M