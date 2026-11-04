local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "MidiEdit_config.lua")

local M = {}

function M.run(anchor)
    local editor = reaper.MIDIEditor_GetActive()
    if not editor then return end
    local take = reaper.MIDIEditor_GetTake(editor)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return end

    local cursor_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjTime(take, reaper.GetCursorPosition()) + 0.5)

    local sel = {}
    local min_p, max_p
    local i = reaper.MIDI_EnumSelCC(take, -1)
    while i ~= -1 do
        local _, _, _, p = reaper.MIDI_GetCC(take, i)
        sel[#sel + 1] = { idx = i, p = p }
        if not min_p or p < min_p then min_p = p end
        if not max_p or p > max_p then max_p = p end
        i = reaper.MIDI_EnumSelCC(take, i)
    end
    if #sel == 0 then return end

    local ref = anchor == "last" and max_p or min_p
    local delta = cursor_ppq - ref
    if delta == 0 then return end
    if min_p + delta < 0 then return end

    if Config.undo.enabled then reaper.Undo_BeginBlock() end
    for _, e in ipairs(sel) do
        reaper.MIDI_SetCC(take, e.idx, nil, nil, e.p + delta, nil, nil, nil, nil, true)
    end
    reaper.MIDI_Sort(take)
    if Config.undo.enabled then
        reaper.Undo_EndBlock(
            anchor == "last" and "Move selected CC events end to edit cursor"
                              or "Move selected CC events to edit cursor", -1)
    end
end

return M