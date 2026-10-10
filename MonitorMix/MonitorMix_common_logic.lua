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

return M