local TEST = "pw_bezier"

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Core = dofile(script_dir .. "../VstiControl/VstiControl_common_logic.lua")

local cfg = {
  channel = 1,
  middle_c = 3,
  defaults = { ks_length = 60, ks_velocity = 100, ks_offset = 0, ramp_shape = "linear" },
}

local specs = {
  ks_seq = { label = "ks seq", type = "keyswitch", offset = -10, stagger = 5,
    steps = { { pitch = 24 }, { pitch = 26 } } },
  ks_one = { label = "ks one", type = "keyswitch", pitch = 24, offset = -2 },
  cc_point = { label = "cc point", type = "cc_point", cc = 1, value = 64 },
  cc_ramp = { label = "cc ramp", type = "cc_ramp", cc = 11, from = 0, to = 127, shape = "slow" },
  ks_name = { label = "ks name", type = "keyswitch", pitch = "C#0" },
  ks_range = { label = "ks range", type = "keyswitch", mode = "range", pitch = "C#0", offset = -10 },
  ks_notes = { label = "ks notes", type = "keyswitch", mode = "per_note", pitch = "C#0", offset = -10 },
  pw_point = { label = "pw point", type = "cc_point", cc = "pw", value = 4096 },
  pw_ramp = { label = "pw ramp", type = "cc_ramp", cc = "pw", from = 0, to = 4096, shape = "linear" },
  pw_bezier = { label = "pw bezier", type = "cc_ramp", cc = "pw", from = -8192, to = 0, shape = "bezier", tension = 0.6 },
}

local ok, msg = Core.exec(cfg, specs[TEST])
reaper.ShowConsoleMsg(tostring(ok) .. " | " .. msg .. "\n")