local function msg(s) reaper.ShowConsoleMsg(s .. "\n") end

reaper.ClearConsole()

local n = reaper.GetNumAudioOutputs()
msg("== Salidas de audio (" .. n .. ") ==")
for i = 0, n - 1 do
  msg(string.format("  [%d] %s", i, reaper.GetOutputChannelName(i) or "?"))
end

local master = reaper.GetMasterTrack(0)
local ns = reaper.GetTrackNumSends(master, 1)
msg("\n== Hardware outputs del master (" .. ns .. ") ==")

local used = {}
for i = 0, ns - 1 do
  local dst = math.floor(reaper.GetTrackSendInfo_Value(master, 1, i, "I_DSTCHAN"))
  local mono = (dst & 1024) ~= 0
  local ch = dst & 1023
  if mono then
    used[ch] = true
    msg(string.format("  send %d: I_DSTCHAN=%d -> mono salida %d", i, dst, ch))
  else
    used[ch] = true
    used[ch + 1] = true
    msg(string.format("  send %d: I_DSTCHAN=%d -> estereo %d/%d", i, dst, ch, ch + 1))
  end
end
if ns == 0 then msg("  (ninguno: el master no tiene hardware outputs)") end

msg("\n== Pares estereo libres (indices base 0) ==")
local secondary
for p = 0, n - 2 do
  if not used[p] and not used[p + 1] then
    local aligned = (p % 2 == 0)
    msg(string.format("  %d/%d  (canales %d+%d)%s", p, p + 1, p + 1, p + 2,
      aligned and "  [alineado]" or ""))
    if aligned and not secondary then secondary = p end
  end
end

msg("\n== Par secundario resuelto ==")
if secondary then
  msg(string.format("  I_DSTCHAN=%d -> salidas %d/%d (base 1)", secondary, secondary + 1, secondary + 2))
else
  msg("  NINGUNO disponible (la UI debe avisar, nunca caer al master)")
end