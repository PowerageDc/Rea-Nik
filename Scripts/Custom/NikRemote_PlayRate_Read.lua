-- NikRemote_PlayRate_Read.lua
-- Reemplazar con el Command ID real (Actions List > buscar "preserve pitch")
local PRESERVEPITCH_CMD = 40671  -- <-- COMPLETAR

local playrate = reaper.Master_GetPlayRate(0)
local pct = math.floor((playrate * 100) + 0.5)
reaper.SetExtState("NikRemote", "playrate", tostring(pct), false)

local ppState = reaper.GetToggleCommandStateEx(0, PRESERVEPITCH_CMD)
reaper.SetExtState("NikRemote", "preservepitch", (ppState == 1) and "on" or "off", false)