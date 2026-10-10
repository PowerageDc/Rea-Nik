local BUS_NAME = "TEST Monitor Bus"
local function msg(s) reaper.ShowConsoleMsg(s .. "\n") end

local function find_bus()
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if name == BUS_NAME then return tr end
  end
end

local function resolve_pair()
  local n = reaper.GetNumAudioOutputs()
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

local function report_state(label)
  local u = reaper.Undo_CanUndo2(0) or "(nada)"
  msg(string.format("%s -> dirty=%s | ultimo Undo: %s",
    label, tostring(reaper.IsProjectDirty(0)), u))
end

reaper.ClearConsole()
report_state("Estado inicial")

local bus = find_bus()
local src = reaper.GetSelectedTrack(0, 0)
local pair = resolve_pair()

if not bus and not src then
  msg("ABORTA: selecciona un track fuente (con audio) antes de correr el script.")
  return
end
if not bus and not pair then
  msg("ABORTA: no hay par secundario disponible.")
  return
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

if bus then
  reaper.DeleteTrack(bus)
  msg("Limpieza: bus de prueba eliminado (sus sends recibidos desaparecen con el).")
else
  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  bus = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(bus, "P_NAME", BUS_NAME, true)
  reaper.SetMediaTrackInfo_Value(bus, "B_MAINSEND", 0)

  local hw = reaper.CreateTrackSend(bus, nil)
  reaper.SetTrackSendInfo_Value(bus, 1, hw, "I_DSTCHAN", pair)

  local s = reaper.CreateTrackSend(src, bus)
  msg(string.format("Bus: B_MAINSEND=%d, hw send I_DSTCHAN=%d (salidas %d/%d base 1)",
    reaper.GetMediaTrackInfo_Value(bus, "B_MAINSEND"),
    reaper.GetTrackSendInfo_Value(bus, 1, hw, "I_DSTCHAN"), pair + 1, pair + 2))
  msg(string.format("Send fuente->bus: vol=%.3f mute=%d I_SENDMODE=%d (0=post-fader, 1=pre-FX, 3=post-FX)",
    reaper.GetTrackSendInfo_Value(src, 0, s, "D_VOL"),
    reaper.GetTrackSendInfo_Value(src, 0, s, "B_MUTE"),
    reaper.GetTrackSendInfo_Value(src, 0, s, "I_SENDMODE")))
  msg("Fuente: B_MAINSEND=" .. reaper.GetMediaTrackInfo_Value(src, "B_MAINSEND")
    .. " (sigue mandando al master tambien)")
end

reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
reaper.Undo_EndBlock("TEST Monitor Bus", -1)
report_state("Estado final")