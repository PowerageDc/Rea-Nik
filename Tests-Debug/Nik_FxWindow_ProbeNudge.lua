local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local FxWindow = dofile(script_dir .. "../FxWindow/FxWindow_common_logic.lua")
local config = FxWindow.load_config(script_dir .. "../FxWindow/")

local STEP_DELAY = 0.7

if not FxWindow.has_js_api() then
  reaper.ShowMessageBox("Falta JS_ReaScriptAPI (instalar desde ReaPack).", "FxWindow Probe", 0)
  return
end

local track = reaper.GetSelectedTrack(0, 0)
if not track then
  reaper.ShowMessageBox("Seleccioná el track con el VSTi.", "FxWindow Probe", 0)
  return
end

local fx_index, entry
for _, fx in ipairs(FxWindow.list_fx(track)) do
  local found = FxWindow.find_entry(config, fx.name)
  if found then fx_index, entry = fx.index, found; break end
end
if not fx_index then
  reaper.ShowMessageBox("Ningún FX del track coincide con el config.", "FxWindow Probe", 0)
  return
end

reaper.TrackFX_Show(track, fx_index, 3)
local hwnd = reaper.TrackFX_GetFloatingWindow(track, fx_index)
if not hwnd then return end

local f = FxWindow.measure(hwnd).frame
local x, y = entry.x - f.left, entry.y - f.top
local w = entry.w + f.left + f.right
local h = entry.h + f.top + f.bottom

local function set(dw, dh)
  reaper.JS_Window_SetPosition(hwnd, x, y, w + dw, h + dh)
end

local steps = {
  { name = "estado inicial", run = function() end },
  { name = "exacto", run = function() set(0, 0) end },
  { name = "encoger 200", run = function() set(-200, -200) end },
  { name = "exacto", run = function() set(0, 0) end },
  { name = "exacto + WM_EXITSIZEMOVE", run = function()
      set(0, 0)
      local ok, err = pcall(reaper.JS_WindowMessage_Send, hwnd, "WM_EXITSIZEMOVE", 0, 0, 0, 0)
      if not ok then reaper.ShowConsoleMsg("WM_EXITSIZEMOVE falló: " .. tostring(err) .. "\n") end
    end },
}

local function log_state(name)
  local m = FxWindow.measure(hwnd)
  local v = m.view
  reaper.ShowConsoleMsg(string.format(
    "%s: cliente %dx%d, vista %s\n",
    name, m.cli.w, m.cli.h, v and (v.w .. "x" .. v.h) or "no encontrada"))
end

reaper.ClearConsole()
local idx, due = 0, 0
local function loop()
  local now = reaper.time_precise()
  if now < due then reaper.defer(loop); return end
  if idx > 0 then log_state(steps[idx].name) end
  idx = idx + 1
  local step = steps[idx]
  if not step then return end
  step.run()
  due = now + STEP_DELAY
  reaper.defer(loop)
end
loop()