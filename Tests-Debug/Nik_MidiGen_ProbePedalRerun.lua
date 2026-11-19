local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "../MidiGen/MidiGen_config.lua")
local Pedal = dofile(script_dir .. "../MidiGen/MidiGenPedal_common_logic.lua")
local Cc = dofile(script_dir .. "../MidiGen/MidiGenCc_common_logic.lua")

local function say(s) reaper.ShowConsoleMsg(s .. "\n") end

local editor = reaper.MIDIEditor_GetActive()
if not editor then say("Sin MIDI Editor abierto") return end
local take = reaper.MIDIEditor_GetTake(editor)
if not take then say("Sin take") return end

local function params(name)
  local p, err = Pedal.resolve(Config, name)
  if not p then say("resolve: " .. tostring(err)) return nil end
  p.mode = "replace"
  return p
end

local function dump(list)
  local out = {}
  for _, ev in ipairs(list) do out[#out + 1] = ev.ppq .. "=" .. ev.msg3 end
  return table.concat(out, " ")
end

local function check(label, p, n, data)
  if not n or type(data) ~= "table" then say(label .. ": FAIL " .. tostring(data)) return end
  local expected = Pedal.plan(take, p, Pedal.read_input(take, editor))
  local info = Cc.lane_info(64)
  local actual = Cc.read_range(take, info, data.chan, data.ppq0, data.ppq1)
  local ok = dump(expected) == dump(actual)
  say(string.format("%s: %s (%d eventos, can_rerun=%s)", label, ok and "OK" or "FAIL", n,
    tostring(Pedal.can_rerun(take))))
  if not ok then
    say("  esperado: " .. dump(expected))
    say("  actual:   " .. dump(actual))
  end
end

local a, b = params("Legato"), params("Medio pedal")
if not a or not b then return end

local n, data = Pedal.apply(editor, a)
check("1 apply Legato", a, n, data)
n, data = Pedal.rerun(take, b)
check("2 rerun Medio pedal", b, n, data)
n, data = Pedal.rerun(take, a)
check("3 rerun Legato", a, n, data)
say("Hecho: son 3 bloques de undo (Ctrl+Z tres veces para volver al original).")