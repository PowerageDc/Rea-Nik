-- Nik_MonitorMix_Publish.lua
-- One-shot: asegura bus y sends (MM.ensure_sends), aplica el filtro y
-- publica NikMonitorMix/list + list_version a ExtState.
-- Cada ejecución INCREMENTA list_version: el cliente lo dispara solo al
-- conectar / cambiar de proyecto / botón Actualizar, nunca en respuesta
-- a un cambio de versión (mismo criterio que PublishLyrics).

local DEBUG = true -- false = sin mensajes en consola

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local MM = dofile(script_dir .. "MonitorMix_common_logic.lua")

local NS = "NikMonitorMix"
local KEY_DATA = "list"
local KEY_VERSION = "list_version"

local function log(msg)
  if DEBUG then reaper.ShowConsoleMsg("[MonitorMix.Publish] " .. msg .. "\n") end
end

local function jsonString(s)
  s = tostring(s or ""):gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    return string.format("\\u%04x", c:byte())
  end)
  return '"' .. s .. '"'
end

-- Índice (base 0) del send de `track` cuyo destino es el bus, o nil.
local function sendIndexTo(track, bus_guid)
  for k = 0, reaper.GetTrackNumSends(track, 0) - 1 do
    local dest = reaper.BR_GetMediaTrackSendInfo_Track(track, 0, k, 1)
    if dest and reaper.GetTrackGUID(dest) == bus_guid then return k end
  end
end

local function buildJson(res, tracks)
  local items = {}
  for _, t in ipairs(tracks) do
    items[#items + 1] = string.format(
      '{"track":%d,"guid":%s,"name":%s,"role":%s,"send":%d}',
      t.track, jsonString(t.guid), jsonString(t.name),
      t.role and jsonString(t.role) or "null", t.send)
  end
  return string.format('{"status":%s,"bus":%s,"pair":%s,"tracks":[%s]}',
    jsonString(res.status), jsonString(res.bus_name or ""),
    res.pair and string.format("%d", res.pair) or "null",
    table.concat(items, ","))
end

local function main()
  local cfg = MM.load_config()
  local res = MM.ensure_sends(cfg)
  for _, line in ipairs(res.log) do log(line) end

  local tracks, skipped = {}, 0
  if res.status == "ok" and res.bus then
    local bus_guid = reaper.GetTrackGUID(res.bus)
    for _, r in ipairs(MM.filter(cfg)) do
      local tr = reaper.GetTrack(0, r.idx)
      local send = tr and sendIndexTo(tr, bus_guid)
      if send then
        tracks[#tracks + 1] = {
          track = r.idx + 1, guid = r.guid, name = r.name,
          role = r.role, send = send,
        }
      else
        skipped = skipped + 1
      end
    end
  end

  local json = buildJson(res, tracks)
  local version = (tonumber(reaper.GetExtState(NS, KEY_VERSION)) or 0) + 1

  -- Primero los datos, después la versión: un cliente que ve la versión
  -- nueva siempre encuentra los datos nuevos.
  reaper.SetExtState(NS, KEY_DATA, json, false)
  reaper.SetExtState(NS, KEY_VERSION, string.format("%d", version), false)

  log(("status=%s, %d tracks (%d sin send, omitidos), %d bytes, versión %d."):format(
    res.status, #tracks, skipped, #json, version))
end

main()