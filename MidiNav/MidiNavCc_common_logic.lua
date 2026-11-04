local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "MidiNav_config.lua")
local Common = dofile(script_dir .. "MidiNav_common_logic.lua")
local C = Config.cc

local M = {}

local function lane_matches(lane, chanmsg, msg2)
    if lane >= 0 and lane < 128 then
        return chanmsg == 0xB0 and msg2 == lane
    end
    if lane >= 256 and lane < 288 then
        local n = lane - 256
        return chanmsg == 0xB0 and (msg2 == n or msg2 == n + 32)
    end
    if lane == 513 then return chanmsg == 0xE0 end
    if lane == 514 then return chanmsg == 0xC0 end
    if lane == 515 then return chanmsg == 0xD0 end
    return false
end

local function visible_lanes(take)
    local lanes = {}
    local item = reaper.GetMediaItemTake_Item(take)
    local ok, chunk = reaper.GetItemStateChunk(item, "", false)
    if not ok then return lanes end
    for code in chunk:gmatch("\n%s*VELLANE%s+(%d+)") do
        local n = tonumber(code)
        if n == 128 then n = 513 end
        lanes[#lanes + 1] = n
    end
    return lanes
end

function M.make_filter(editor, take, mode)
    mode = mode or C.lane_mode
    local active_lane = reaper.MIDIEditor_GetSetting_int(editor, "last_clicked_cc_lane")
    local visible = mode == "visible" and visible_lanes(take) or {}
    return function(sel, chanmsg, msg2)
        if mode == "all" then return true end
        if mode == "selected" then return sel end
        if mode == "visible" then
            for _, l in ipairs(visible) do
                if lane_matches(l, chanmsg, msg2) then return true end
            end
            return false
        end
        return lane_matches(active_lane, chanmsg, msg2)
    end
end

function M.run(direction)
    local forward = direction ~= "prev"

    local editor = reaper.MIDIEditor_GetActive()
    if not editor then return end
    local take = reaper.MIDIEditor_GetTake(editor)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return end

    local keep_fn = M.make_filter(editor, take)
    local pos = reaper.GetCursorPosition()
    local limit
    if forward then
        limit = reaper.MIDI_GetPPQPosFromProjTime(take, pos + C.threshold_sec)
    else
        limit = reaper.MIDI_GetPPQPosFromProjTime(take, pos - C.threshold_sec)
    end

    local best
    local _, _, cc_count = reaper.MIDI_CountEvts(take)
    for i = 0, cc_count - 1 do
        local _, sel, _, p, chanmsg, _, msg2 = reaper.MIDI_GetCC(take, i)
        local keep = keep_fn(sel, chanmsg, msg2)
        if keep then
            if forward then
                if p > limit and (not best or p < best) then best = p end
            else
                if p < limit and (not best or p > best) then best = p end
            end
        end
    end
    if not best then return end

    Common.with_undo(
        forward and "Move cursor to next CC event"
                 or "Move cursor to previous CC event",
        function()
            Common.move_cursor(reaper.MIDI_GetProjTimeFromPPQPos(take, best))
        end)
end

return M