local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "MidiNav_config.lua")
local Common = dofile(script_dir .. "MidiNav_common_logic.lua")
local Cc = dofile(script_dir .. "MidiNavCc_common_logic.lua")
local R = Config.cc_range

local M = {}

function M.run(source)
    local editor = reaper.MIDIEditor_GetActive()
    if not editor then return end
    local take = reaper.MIDIEditor_GetTake(editor)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return end

    local function to_ppq(t) return reaper.MIDI_GetPPQPosFromProjTime(take, t) end

    local pos = reaper.GetCursorPosition()
    local tol = to_ppq(pos + R.tolerance_sec) - to_ppq(pos)

    local lo, hi
    if source == "time_selection" then
        local t0, t1 = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
        if t1 <= t0 then return end
        lo, hi = to_ppq(t0), to_ppq(t1)
    elseif source == "to_cursor" then
        lo, hi = -math.huge, to_ppq(pos)
    else
        lo, hi = to_ppq(pos), math.huge
    end

    local keep_fn = Cc.make_filter(editor, take, R.lane_mode)

    local hits, outside = {}, {}
    local _, _, cc_count = reaper.MIDI_CountEvts(take)
    for i = 0, cc_count - 1 do
        local _, sel, _, p, chanmsg, _, msg2 = reaper.MIDI_GetCC(take, i)
        if p >= lo - tol and p <= hi + tol and keep_fn(sel, chanmsg, msg2) then
            if not sel then hits[#hits + 1] = i end
            hits.found = true
        elseif sel then
            outside[#outside + 1] = i
        end
    end
    if not hits.found then return end
    if #hits == 0 and (R.mode ~= "replace" or #outside == 0) then return end

    Common.with_undo("Select CC events in range", function()
        if R.mode == "replace" then
            for _, i in ipairs(outside) do
                reaper.MIDI_SetCC(take, i, false, nil, nil, nil, nil, nil, nil, true)
            end
        end
        for _, i in ipairs(hits) do
            reaper.MIDI_SetCC(take, i, true, nil, nil, nil, nil, nil, nil, true)
        end
    end)
end

return M