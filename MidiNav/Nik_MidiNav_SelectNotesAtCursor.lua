local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "MidiNav_config.lua")
local Common = dofile(script_dir .. "MidiNav_common_logic.lua")
local A = Config.at_cursor

local editor = reaper.MIDIEditor_GetActive()
if not editor then return end
local take = reaper.MIDIEditor_GetTake(editor)
if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return end

local notes = Common.collect_notes(editor, take)
if #notes == 0 then return end

local pos = reaper.GetCursorPosition()
local cursor_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, pos)
local start_limit = reaper.MIDI_GetPPQPosFromProjTime(take, pos + A.tolerance_sec)

local hits = {}
for _, n in ipairs(notes) do
    if n.s <= start_limit and n.e > cursor_ppq then
        hits[#hits + 1] = n
    end
end
if #hits == 0 then return end

local is_hit = {}
for _, n in ipairs(hits) do is_hit[n.idx] = true end

Common.with_undo("Select notes at edit cursor", function()
    if A.mode == "replace" then
        for _, n in ipairs(notes) do
            if n.sel and not is_hit[n.idx] then
                reaper.MIDI_SetNote(take, n.idx, false, nil, nil, nil, nil, nil, nil, true)
            end
        end
    end
    for _, n in ipairs(hits) do
        reaper.MIDI_SetNote(take, n.idx, true, nil, nil, nil, nil, nil, nil, true)
    end
end)