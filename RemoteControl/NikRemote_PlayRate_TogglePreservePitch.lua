-- @description Nik RemoteControl — PlayRate Toggle Preserve Pitch
-- @version 1.0
-- @author Nik
-- NikRemote_PlayRate_TogglePreservePitch.lua
-- Mismo Command ID que en el script de lectura
local PRESERVEPITCH_CMD = 40671  -- <-- COMPLETAR
reaper.Main_OnCommand(PRESERVEPITCH_CMD, 0)