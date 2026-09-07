local proj = 0

reaper.SetProjExtState(proj, "NSAUDIOMUSIC", "test_key", "valor_proyecto")
reaper.SetExtState("NikRemote", "test_key", "valor_global", false)

reaper.ShowConsoleMsg("Escrito:\n")
reaper.ShowConsoleMsg("  ProjExtState  NSAUDIOMUSIC/test_key = valor_proyecto\n")
reaper.ShowConsoleMsg("  ExtState      NikRemote/test_key    = valor_global\n")
reaper.ShowConsoleMsg("\nAhora probá desde el browser/JS ambos endpoints y compará.\n")