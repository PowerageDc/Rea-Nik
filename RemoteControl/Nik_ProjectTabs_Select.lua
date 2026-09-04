-- Nik_ProjectTabs_Select.lua
-- Switchea a la tab de proyecto indicada por el remoto (tap en el popup).
-- Lee el índice destino (mismo orden de EnumProjects que arma
-- ProjectTabs_common_logic) desde ExtState "project_tabs_target_idx",
-- escrita por el HTML justo antes de disparar este comando
-- (patrón SET/EXTSTATE + _RS, igual que Playrate/ReaPitch).
-- Registrar en el Action List y completar PROJECTTABS_CMD_SELECT en el HTML.

local target = tonumber(reaper.GetExtState("NikRemote", "project_tabs_target_idx"))
if target then
    local proj = reaper.EnumProjects(target)
    if proj then
        reaper.Main_OnCommand(40667, 0) -- Transport: Stop, save all recorded media
        reaper.SelectProjectInstance(proj)
        end
    end
