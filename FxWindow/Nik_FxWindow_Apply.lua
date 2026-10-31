local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local FxWindow = dofile(script_dir .. "FxWindow_common_logic.lua")

local function log(msg)
  reaper.ShowConsoleMsg(msg .. "\n")
end

if not FxWindow.has_js_api() then
  reaper.ShowMessageBox("Falta JS_ReaScriptAPI (instalar desde ReaPack).", "FxWindow", 0)
  return
end

local sel_count = reaper.CountSelectedTracks(0)
if sel_count == 0 then
  reaper.ShowMessageBox("Seleccioná al menos un track.", "FxWindow", 0)
  return
end

local config = FxWindow.load_config(script_dir)
reaper.ClearConsole()

local INIT_DELAY = 0.7
local VERIFY_DELAY = 0.6
local MAX_RETRIES = 2
local SHRINK = 200

local pending = {}
local start = reaper.time_precise()

for t = 0, sel_count - 1 do
  local track = reaper.GetSelectedTrack(0, t)
  local _, track_name = reaper.GetTrackName(track)
  local instrument = reaper.TrackFX_GetInstrument(track)
  local instrument_matched = false

  for _, fx in ipairs(FxWindow.list_fx(track)) do
    local entry = FxWindow.find_entry(config, fx.name)
    if entry then
      if fx.index == instrument then instrument_matched = true end
      reaper.TrackFX_Show(track, fx.index, 3)
      local hwnd = reaper.TrackFX_GetFloatingWindow(track, fx.index)
      if hwnd then
        pending[#pending + 1] = {
          label = string.format("[%s] %s", track_name, fx.name),
          hwnd = hwnd,
          entry = entry,
          step = "apply",
          due = start + INIT_DELAY,
          attempts = 0,
        }
      else
        log(string.format("[%s] %s: sin ventana flotante", track_name, fx.name))
      end
    end
  end

  if instrument >= 0 and not instrument_matched then
    local _, name = reaper.TrackFX_GetFXName(track, instrument, "")
    log(string.format("[%s] %s: sin entrada en el config", track_name, name))
  end
end

local steps = {}

function steps.apply(p, at)
  FxWindow.apply(p.hwnd, p.entry)
  p.step, p.due = "verify", at + VERIFY_DELAY
end

function steps.verify(p, at)
  local diff = FxWindow.differences(FxWindow.measure(p.hwnd), p.entry)
  if not diff then
    local extra = p.attempts > 0 and string.format(" (tras %d reintento/s)", p.attempts) or ""
    log(p.label .. ": OK" .. extra)
    p.done = true
  elseif p.attempts >= MAX_RETRIES then
    log(p.label .. ": DIFIERE (" .. diff .. ")")
    p.done = true
  else
    p.attempts = p.attempts + 1
    FxWindow.apply(p.hwnd, p.entry, SHRINK)
    p.step, p.due = "apply", at + VERIFY_DELAY
  end
end

local function loop()
  local at = reaper.time_precise()
  local remaining = 0
  for _, p in ipairs(pending) do
    if not p.done then
      if at >= p.due then steps[p.step](p, at) end
      if not p.done then remaining = remaining + 1 end
    end
  end
  if remaining > 0 then reaper.defer(loop) end
end

if #pending > 0 then loop() end