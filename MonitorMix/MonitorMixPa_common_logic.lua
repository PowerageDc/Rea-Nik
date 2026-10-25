-- MonitorMixPa_common_logic.lua
-- Capa PA: corta o activa el send al master/padre (B_MAINSEND) de los tracks
-- hoja (todo track que no es folder ni bus de monitoreo), sin tocar los sends
-- al bus de monitoreo ni el mute/solo reales de REAPER.
--
-- Modelo por proyecto: dos conjuntos de GUID, `cut` y `solo`. El send de una
-- hoja queda activo si no está en `cut` y (`solo` está vacío o la hoja está
-- en `solo`). Sin solo activo, la verdad es el B_MAINSEND real (los cambios
-- hechos a mano en REAPER se adoptan como cortes); con solo activo mandan los
-- conjuntos, persistidos en ProjExtState.
--
-- Órdenes (ExtState NikMonitorMix/pa_cmd, "<op>:<destino>"):
--   toggle:N | cut:N | on:N | solo:N   N = número de track del web control
--                                      (base 1); un folder expande a sus hojas
--   toggle:all | cut:all | on:all      todas las hojas del filtro
--   clear                              vacía cortados y solo

local M = {}

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local MM = dofile(script_dir .. "MonitorMix_common_logic.lua")

local NS = "NikMonitorMix"
local KEY_CMD = "pa_cmd"
local KEY_STATE = "pa_state"
local PROJ_CUT = "pa_cut"
local PROJ_SOLO = "pa_solo"

local function load_set(key)
  local _, v = reaper.GetProjExtState(0, NS, key)
  local set = {}
  for g in (v or ""):gmatch("{[^}]+}") do set[g] = true end
  return set
end

-- Escribe solo si cambió, para no ensuciar el proyecto sin necesidad.
local function save_set(key, set)
  local list = {}
  for g in pairs(set) do list[#list + 1] = g end
  table.sort(list)
  local s = table.concat(list, ",")
  local _, cur = reaper.GetProjExtState(0, NS, key)
  if cur == s then return end
  reaper.SetProjExtState(0, NS, key, s)
end

-- Índices (base 0) de todos los tracks dentro del folder `idx`, a cualquier
-- profundidad.
local function descendants(idx)
  local out, level = {}, 1
  for j = idx + 1, reaper.CountTracks(0) - 1 do
    out[#out + 1] = j
    level = level + math.floor(reaper.GetMediaTrackInfo_Value(reaper.GetTrack(0, j), "I_FOLDERDEPTH"))
    if level <= 0 then break end
  end
  return out
end

-- Todas las hojas (tracks que no son folder) menos los buses de monitoreo:
-- el PA puede cortar cualquier fila que suene por el master, no solo las que
-- admite el filtro de Monitor Mix.
local function universe(cfg)
  local bus_names = {}
  for _, b in ipairs(cfg.buses or {}) do bus_names[b.name] = true end
  local leaves = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    local is_folder = math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")) == 1
    local is_bus = bus_names[name]
      or (reaper.GetTrackNumSends(tr, -1) > 0 and reaper.GetTrackNumSends(tr, 1) > 0)
    if not is_folder and not is_bus then
      leaves[#leaves + 1] = { idx = i, guid = reaper.GetTrackGUID(tr), tr = tr }
    end
  end
  return leaves
end

local function load_model(cfg)
  local leaves = universe(cfg)
  local present = {}
  for _, l in ipairs(leaves) do present[l.guid] = true end

  local solo = {}
  for g in pairs(load_set(PROJ_SOLO)) do
    if present[g] then solo[g] = true end
  end

  local cut = {}
  if next(solo) == nil then
    for _, l in ipairs(leaves) do
      if reaper.GetMediaTrackInfo_Value(l.tr, "B_MAINSEND") == 0 then cut[l.guid] = true end
    end
  else
    for g in pairs(load_set(PROJ_CUT)) do
      if present[g] then cut[g] = true end
    end
  end
  return leaves, cut, solo
end

-- GUIDs afectados por un destino: "all", una hoja o un folder (sus hojas).
-- Un track que no es hoja (bus de monitoreo) devuelve lista vacía.
local function group_guids(leaves, target)
  local out = {}
  if target == "all" then
    for _, l in ipairs(leaves) do out[#out + 1] = l.guid end
    return out
  end
  local n = tonumber(target)
  if not n then return out end
  local idx = math.floor(n) - 1
  local by_idx = {}
  for _, l in ipairs(leaves) do by_idx[l.idx] = l.guid end
  if by_idx[idx] then return { by_idx[idx] } end
  local tr = reaper.GetTrack(0, idx)
  if tr and math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")) == 1 then
    for _, j in ipairs(descendants(idx)) do
      if by_idx[j] then out[#out + 1] = by_idx[j] end
    end
  end
  return out
end

local function all_in(set, guids)
  for _, g in ipairs(guids) do
    if not set[g] then return false end
  end
  return #guids > 0
end

local function put(set, guids, on)
  for _, g in ipairs(guids) do set[g] = on and true or nil end
end

-- Devuelve true si la orden es válida y modificó los conjuntos.
local function apply_op(op, target, leaves, cut, solo)
  if op == "clear" then
    for g in pairs(cut) do cut[g] = nil end
    for g in pairs(solo) do solo[g] = nil end
    return true
  end
  local guids = group_guids(leaves, target)
  if #guids == 0 then return false end
  if op == "cut" then put(cut, guids, true)
  elseif op == "on" then put(cut, guids, false)
  elseif op == "toggle" then put(cut, guids, not all_in(cut, guids))
  elseif op == "solo" then put(solo, guids, not all_in(solo, guids))
  else return false end
  return true
end

-- Hojas cuyo B_MAINSEND real difiere del que dicta el modelo.
local function plan(leaves, cut, solo)
  local any_solo = next(solo) ~= nil
  local diff = {}
  for _, l in ipairs(leaves) do
    local on = (not cut[l.guid]) and ((not any_solo) or solo[l.guid])
    local want = on and 1 or 0
    if reaper.GetMediaTrackInfo_Value(l.tr, "B_MAINSEND") ~= want then
      diff[#diff + 1] = { tr = l.tr, want = want }
    end
  end
  return diff
end

-- {"n":hojas,"cut":[tracks],"solo":[tracks],"folders":[{"track":N,"n":hojas,"cut":k,"solo":k}]}
-- Números del web control (base 1). "n" es el total de hojas del PA.
local function state_json(leaves, cut, solo)
  local cut_l, solo_l, by_idx = {}, {}, {}
  for _, l in ipairs(leaves) do
    by_idx[l.idx] = l
    if cut[l.guid] then cut_l[#cut_l + 1] = l.idx + 1 end
    if solo[l.guid] then solo_l[#solo_l + 1] = l.idx + 1 end
  end
  local folders = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")) == 1 then
      local n, c, s = 0, 0, 0
      for _, j in ipairs(descendants(i)) do
        local l = by_idx[j]
        if l then
          n = n + 1
          if cut[l.guid] then c = c + 1 end
          if solo[l.guid] then s = s + 1 end
        end
      end
      if n > 0 then
        folders[#folders + 1] = string.format('{"track":%d,"n":%d,"cut":%d,"solo":%d}', i + 1, n, c, s)
      end
    end
  end
  return string.format('{"n":%d,"cut":[%s],"solo":[%s],"folders":[%s]}',
    #leaves, table.concat(cut_l, ","), table.concat(solo_l, ","), table.concat(folders, ","))
end

local function write_state(leaves, cut, solo)
  reaper.SetExtState(NS, KEY_STATE, state_json(leaves, cut, solo), false)
end

-- Solo publica (no modifica nada): lo llama Publish.lua al cambiar de
-- proyecto, para que el remoto no muestre el estado del proyecto anterior.
function M.publish_state(cfg)
  local leaves, cut, solo = load_model(cfg)
  write_state(leaves, cut, solo)
end

-- Lee pa_cmd, lo borra, aplica y publica el estado. Sin orden solo publica.
function M.run_command()
  local cfg = MM.load_config()
  local function log(s)
    if cfg.debug ~= false then
      reaper.ShowConsoleMsg("[MonitorMix.PA " .. os.date("%H:%M:%S") .. "] " .. s .. "\n")
    end
  end

  local raw = reaper.GetExtState(NS, KEY_CMD)
  reaper.DeleteExtState(NS, KEY_CMD, false)

  local leaves, cut, solo = load_model(cfg)
  local op, target = raw:match("^(%a+):?(.*)$")
  if op and apply_op(op, target, leaves, cut, solo) then
    local diff = plan(leaves, cut, solo)
    if #diff > 0 then
      reaper.Undo_BeginBlock()
      reaper.PreventUIRefresh(1)
      for _, d in ipairs(diff) do reaper.SetMediaTrackInfo_Value(d.tr, "B_MAINSEND", d.want) end
      reaper.PreventUIRefresh(-1)
      reaper.TrackList_AdjustWindows(false)
      reaper.UpdateArrange()
      reaper.Undo_EndBlock("Monitor Mix: PA", -1)
    end
    -- Con solo activo los conjuntos son la verdad y se persisten; sin solo
    -- la verdad es B_MAINSEND y no hace falta guardar nada.
    local keep = next(solo) ~= nil
    save_set(PROJ_SOLO, solo)
    save_set(PROJ_CUT, keep and cut or {})
    log(string.format("%s:%s -> %d sends cambiados", op, target, #diff))
  elseif raw ~= "" then
    log("orden ignorada: '" .. raw .. "' (inválida o destino que no es hoja ni folder)")
  end
  write_state(leaves, cut, solo)
end

return M