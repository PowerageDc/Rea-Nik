local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "../MidiGen/MidiGen_config.lua")
local Pedal = dofile(script_dir .. "../MidiGen/MidiGenPedal_common_logic.lua")

local PRESET = "Legato"
local LIFT_FIRST = true

local function say(s) reaper.ShowConsoleMsg(s .. "\n") end

local p, err = Pedal.resolve(Config, PRESET)
if not p then say("resolve: " .. tostring(err)) return end
p.lift_first = LIFT_FIRST

local editor = reaper.MIDIEditor_GetActive()
if not editor then say("Sin MIDI Editor abierto") return end
local take = reaper.MIDIEditor_GetTake(editor)
if not take then say("Sin take") return end

local events, data = Pedal.plan(take, p, Pedal.read_input(take, editor))
if not events or type(data) ~= "table" then say("plan: " .. tostring(data)) return end

say(string.format("%s | %s | ataques %d, puntos %d, cambios %d, eventos %d",
  PRESET, data.source, #data.attacks, #data.points, data.changes, #events))
for _, ev in ipairs(events) do
  say(string.format("%9.3f s  ppq %-7d CC64=%-3d shape %d",
    reaper.MIDI_GetProjTimeFromPPQPos(take, ev.ppq), ev.ppq, ev.msg3, ev.shape))
end