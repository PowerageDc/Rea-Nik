local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "MidiNav_config.lua")
local Common = dofile(script_dir .. "MidiNav_common_logic.lua")
local S = Config.select
local N = Config.notes

local M = {}

local function better(rule, a, b)
    if rule == "lowest" then return a.pitch < b.pitch end
    return a.pitch > b.pitch
end

local function pick_next(notes, limit_ppq)
    local first
    for i, n in ipairs(notes) do
        if n.s > limit_ppq then first = i break end
    end
    if not first then return nil end
    local pick = notes[first]
    local j = first + 1
    while notes[j] and notes[j].s <= notes[first].s + N.chord_tol_ppq do
        if better(S.chord_pick_next, notes[j], pick) then pick = notes[j] end
        j = j + 1
    end
    return pick
end

local function pick_prev(notes, limit_ppq)
    local last
    for i = #notes, 1, -1 do
        if notes[i].s < limit_ppq then last = i break end
    end
    if not last then return nil end
    local pick = notes[last]
    local j = last - 1
    while notes[j] and notes[j].s >= notes[last].s - N.chord_tol_ppq do
        if better(S.chord_pick_prev, notes[j], pick) then pick = notes[j] end
        j = j - 1
    end
    return pick
end

function M.run(direction)
    local forward = direction ~= "prev"

    local editor = reaper.MIDIEditor_GetActive()
    if not editor then return end
    local take = reaper.MIDIEditor_GetTake(editor)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return end

    local notes = Common.collect_notes(editor, take)
    if #notes == 0 then return end

    local pos = reaper.GetCursorPosition()
    local pick
    if forward then
        pick = pick_next(notes, reaper.MIDI_GetPPQPosFromProjTime(take, pos + S.threshold_sec))
    else
        pick = pick_prev(notes, reaper.MIDI_GetPPQPosFromProjTime(take, pos - S.threshold_sec))
    end
    if not pick then return end

    Common.with_undo(
        forward and "Select next note from edit cursor"
                 or "Select previous note from edit cursor",
        function()
            if S.mode == "replace" then
                for _, n in ipairs(notes) do
                    if n.sel then
                        reaper.MIDI_SetNote(take, n.idx, false, nil, nil, nil, nil, nil, nil, true)
                    end
                end
            end
            reaper.MIDI_SetNote(take, pick.idx, true, nil, nil, nil, nil, nil, nil, true)
            if S.move_cursor == "start" then
                Common.move_cursor(reaper.MIDI_GetProjTimeFromPPQPos(take, pick.s))
            end
        end)
end

return M