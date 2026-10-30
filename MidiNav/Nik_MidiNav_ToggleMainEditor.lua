if not reaper.JS_Window_ArrayAllTop then
  reaper.MB("Falta la extensión js_ReaScriptAPI.", "Nik_MidiNav_ToggleMainEditor", 0)
  return
end

local OPEN_ITEM_IN_MIDI_EDITOR = 40153

local function is_midi_editor(hwnd)
  return hwnd ~= nil and reaper.MIDIEditor_GetMode(hwnd) ~= -1
end

local function find_midi_editor()
  local arr = reaper.new_array(1024)
  local count = reaper.JS_Window_ArrayAllTop(arr)
  for i = 1, count do
    local hwnd = reaper.JS_Window_HandleFromAddress(arr[i])
    if is_midi_editor(hwnd) then return hwnd end
  end
  return nil
end

local function focus(hwnd)
  reaper.JS_Window_SetForeground(hwnd)
  reaper.JS_Window_SetFocus(hwnd)
end

if is_midi_editor(reaper.JS_Window_GetForeground()) then
  focus(reaper.GetMainHwnd())
else
  local editor = find_midi_editor() or reaper.MIDIEditor_GetActive()
  if editor then
    focus(editor)
  else
    reaper.Main_OnCommand(OPEN_ITEM_IN_MIDI_EDITOR, 0)
  end
end