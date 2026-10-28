local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "MidiNav_config.lua")
local N = Config.notes

local M = {}

function M.collect_notes(editor, take)
    local filter_chan
    if N.channel_filter == "active" then
        filter_chan = reaper.MIDIEditor_GetSetting_int(editor, "default_note_chan")
    end
    local notes = {}
    local _, note_count = reaper.MIDI_CountEvts(take)
    for i = 0, note_count - 1 do
        local _, sel, muted, s, e, chan, pitch = reaper.MIDI_GetNote(take, i)
        local keep = (N.include_muted or not muted)
            and (filter_chan == nil or chan == filter_chan)
        if keep then
            notes[#notes + 1] = { idx = i, sel = sel, s = s, e = e, pitch = pitch }
        end
    end
    table.sort(notes, function(a, b) return a.s < b.s end)
    return notes
end

function M.move_cursor(target)
    reaper.SetEditCurPos(target, Config.move_view, Config.seek_play)
end

function M.with_undo(name, fn)
    if Config.undo.enabled then reaper.Undo_BeginBlock() end
    fn()
    if Config.undo.enabled then reaper.Undo_EndBlock(name, -1) end
end

return M