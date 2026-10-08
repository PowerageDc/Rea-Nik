local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local L = dofile(script_dir .. "../MusicState/MusicStateLyrics_common_logic.lua")

local function plan(events, t1, t2)
  local end_time = t2 or t1
  return {
    t1 = t1, t2 = t2, has_sel = t2 ~= nil, end_time = end_time, events = events,
    at_start = L.EventsNear(events, t1),
    at_end = L.EventsNear(events, end_time),
    inside = t2 and L.EventsBetween(events, t1, t2) or {},
  }
end

local EV = {
  { time = 10, text = "Hola" },
  { time = 12, text = L.END_MARK },
  { time = 14, text = "Chau" },
  { time = 16, text = L.END_MARK },
}

local fails = 0
local function check(name, t1, t2, text, want)
  local got = L.DecideAdd(plan(EV, t1, t2), text)
  local ok = true
  for k, v in pairs(want) do
    if got[k] ~= v then ok = false end
  end
  if not ok then fails = fails + 1 end
  reaper.ShowConsoleMsg(string.format("%s %s -> kind=%s n=%s has_line=%s replaces_end=%s code=%s\n",
    ok and "PASS" or "FAIL", name, tostring(got.kind), tostring(got.n),
    tostring(got.has_line), tostring(got.replaces_end), tostring(got.code)))
end

reaper.ClearConsole()
check("1  libre",                 20, nil, "x", { kind = "apply" })
check("2  linea en t1",           10, nil, "x", { kind = "confirm_line", n = 0, has_line = true })
check("3  fin en t1",             12, nil, "x", { kind = "apply", replaces_end = true, has_line = false })
check("4a vacio, marcador libre", 20, nil, "",  { kind = "apply" })
check("4b vacio, linea en pos",   14, nil, "",  { kind = "reject", code = "end_occupied" })
check("4c vacio, fin en pos",     11, 12,  "",  { kind = "reject", code = "end_occupied" })
check("5  seleccion con eventos", 9,  13,  "x", { kind = "confirm_inside", n = 2, has_line = false })
check("6a toggle sobre linea",    10, 12,  "x", { kind = "confirm_line", n = 0, has_line = true })
check("6b toggle sobre 2a linea", 14, 16,  "x", { kind = "confirm_line", n = 0, has_line = true })
check("7  combinado",             10, 15,  "x", { kind = "confirm_inside", n = 2, has_line = true })
check("8  texto reservado",       20, nil, L.END_MARK, { kind = "reject", code = "reserved" })
reaper.ShowConsoleMsg(fails == 0 and "\nTodo OK\n" or ("\nFallos: " .. fails .. "\n"))