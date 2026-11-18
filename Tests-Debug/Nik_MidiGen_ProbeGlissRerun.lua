local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "../MidiGen/MidiGen_config.lua")
local Gliss = dofile(script_dir .. "../MidiGen/MidiGenGliss_common_logic.lua")

local STEP_SEC = 1.5

local editor = reaper.MIDIEditor_GetActive()
if not editor then return end
local take = reaper.MIDIEditor_GetTake(editor)

-- accion, preset y modo de cada paso: aplica y rehace sobre la misma sesion
local STEPS = {
  { "apply", "Pulgar", "merge" },
  { "rerun", "Palma", "merge" },
  { "rerun", "Negras", "merge" },
  { "rerun", "Pulgar", "replace" },
}

local i = 0
local t_next = reaper.time_precise()

local function tick()
  if reaper.time_precise() >= t_next then
    i = i + 1
    local s = STEPS[i]
    if not s then return end
    local p = Gliss.resolve(Config, s[2])
    p.mode = s[3]
    local n, info
    if s[1] == "apply" then
      n, info = Gliss.apply(editor, p)
    else
      n, info = Gliss.rerun(take, p)
    end
    reaper.ShowConsoleMsg(string.format("%d. %s %s %s -> %s (%s)\n",
      i, s[1], s[2], s[3], tostring(n), type(info) == "string" and info or "ok"))
    t_next = reaper.time_precise() + STEP_SEC
  end
  reaper.defer(tick)
end

reaper.defer(tick)
