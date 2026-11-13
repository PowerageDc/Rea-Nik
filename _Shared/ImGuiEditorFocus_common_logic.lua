-- ImGuiEditorFocus_common_logic.lua
-- Devuelve el foco del teclado a una ventana (por ejemplo un MIDI Editor)
-- tras interactuar con un panel ReaImGui, salvo mientras haya un item activo
-- o un popup abierto (slider en edicion, combo desplegado). new(ctx, getHwnd)
-- devuelve una funcion tick() para llamar cada frame dentro de Begin/End.
-- Patron dofile + M={}.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local HostFocus = dofile(script_dir .. "ImGuiHostFocus_common_logic.lua")

local M = {}

function M.new(ctx, getHwnd)
  local was_active = false

  return function()
    local active = reaper.ImGui_IsAnyItemActive(ctx)
    local popup = reaper.ImGui_IsPopupOpen(ctx, "", reaper.ImGui_PopupFlags_AnyPopupId())
    local focused = reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_ChildWindows())
    local hovered = reaper.ImGui_IsWindowHovered(ctx, reaper.ImGui_HoveredFlags_ChildWindows())
    local released = was_active and not active
    local left = focused and not hovered
    was_active = active
    if active or popup then return end
    if released or left then
      HostFocus.toHwnd(getHwnd())
    end
  end
end

return M