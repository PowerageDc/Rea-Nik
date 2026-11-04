local TEST_LANE = 11

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

reaper.ShowConsoleMsg("---- sonda de lanes ----\n")

local item = reaper.GetMediaItemTake_Item(take)
local ok, chunk = reaper.GetItemStateChunk(item, "", false)
if ok then
    for line in chunk:gmatch("[^\r\n]+") do
        if line:match("^%s*VELLANE") then
            reaper.ShowConsoleMsg("chunk: " .. line .. "\n")
        elseif line:match("^%s*CFGEDIT ") then
            reaper.ShowConsoleMsg("chunk: " .. line:sub(1, 200) .. "\n")
        end
    end
else
    reaper.ShowConsoleMsg("GetItemStateChunk fallo\n")
end

local before = reaper.MIDIEditor_GetSetting_int(editor, "last_clicked_cc_lane")
local set_ok = reaper.MIDIEditor_SetSetting_int(editor, "last_clicked_cc_lane", TEST_LANE)
local after = reaper.MIDIEditor_GetSetting_int(editor, "last_clicked_cc_lane")
reaper.ShowConsoleMsg(("antes = %s | SetSetting devolvio %s | despues = %s\n")
    :format(tostring(before), tostring(set_ok), tostring(after)))