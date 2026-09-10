-- Nik_MusicState_ProbeExtState.lua
-- Lee directo ProjExtState (NSAUDIOMUSIC) y el ExtState global puenteado
-- (NikMusicState), sin pasar por el parser del Helper -- verificacion
-- independiente de lo que efectivamente quedo guardado/publicado.
-- Correr una vez desde el Action List, mirar la consola (Ctrl+Shift+... /
-- ventana "ReaScript console output" abierta automaticamente por
-- ShowConsoleMsg).

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Bridge = dofile(script_dir .. "../_Shared/MusicStateBridge_common_logic.lua")

local GLOBAL_NAMESPACE = "NikMusicState"  -- ver IMPL_MusicState.md 11.2
local KEYS = { "project_key", "project_roles", "harmony_data", "cues_data" }

reaper.ClearConsole()

local proj = 0
for _, key in ipairs(KEYS) do
  local ok_proj, val_proj = reaper.GetProjExtState(proj, Bridge.NAMESPACE, key)
  local val_bridge = reaper.GetExtState(GLOBAL_NAMESPACE, key)

  reaper.ShowConsoleMsg(string.format("== %s ==\n", key))
  reaper.ShowConsoleMsg(string.format("  ProjExtState (ok=%s): %s\n", tostring(ok_proj > 0), val_proj))
  reaper.ShowConsoleMsg(string.format("  ExtState global      : %s\n", val_bridge))
  reaper.ShowConsoleMsg(string.format("  contiene \\n literal   : %s\n", tostring(val_bridge:find("\n") ~= nil)))
  reaper.ShowConsoleMsg(string.format("  proj == bridge        : %s\n", tostring(val_proj == val_bridge)))
  reaper.ShowConsoleMsg("\n")
end