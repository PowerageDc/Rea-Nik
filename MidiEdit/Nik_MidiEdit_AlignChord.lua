local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "MidiEdit_config.lua")
local A = Config.align_chord

local editor = reaper.MIDIEditor_GetActive()
if not editor then return end
local take = reaper.MIDIEditor_GetTake(editor)
if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return end

local sel = {}
local min_s, min_e, max_e
local _, note_count = reaper.MIDI_CountEvts(take)
for i = 0, note_count - 1 do
    local _, selected, _, s, e = reaper.MIDI_GetNote(take, i)
    if selected then
        sel[#sel + 1] = { idx = i, s = s, e = e }
        if not min_s or s < min_s then min_s = s end
        if not min_e or e < min_e then min_e = e end
        if not max_e or e > max_e then max_e = e end
    end
end
if #sel == 0 then return end

local start_target
if A.starts == "earliest" then
    start_target = min_s
elseif A.starts == "cursor" then
    start_target = reaper.MIDI_GetPPQPosFromProjTime(take, reaper.GetCursorPosition())
end

local end_target
if A.ends == "latest" then
    end_target = max_e
elseif A.ends == "earliest" then
    end_target = min_e
end

local changes = {}
for _, n in ipairs(sel) do
    local ns = start_target or n.s
    local ne = end_target or n.e
    if ns < ne and (ns ~= n.s or ne ~= n.e) then
        changes[#changes + 1] = { idx = n.idx, s = ns, e = ne }
    end
end
if #changes == 0 then return end

if Config.undo.enabled then reaper.Undo_BeginBlock() end
for _, c in ipairs(changes) do
    reaper.MIDI_SetNote(take, c.idx, nil, nil, c.s, c.e, nil, nil, nil, true)
end
reaper.MIDI_Sort(take)
if Config.undo.enabled then reaper.Undo_EndBlock("Align selected notes", -1) end