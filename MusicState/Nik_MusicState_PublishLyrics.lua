-- Nik_MusicState_PublishLyrics.lua
-- One-shot: lee los eventos lyric (MIDI tipo 5) del track "Lyrics" del
-- proyecto activo y publica NikMusicState/lyrics_data + lyrics_version
-- a ExtState. Si no hay track o no hay eventos, borra ambas keys.
-- Contrato de datos: musicstate_data_model.md 4.7.

local DEBUG = true -- false = sin mensajes en consola

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Bridge = dofile(script_dir .. "MusicStateBridge_common_logic.lua")

local NS = Bridge.BRIDGE_NAMESPACE
local KEY_DATA = "lyrics_data"
local KEY_VERSION = "lyrics_version"
local TRACK_NAME_PATTERN = "lyrics" -- se busca en minusculas, texto plano
local END_MARK = "·"                -- U+00B7, fin de linea explicito
local LYRIC_TYPE = 5

local function log(msg)
  if DEBUG then reaper.ShowConsoleMsg("[PublishLyrics] " .. msg .. "\n") end
end

local function round3(x)
  return math.floor(x * 1000 + 0.5) / 1000
end

local function fmtNumber(x)
  return (string.format("%.3f", x):gsub(",", "."))
end

local function jsonString(s)
  s = s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    return string.format("\\u%04x", c:byte())
  end)
  return '"' .. s .. '"'
end

local function findLyricsTrack(proj)
  for i = 0, reaper.CountTracks(proj) - 1 do
    local tr = reaper.GetTrack(proj, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if name:lower():find(TRACK_NAME_PATTERN, 1, true) then
      return tr, name
    end
  end
  return nil
end

-- Devuelve bars (bar -> lista de {off, text, is_end, seq}), cantidad de
-- eventos publicables y cantidad de eventos ignorados (texto en blanco).
local function collectEvents(proj, track)
  local bars, count, skipped, seq = {}, 0, 0, 0
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local take = reaper.GetActiveTake(item)
    local muted = reaper.GetMediaItemInfo_Value(item, "B_MUTE") == 1
    if take and reaper.TakeIsMIDI(take) and not muted then
      local _, _, _, texts = reaper.MIDI_CountEvts(take)
      for k = 0, texts - 1 do
        local _, _, _, ppq, typ, msg =
          reaper.MIDI_GetTextSysexEvt(take, k, false, false, 0, 0, "")
        if typ == LYRIC_TYPE then
          local text = msg:match("^%s*(.-)%s*$")
          if text == "" then
            skipped = skipped + 1
          else
            -- Redondear el QN absoluto ANTES de partirlo en compas/offset
            local qn = round3(reaper.MIDI_GetProjQNFromPPQPos(take, ppq))
            local bar, bar_start = reaper.TimeMap_QNToMeasures(proj, qn)
            bar = math.floor(bar)
            local off = round3(qn - bar_start)
            if off < 0 then off = 0 end
            seq = seq + 1
            bars[bar] = bars[bar] or {}
            table.insert(bars[bar], {
              off = off, text = text, is_end = (text == END_MARK), seq = seq,
            })
            count = count + 1
          end
        end
      end
    end
  end
  return bars, count, skipped
end

local function buildJson(bars)
  local keys = {}
  for bar in pairs(bars) do keys[#keys + 1] = bar end
  table.sort(keys)
  local parts = {}
  for _, bar in ipairs(keys) do
    local evts = bars[bar]
    table.sort(evts, function(a, b)
      if a.off ~= b.off then return a.off < b.off end
      return a.seq < b.seq
    end)
    local items = {}
    for _, e in ipairs(evts) do
      local text = e.is_end and "null" or jsonString(e.text)
      items[#items + 1] = '{"qn_offset":' .. fmtNumber(e.off) .. ',"text":' .. text .. '}'
    end
    parts[#parts + 1] = '"' .. string.format("%d", bar) .. '":[' .. table.concat(items, ",") .. ']'
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function clearKeys(reason)
  reaper.DeleteExtState(NS, KEY_DATA, true)
  reaper.DeleteExtState(NS, KEY_VERSION, true)
  log(reason .. ": keys globales borradas.")
end

local function main()
  local proj = reaper.EnumProjects(-1)
  local track, track_name = findLyricsTrack(proj)
  if not track then
    clearKeys("sin track de lyrics")
    return
  end

  local bars, count, skipped = collectEvents(proj, track)
  if count == 0 then
    clearKeys("track '" .. track_name .. "' sin eventos lyric")
    return
  end

  local json = buildJson(bars)
  local version = (tonumber(reaper.GetExtState(NS, KEY_VERSION)) or 0) + 1

  -- Primero los datos, despues la version: un cliente que ve la version
  -- nueva siempre encuentra los datos nuevos.
  reaper.SetExtState(NS, KEY_DATA, json, false)
  reaper.SetExtState(NS, KEY_VERSION, string.format("%d", version), false)

  log(("track '%s': %d eventos (%d en blanco ignorados), %d bytes, version %d."):format(
    track_name, count, skipped, #json, version))
end

main()
