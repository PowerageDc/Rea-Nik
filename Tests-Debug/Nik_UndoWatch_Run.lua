-- Nik_UndoWatch_Run.lua (v2)
reaper.ClearConsole()
reaper.ShowConsoleMsg("=== Nik_UndoWatch_Run v2 iniciado ===\n")

local last_count = reaper.GetProjectStateChangeCount(0)
local last_desc  = reaper.Undo_CanUndo2(0)
reaper.ShowConsoleMsg(string.format("[%.2f] inicial -> count=%d desc=%s\n",
  os.clock(), last_count, tostring(last_desc)))

local function loop()
  local count = reaper.GetProjectStateChangeCount(0)
  if count ~= last_count then
    local desc = reaper.Undo_CanUndo2(0)
    reaper.ShowConsoleMsg(string.format("[%.2f] CAMBIO #%d -> count=%d desc=%s\n",
      os.clock(), count - last_count, count, tostring(desc)))
    last_count = count
    last_desc = desc
  end
  reaper.defer(loop)
end

loop()