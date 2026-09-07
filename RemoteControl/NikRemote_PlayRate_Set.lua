-- NikRemote_PlayRate_Set.lua
local target = tonumber(reaper.GetExtState("NikRemote", "playrate_target"))
if target then
    local rate = target / 100
    if rate < 0.4 then rate = 0.4 end
    if rate > 1.5 then rate = 1.5 end
    reaper.CSurf_OnPlayRateChange(rate)
    end
