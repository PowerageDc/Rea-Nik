local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "MidiEdit_config.lua")
local Strum = dofile(script_dir .. "MidiEditStrum_common_logic.lua")

local editor = reaper.MIDIEditor_GetActive()
if not editor then return end
local take = reaper.MIDIEditor_GetTake(editor)
if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return end

local params, err = Strum.load(Config)
if not params then
    reaper.ShowConsoleMsg("[MidiEdit Strum] " .. err .. "\n")
    return
end

Strum.run(take, params)