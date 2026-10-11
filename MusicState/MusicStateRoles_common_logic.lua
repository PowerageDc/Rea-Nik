-- MusicStateRoles_common_logic.lua
-- Tab "Roles" de Nik_MusicState_Helper.lua -- ver 01_CONVENCIONES.md,
-- patron dofile + M={}. Consumido solo por el Helper, no vive en _Shared/.

local M = {}

-- false | 'when_empty' | 'always' (perfil previsto en musicstate_keys.md 9.4)
local KEEP_FOCUS = 'always'

function M.draw(ctx, H, helpers)
  reaper.ImGui_Text(ctx, 'Roles configurados para este proyecto:')
  reaper.ImGui_TextDisabled(ctx, '("todos" es implicito, no se lista aca)')
  reaper.ImGui_Spacing(ctx)

  local remove_idx = nil
  for i, role in ipairs(H.roles) do
    reaper.ImGui_Text(ctx, role)
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Quitar##role' .. i) then
      remove_idx = i
    end
  end
  if remove_idx then
    table.remove(H.roles, remove_idx)
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  local changed
  changed, H.new_role_buf = reaper.ImGui_InputText(ctx, 'Nuevo rol', H.new_role_buf)
  local enter_commit, enter_key = helpers.InputCommit.resolveEnterCommit(ctx)
  local enter_rep = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter(), true)
    or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter(), true)
  local enter_ended = enter_rep and reaper.ImGui_IsItemDeactivated(ctx)
  if enter_commit or enter_ended then helpers.Keys.consume('Enter') end
  if enter_ended and (KEEP_FOCUS == 'always'
      or (KEEP_FOCUS == 'when_empty' and H.new_role_buf == '')) then
    reaper.ImGui_SetKeyboardFocusHere(ctx, -1)
  end

  reaper.ImGui_SameLine(ctx)
  local add_clicked = reaper.ImGui_Button(ctx, 'Agregar', 80, 0)

  if (enter_commit or add_clicked) and H.new_role_buf ~= '' then
    table.insert(H.roles, H.new_role_buf)
    H.new_role_buf = ''
  end
end

return M