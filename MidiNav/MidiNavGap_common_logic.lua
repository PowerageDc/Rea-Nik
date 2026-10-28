local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "MidiNav_config.lua")
local Common = dofile(script_dir .. "MidiNav_common_logic.lua")
local G = Config.gap
local N = Config.notes

local M = {}

local function distance(n, p)
    if p < n.s then return n.s - p end
    if p > n.e then return p - n.e end
    return 0
end

local function nearest_index(notes, p)
    local best, best_d
    for i, n in ipairs(notes) do
        local d = distance(n, p)
        local better
        if not best_d then
            better = true
        elseif G.tiebreak == "next" then
            better = d <= best_d + G.tie_tol_ppq
        else
            better = d < best_d - G.tie_tol_ppq
        end
        if better then best, best_d = i, d end
    end
    return best
end

local function chord_first(notes, i)
    local ref = notes[i].s
    while notes[i - 1] and notes[i - 1].s >= ref - N.chord_tol_ppq do
        i = i - 1
    end
    return i
end

local function chord_last(notes, i)
    while notes[i + 1] and notes[i + 1].s <= notes[i].s + N.chord_tol_ppq do
        i = i + 1
    end
    return i
end

local function chord_info(notes, i)
    local first, last = chord_first(notes, i), chord_last(notes, i)
    local max_end = notes[first].e
    for j = first, last do
        if notes[j].e > max_end then max_end = notes[j].e end
    end
    return first, last, max_end
end

local function target_next(notes, last, cur_end)
    local nxt = notes[last + 1]
    if not nxt then return nil end
    local gap = nxt.s - cur_end
    if gap > G.min_gap_ppq then return cur_end + gap * G.position end
    if G.no_gap_target == "current_end" then return cur_end end
    return nxt.s
end

local function target_prev(notes, first, cur_start)
    if first <= 1 then return nil end
    local _, _, prev_end = chord_info(notes, first - 1)
    local gap = cur_start - prev_end
    if gap > G.min_gap_ppq then return cur_start - gap * G.position end
    if G.no_gap_target_prev == "current_start" then return cur_start end
    return prev_end
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
    local target

    local sel_first, sel_last, sel_end
    for i, n in ipairs(notes) do
        if n.sel then
            sel_first = sel_first or i
            sel_last = i
            if not sel_end or n.e > sel_end then sel_end = n.e end
        end
    end

    local use_sel = sel_first ~= nil
    if use_sel then
        local ppq
        if forward then
            ppq = target_next(notes, chord_last(notes, sel_last), sel_end)
        else
            ppq = target_prev(notes, chord_first(notes, sel_first), notes[sel_first].s)
        end
        if ppq then
            local t = reaper.MIDI_GetProjTimeFromPPQPos(take, ppq)
            local reached = forward and pos >= t - G.same_pos_tol_sec
                or not forward and pos <= t + G.same_pos_tol_sec
            if G.selection_continue and reached then
                use_sel = false
            else
                target = t
            end
        end
    end
    if not use_sel then
        local idx = nearest_index(notes, reaper.MIDI_GetPPQPosFromProjTime(take, pos))
        for _ = 1, 2 do
            if not notes[idx] then target = nil break end
            local first, last, max_end = chord_info(notes, idx)
            local ppq
            if forward then
                ppq = target_next(notes, last, max_end)
            else
                ppq = target_prev(notes, first, notes[first].s)
            end
            if not ppq then target = nil break end
            target = reaper.MIDI_GetProjTimeFromPPQPos(take, ppq)
            if not G.repeat_advances or math.abs(target - pos) > G.same_pos_tol_sec then break end
            idx = forward and last + 1 or first - 1
        end
    end

    if target and math.abs(target - pos) > G.same_pos_tol_sec then
        Common.with_undo(
            forward and "Move edit cursor to middle of gap to next note"
                     or "Move edit cursor to middle of gap to previous note",
            function() Common.move_cursor(target) end)
    end
end

return M