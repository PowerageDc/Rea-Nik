-- ============================================================
-- Test aislado: ¿RENDER_STARTPOS negativo se clampea al escribir?
-- No toca nada del script principal. Correr una vez y mirar la
-- consola de Reaper.
-- ============================================================

reaper.ClearConsole()

reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 0, true) -- 0 = custom time bounds
reaper.GetSetProjectInfo(0, "RENDER_STARTPOS", -1.0, true)
reaper.GetSetProjectInfo(0, "RENDER_ENDPOS", 100.0, true)

local startReadBack = reaper.GetSetProjectInfo(0, "RENDER_STARTPOS", 0, false)
local endReadBack = reaper.GetSetProjectInfo(0, "RENDER_ENDPOS", 0, false)

reaper.ShowConsoleMsg("RENDER_STARTPOS escrito: -1.0\n")
reaper.ShowConsoleMsg("RENDER_STARTPOS leído de vuelta: " .. tostring(startReadBack) .. "\n")
reaper.ShowConsoleMsg("RENDER_ENDPOS leído de vuelta: " .. tostring(endReadBack) .. "\n")
reaper.ShowConsoleMsg("\nSi el primer valor es -1.0 (o cercano), la API SÍ guarda el negativo.\n")
reaper.ShowConsoleMsg("Si es 0.0, la API lo clampea al escribir.\n")
