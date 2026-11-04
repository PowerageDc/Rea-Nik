local editor = reaper.MIDIEditor_GetActive()
if not editor then
    reaper.ShowConsoleMsg("Sin MIDI Editor activo\n")
    return
end
local take = reaper.MIDIEditor_GetTake(editor)
if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then
    reaper.ShowConsoleMsg("Sin take valido\n")
    return
end

local lane = reaper.MIDIEditor_GetSetting_int(editor, "last_clicked_cc_lane")
reaper.ShowConsoleMsg(("last_clicked_cc_lane = %s\n"):format(tostring(lane)))

local counts = {}
local _, _, cc_count = reaper.MIDI_CountEvts(take)
for i = 0, cc_count - 1 do
    local _, _, _, _, chanmsg, _, msg2 = reaper.MIDI_GetCC(take, i)
    local key = chanmsg == 0xB0 and ("CC " .. msg2) or ("chanmsg 0x" .. string.format("%X", chanmsg))
    counts[key] = (counts[key] or 0) + 1
end
for k, v in pairs(counts) do
    reaper.ShowConsoleMsg(("  %s: %d eventos\n"):format(k, v))
end