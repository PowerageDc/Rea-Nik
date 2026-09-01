-- Diagnóstico rápido: ¿existe GetProjectStateChunk en esta instalación?
reaper.ClearConsole()
reaper.ShowConsoleMsg("REAPER version: " .. reaper.GetAppVersion() .. "\n")
reaper.ShowConsoleMsg("APIExists('GetProjectStateChunk'): " .. tostring(reaper.APIExists("GetProjectStateChunk")) .. "\n")
reaper.ShowConsoleMsg("type(reaper.GetProjectStateChunk): " .. type(reaper.GetProjectStateChunk) .. "\n")

if reaper.APIExists("GetProjectStateChunk") then
  local ok, chunk = reaper.GetProjectStateChunk(0, "", false)
  reaper.ShowConsoleMsg("Llamada directa OK: " .. tostring(ok) .. ", largo del chunk: " .. tostring(chunk and #chunk or "nil") .. "\n")
end
