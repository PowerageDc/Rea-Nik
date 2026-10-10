local M = {}

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")

local ACCENTS = {
  ["Á"] = "a", ["É"] = "e", ["Í"] = "i", ["Ó"] = "o", ["Ú"] = "u", ["Ñ"] = "n",
  ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ñ"] = "n",
  ["Ü"] = "u", ["ü"] = "u",
}

function M.norm(s)
  s = tostring(s or "")
  for k, v in pairs(ACCENTS) do s = (s:gsub(k, v)) end
  return s:lower()
end

local function match_kw(text, list)
  for _, kw in ipairs(list or {}) do
    local k = M.norm(kw)
    if k ~= "" and text:find(k, 1, true) then return kw end
  end
end

local function match_guid(guid, list)
  local g = guid:lower()
  for _, x in ipairs(list or {}) do
    if x:lower() == g then return x end
  end
end

local function append(dst, src)
  for _, v in ipairs(src or {}) do dst[#dst + 1] = v end
end

local stem_cache
function M.stem_aliases()
  if stem_cache then return stem_cache end
  stem_cache = {}
  local ok, SB = pcall(dofile, script_dir .. "../_Shared/StemBus_common_logic.lua")
  if ok and type(SB) == "table" and type(SB.BUS_ALIASES) == "table" then
    for k, v in pairs(SB.BUS_ALIASES) do
      stem_cache[#stem_cache + 1] = type(v) == "string" and v or tostring(k)
    end
  end
  return stem_cache
end

function M.load_config()
  return dofile(script_dir .. "MonitorMix_config.lua")
end

function M.project_name()
  local a, b = reaper.GetProjectName(0)
  return type(b) == "string" and b or tostring(a or "")
end

function M.build_config(base, project_name)
  local cfg = {
    folders = base.folders,
    include = {}, exclude = {}, guid_include = {}, guid_exclude = {},
    active = {},
  }
  append(cfg.include, base.include)
  append(cfg.exclude, base.exclude)
  append(cfg.guid_include, base.guid_include)
  append(cfg.guid_exclude, base.guid_exclude)
  for _, b in ipairs(base.buses or {}) do cfg.exclude[#cfg.exclude + 1] = b.name end

  local pn = M.norm(project_name)
  for _, ov in ipairs(base.overrides or {}) do
    if ov.match and pn:find(M.norm(ov.match), 1, true) then
      cfg.active[#cfg.active + 1] = ov.match
      append(cfg.include, ov.include)
      append(cfg.exclude, ov.exclude)
      append(cfg.guid_include, ov.guid_include)
      append(cfg.guid_exclude, ov.guid_exclude)
      if ov.folders then cfg.folders = ov.folders end
    end
  end
  return cfg
end

local function collect_tracks()
  local list = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    list[#list + 1] = {
      idx = i,
      name = name,
      nname = M.norm(name),
      guid = reaper.GetTrackGUID(tr),
      depth = math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")),
      recv = reaper.GetTrackNumSends(tr, -1),
      hw = reaper.GetTrackNumSends(tr, 1),
    }
  end
  return list
end

local function assign_members(tracks, folders)
  local member = {}
  for i, t in ipairs(tracks) do
    if t.depth == 1 then
      for _, f in ipairs(folders or {}) do
        if match_kw(t.nname, f.aliases or M.stem_aliases()) then
          local level = 1
          for j = i + 1, #tracks do
            if (f.recursive ~= false or level == 1) and not member[j] then
              member[j] = f.role
            end
            level = level + tracks[j].depth
            if level <= 0 then break end
          end
          break
        end
      end
    end
  end
  return member
end

function M.evaluate(base)
  local pname = M.project_name()
  local cfg = M.build_config(base, pname)
  local tracks = collect_tracks()
  local member = assign_members(tracks, cfg.folders)
  local results = {}

  for i, t in ipairs(tracks) do
    local r = {
      idx = t.idx, name = t.name, guid = t.guid,
      admitted = false, role = nil, reason = "fuera de carpetas válidas",
    }
    local kw = match_guid(t.guid, cfg.guid_exclude) or match_kw(t.nname, cfg.exclude)
    if kw then
      r.reason = "exclude: " .. kw
    elseif match_guid(t.guid, cfg.guid_include) then
      r.admitted, r.role, r.reason = true, member[i], "guid_include"
    elseif t.depth == 1 then
      r.reason = "es un folder"
    elseif t.recv > 0 and t.hw > 0 then
      r.reason = "bus de monitoreo (recv + hw)"
    else
      local ikw = match_kw(t.nname, cfg.include)
      if ikw then
        r.admitted, r.role, r.reason = true, member[i], "include: " .. ikw
      elseif member[i] then
        r.admitted, r.role, r.reason = true, member[i], "carpeta: " .. member[i]
      end
    end
    results[#results + 1] = r
  end
  return results, cfg, pname
end

function M.filter(base)
  local results = M.evaluate(base)
  local out = {}
  for _, r in ipairs(results) do
    if r.admitted then out[#out + 1] = r end
  end
  return out
end

function M.resolve_pair(override)
  local n = reaper.GetNumAudioOutputs()
  if override then
    if override + 1 < n then return override end
    return nil
  end
  local master = reaper.GetMasterTrack(0)
  local used = {}
  for i = 0, reaper.GetTrackNumSends(master, 1) - 1 do
    local dst = math.floor(reaper.GetTrackSendInfo_Value(master, 1, i, "I_DSTCHAN"))
    local ch = dst & 1023
    used[ch] = true
    if (dst & 1024) == 0 then used[ch + 1] = true end
  end
  for p = 0, n - 2, 2 do
    if not used[p] and not used[p + 1] then return p end
  end
end

function M.find_track_by_name(name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, n = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if n == name then return tr end
  end
end

local function receive_sources(bus)
  local set = {}
  for i = 0, reaper.GetTrackNumSends(bus, -1) - 1 do
    local src = reaper.BR_GetMediaTrackSendInfo_Track(bus, -1, i, 0)
    if src then set[reaper.GetTrackGUID(src)] = true end
  end
  return set
end

-- Crea (si faltan) el bus, su hardware output y un send por cada track
-- admitido por el filtro. Idempotente: nunca toca sends existentes.
-- No imprime: devuelve res.log para que lo muestre el llamador.
-- res = { status = "ok" | "no_bus_cfg" | "no_pair" | "no_tracks", bus = track|nil,
--         bus_name, pair, created = {registros del filtro},
--         created_bus, created_hw, log = {líneas} }
function M.ensure_sends(cfg)
  local res = {
    status = "ok", created = {}, created_bus = false, created_hw = false,
    log = {},
  }
  local function log(s) res.log[#res.log + 1] = s end

  local bus_cfg = cfg.buses and cfg.buses[1]
  if not bus_cfg then
    res.status = "no_bus_cfg"
    log("ABORTA: el config no define ningún bus.")
    return res
  end
  res.bus_name = bus_cfg.name

  local d = cfg.defaults or {}
  local send_db = d.send_db or -12
  local send_mode = d.send_mode or 3
  local gain = 10 ^ (send_db / 20)

  local bus = M.find_track_by_name(bus_cfg.name)
  local need_hw = (not bus) or reaper.GetTrackNumSends(bus, 1) == 0
  res.bus = bus

  local have = bus and receive_sources(bus) or {}
  local todo = {}
  for _, r in ipairs(M.filter(cfg)) do
    if not have[r.guid] then todo[#todo + 1] = r end
  end

  if not bus and #todo == 0 then
    res.status = "no_tracks"
    log("Sin tracks admitidos por el filtro: no se crea el bus.")
    return res
  end

  local pair = M.resolve_pair(bus_cfg.pair_override)
  if need_hw and not bus_cfg.pair_override
      and reaper.GetTrackNumSends(reaper.GetMasterTrack(0), 1) == 0 then
    res.status = "no_pair"
    log("ABORTA: el master no tiene hardware output, no se puede deducir el par secundario (definir pair_override en el config).")
    return res
  end

  if need_hw and not pair then
    res.status = "no_pair"
    log("ABORTA: no hay par secundario disponible (revisar Preferences > Audio > Last output).")
    return res
  end
  res.pair = pair
  if not need_hw then
    res.pair = math.floor(reaper.GetTrackSendInfo_Value(bus, 1, 0, "I_DSTCHAN"))
  end

  if bus then
    local hw_txt = need_hw and "sin hardware output" or ("hardware I_DSTCHAN=" .. res.pair)
    log("Bus existente: " .. bus_cfg.name .. " (" .. hw_txt .. ")")
    if reaper.GetMediaTrackInfo_Value(bus, "B_MAINSEND") ~= 0 then
      log("AVISO: el bus tiene B_MAINSEND activo, suena también por el master (no se modifica).")
    end
  end

  if bus and not need_hw and #todo == 0 then
    log("Nada que crear: todos los tracks admitidos ya tienen su send.")
    return res
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  if not bus then
    local idx = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(idx, true)
    bus = reaper.GetTrack(0, idx)
    reaper.GetSetMediaTrackInfo_String(bus, "P_NAME", bus_cfg.name, true)
    reaper.SetMediaTrackInfo_Value(bus, "B_MAINSEND", 0)
    res.bus, res.created_bus = bus, true
    log("Bus creado: " .. bus_cfg.name)
  end

  if need_hw then
    local hw = reaper.CreateTrackSend(bus, nil)
    reaper.SetTrackSendInfo_Value(bus, 1, hw, "I_DSTCHAN", pair)
    res.created_hw = true
    log(string.format("Hardware output: I_DSTCHAN=%d (salidas %d/%d, base 1)", pair, pair + 1, pair + 2))
  end

  for _, r in ipairs(todo) do
    local tr = reaper.GetTrack(0, r.idx)
    local s = reaper.CreateTrackSend(tr, bus)
    reaper.SetTrackSendInfo_Value(tr, 0, s, "D_VOL", gain)
    reaper.SetTrackSendInfo_Value(tr, 0, s, "I_SENDMODE", send_mode)
    reaper.SetTrackSendInfo_Value(tr, 0, s, "B_MUTE", 0)
    log(string.format("  send creado: [%d] %s (%s, %g dB)", r.idx + 1, r.name, r.role or "-", send_db))
  end

  reaper.PreventUIRefresh(-1)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Monitor Mix: crear bus y sends", -1)
  res.created = todo
  log(string.format("Listo: %d sends creados.", #todo))
  return res
end

return M