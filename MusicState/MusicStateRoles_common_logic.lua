-- MusicStateRoles_common_logic.lua
-- Tab "Roles" de Nik_MusicState_Helper.lua -- ver 01_CONVENCIONES.md,
-- patron dofile + M={}. Consumido solo por el Helper, no vive en _Shared/.

local M = {}

local ROLE_INPUT = { on_enter = 'commit', keep_focus = 'always' }

function M.draw(ctx, H, helpers)
  reaper.ImGui_Text(ctx, 'Roles configurados para este proyecto:')
  reaper.ImGui_TextDisabled(ctx, '("todos" es implicito, no se lista aca)')
  reaper.ImGui_Spacing(ctx)

  local remove_idx = nil
  for i, role in ipairs(H.roles) do
    reaper.ImGui_Text(ctx, role)
    reaper.ImGui_SameLine(ctx)
    if helpers.ButtonStyle.button(ctx, 'Quitar##role' .. i, 'danger') then
      remove_idx = i
    end
  end
  if remove_idx then
    table.remove(H.roles, remove_idx)
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  local _, new_buf, enter_commit = helpers.Keys.input(ctx, 'Nuevo rol', H.new_role_buf, ROLE_INPUT)
  H.new_role_buf = new_buf

  reaper.ImGui_SameLine(ctx)
  local add_clicked = helpers.ButtonStyle.button(ctx, 'Agregar', 'primary', 80)

  if (enter_commit or add_clicked) and H.new_role_buf ~= '' then
    table.insert(H.roles, H.new_role_buf)
    H.new_role_buf = ''
  end
end

return M