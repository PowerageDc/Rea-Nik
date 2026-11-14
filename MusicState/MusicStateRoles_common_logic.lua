-- MusicStateRoles_common_logic.lua
-- Tab "Roles" de Nik_MusicState_Helper.lua (patron dofile + M={}).
-- Consumido solo por el Helper, no vive en _Shared/.
-- Los roles del proyecto se tildan sobre el catalogo de
-- MusicStateRoles_config.lua; un rol fuera del catalogo es la excepcion.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "MusicStateRoles_config.lua")
local Model = dofile(script_dir .. "MusicStateCuesModel_common_logic.lua")

local M = {}

local ROLE_INPUT = { on_enter = 'commit', keep_focus = 'always' }

local HOVER_DISABLED = reaper.ImGui_HoveredFlags_AllowWhenDisabled
  and reaper.ImGui_HoveredFlags_AllowWhenDisabled() or 0

local in_catalog = {}
for _, e in ipairs(Config.catalog) do in_catalog[e.id] = true end

-- Roles con los que arranca un proyecto sin roles guardados.
function M.defaultRoles()
  local out = {}
  for _, e in ipairs(Config.catalog) do
    if e.default then out[#out + 1] = e.id end
  end
  return out
end

local function countCues(H, role)
  local n = 0
  for _, c in ipairs(H.cues) do
    if Model.hasRole(c, role) then n = n + 1 end
  end
  return n
end

-- H.roles = los roles de `enabled` (set id -> true): primero los del
-- catalogo en su orden, despues los sueltos en el orden que tenian.
local function rebuild(H, enabled)
  local out = {}
  for _, e in ipairs(Config.catalog) do
    if enabled[e.id] then out[#out + 1] = e.id end
  end
  for _, r in ipairs(H.roles) do
    if enabled[r] and not in_catalog[r] then out[#out + 1] = r end
  end
  H.roles = out
end

-- Un rol con cues no se puede destildar ni quitar: primero hay que
-- reasignar o borrar esos cues.
local function drawInUseTooltip(ctx, n)
  if reaper.ImGui_IsItemHovered(ctx, HOVER_DISABLED) then
    reaper.ImGui_SetTooltip(ctx,
      string.format('%d cue(s) usan este rol: reasignalos o borralos antes.', n))
  end
end

function M.draw(ctx, H, helpers)
  reaper.ImGui_Text(ctx, 'Roles de este proyecto:')
  reaper.ImGui_TextDisabled(ctx, '("todos" es implicito. El catalogo se edita en MusicStateRoles_config.lua)')
  reaper.ImGui_Spacing(ctx)

  local enabled = {}
  for _, r in ipairs(H.roles) do enabled[r] = true end

  local toggled = nil
  for _, e in ipairs(Config.catalog) do
    local on = enabled[e.id] == true
    local used = on and countCues(H, e.id) or 0
    reaper.ImGui_BeginDisabled(ctx, used > 0)
    local changed, value = reaper.ImGui_Checkbox(ctx, e.id .. '##cat_' .. e.id, on)
    reaper.ImGui_EndDisabled(ctx)
    if used > 0 then
      drawInUseTooltip(ctx, used)
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_TextDisabled(ctx, string.format('(%d cues)', used))
    end
    if changed then toggled = { id = e.id, on = value } end
  end
  if toggled then
    enabled[toggled.id] = toggled.on or nil
    rebuild(H, enabled)
  end

  local loose = {}
  for _, r in ipairs(H.roles) do
    if not in_catalog[r] then loose[#loose + 1] = r end
  end
  if #loose > 0 then
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextDisabled(ctx, 'Fuera del catalogo:')
    local remove = nil
    for i, r in ipairs(loose) do
      local used = countCues(H, r)
      reaper.ImGui_Text(ctx, r)
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_BeginDisabled(ctx, used > 0)
      if helpers.ButtonStyle.button(ctx, 'Quitar##loose' .. i, 'danger') then
        remove = r
      end
      reaper.ImGui_EndDisabled(ctx)
      if used > 0 then
        drawInUseTooltip(ctx, used)
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextDisabled(ctx, string.format('(%d cues)', used))
      end
    end
    if remove then
      enabled[remove] = nil
      rebuild(H, enabled)
    end
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_TextDisabled(ctx, 'Rol fuera del catalogo (excepcional):')
  local _, new_buf, enter_commit = helpers.Keys.input(ctx, 'Nuevo rol', H.new_role_buf, ROLE_INPUT)
  H.new_role_buf = new_buf

  reaper.ImGui_SameLine(ctx)
  local add_clicked = helpers.ButtonStyle.button(ctx, 'Agregar', 'primary', 80)

  if enter_commit or add_clicked then
    local name = H.new_role_buf:match('^%s*(.-)%s*$')
    if name ~= '' and name ~= Model.ALL_ROLE and not enabled[name] then
      if in_catalog[name] then
        enabled[name] = true
        rebuild(H, enabled)
      else
        table.insert(H.roles, name)
      end
    end
    H.new_role_buf = ''
  end
end

return M