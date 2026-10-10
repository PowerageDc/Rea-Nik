local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local MM = dofile(script_dir .. "MonitorMix_common_logic.lua")

local function msg(s) reaper.ShowConsoleMsg(s .. "\n") end

local function find_track_by_name(name)
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

reaper.ClearConsole()

local cfg = MM.load_config()
local bus_cfg = cfg.buses and cfg.buses[1]
if not bus_cfg then
  msg("ABORTA: el config no define ningún bus.")
  return
end

local d = cfg.defaults or {}
local send_db = d.send_db or -12
local send_mode = d.send_mode or 3
local gain = 10 ^ (send_db / 20)

local bus = find_track_by_name(bus_cfg.name)
local pair = MM.resolve_pair(bus_cfg.pair_override)
local need_hw = (not bus) or reaper.GetTrackNumSends(bus, 1) == 0

if need_hw and not pair then
  msg("ABORTA: no hay par secundario disponible (revisar Preferences > Audio > Last output).")
  return
end

local have = bus and receive_sources(bus) or {}
local todo = {}
for _, r in ipairs(MM.filter(cfg)) do
  if not have[r.guid] then todo[#todo + 1] = r end
end

if bus then
  local hw_txt = "sin hardware output"
  if not need_hw then
    hw_txt = "hardware I_DSTCHAN=" .. math.floor(reaper.GetTrackSendInfo_Value(bus, 1, 0, "I_DSTCHAN"))
  end
  msg("Bus existente: " .. bus_cfg.name .. " (" .. hw_txt .. ")")
  if reaper.GetMediaTrackInfo_Value(bus, "B_MAINSEND") ~= 0 then
    msg("AVISO: el bus tiene B_MAINSEND activo, suena también por el master (no se modifica).")
  end
end

if bus and not need_hw and #todo == 0 then
  msg("Nada que crear: todos los tracks admitidos ya tienen su send.")
  return
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

if not bus then
  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  bus = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(bus, "P_NAME", bus_cfg.name, true)
  reaper.SetMediaTrackInfo_Value(bus, "B_MAINSEND", 0)
  msg("Bus creado: " .. bus_cfg.name)
end

if need_hw then
  local hw = reaper.CreateTrackSend(bus, nil)
  reaper.SetTrackSendInfo_Value(bus, 1, hw, "I_DSTCHAN", pair)
  msg(string.format("Hardware output: I_DSTCHAN=%d (salidas %d/%d, base 1)", pair, pair + 1, pair + 2))
end

for _, r in ipairs(todo) do
  local tr = reaper.GetTrack(0, r.idx)
  local s = reaper.CreateTrackSend(tr, bus)
  reaper.SetTrackSendInfo_Value(tr, 0, s, "D_VOL", gain)
  reaper.SetTrackSendInfo_Value(tr, 0, s, "I_SENDMODE", send_mode)
  reaper.SetTrackSendInfo_Value(tr, 0, s, "B_MUTE", 0)
  msg(string.format("  send creado: [%d] %s (%s, %d dB)", r.idx + 1, r.name, r.role or "-", send_db))
end

reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Monitor Mix: crear bus y sends", -1)
msg(string.format("Listo: %d sends creados.", #todo))