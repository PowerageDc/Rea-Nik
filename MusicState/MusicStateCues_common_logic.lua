-- MusicStateCues_common_logic.lua
-- Tab "Cues" de Nik_MusicState_Helper.lua (patron dofile + M={}).
-- Consumido solo por el Helper, no vive en _Shared/.
-- Los cues viven en H.cues (ver MusicStateCuesModel_common_logic.lua); la
-- tab solo guarda estado de interfaz en H._cues_ui.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Model = dofile(script_dir .. "MusicStateCuesModel_common_logic.lua")

local M = {}

local EXT_SECTION = 'NikMusicStateHelper'
local EXT_KEY_AUTOSELECT = 'cues_autoselect'
local COLOR_ACTIVE_EXACT = 0x3FBF3FA0
local COLOR_ACTIVE_CARRY = 0x3FBF3F40
local COLOR_SECTION_BG = 0x80808030
local COLOR_UNKNOWN_ROLE = 0xE06060FF
local SCROLL_RATIO = 0.35
local POS_COLUMN_W = 90
local DUR_COLUMN_W = 70
local ROLES_COLUMN_W = 150
local NO_FILTER_LABEL = '(sin filtro)'
-- Un cue cuenta como "recien empezado" si el cursor esta a menos de esto de
-- su inicio (QN).
local EXACT_QN = 0.01
-- Minimo de una seleccion de tiempo para usarla como inicio y duracion.
local MIN_RANGE_S = 0.02

local function getState(H)
  if not H._cues_ui then
    H._cues_ui = {
      proj = nil,
      sel_uid = nil,
      filter_role = nil,
      last_target = nil,
      scroll_target = nil,
      scroll_sel = false,
      autoselect = reaper.GetExtState(EXT_SECTION, EXT_KEY_AUTOSELECT) ~= '0',
    }
  end
  return H._cues_ui
end

local function findSectionIdx(sections, time)
  for s_idx = #sections, 1, -1 do
    if sections[s_idx].time <= time then return s_idx end
  end
  return nil
end

local function cueTime(cue)
  return reaper.TimeMap2_QNToTime(0, cue.qn)
end

local function clearTimeRange()
  reaper.GetSet_LoopTimeRange(true, false, 0, 0, false)
  reaper.UpdateArrange()
end

local function selectTimeRange(cue)
  reaper.GetSet_LoopTimeRange(true, false, cueTime(cue),
    reaper.TimeMap2_QNToTime(0, cue.qn + cue.dur_qn), false)
  reaper.UpdateArrange()
end

-- Click en una fila: la selecciona (o la deselecciona si ya lo estaba), mueve
-- el cursor a su inicio y, con el toggle, selecciona su rango de tiempo.
local function onRowClick(S, cue)
  local was_sel = S.sel_uid == cue.uid
  S.sel_uid = (not was_sel) and cue.uid or nil
  reaper.SetEditCurPos(cueTime(cue), true, false)
  if not S.autoselect then return end
  if was_sel then clearTimeRange() else selectTimeRange(cue) end
end

local function deselectRow(S)
  S.sel_uid = nil
  if S.autoselect then clearTimeRange() end
end

-- Alta en el cursor, o en la seleccion de tiempo si la hay (inicio y
-- duracion salen de ella). Dirigido al rol filtrado, o a todos.
local function addCue(S, H)
  local s, e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local qn, dur
  if e - s > MIN_RANGE_S then
    qn = reaper.TimeMap2_timeToQN(0, s)
    dur = reaper.TimeMap2_timeToQN(0, e) - qn
  else
    qn = reaper.TimeMap2_timeToQN(0, reaper.GetCursorPosition())
  end
  local roles = S.filter_role and { S.filter_role } or { Model.ALL_ROLE }
  local cue = Model.newCue(qn, dur, roles, '')
  Model.insert(H.cues, cue)
  S.sel_uid = cue.uid
  S.scroll_sel = true
end

local function listHasRole(list, role)
  for _, r in ipairs(list) do
    if r == role then return true end
  end
  return false
end

local function drawFilter(ctx, S, H)
  if S.filter_role and not listHasRole(H.roles, S.filter_role) then
    S.filter_role = nil
  end
  local no_roles = #H.roles == 0
  local preview = S.filter_role or (no_roles and '(sin roles)' or NO_FILTER_LABEL)
  reaper.ImGui_BeginDisabled(ctx, no_roles)
  reaper.ImGui_SetNextItemWidth(ctx, 160)
  if reaper.ImGui_BeginCombo(ctx, 'Ver##cues_filter', preview) then
    if reaper.ImGui_Selectable(ctx, NO_FILTER_LABEL .. '##cues_all', S.filter_role == nil) then
      S.filter_role = nil
    end
    for _, r in ipairs(H.roles) do
      if reaper.ImGui_Selectable(ctx, r .. '##role_' .. r, S.filter_role == r) then
        S.filter_role = r
      end
    end
    reaper.ImGui_EndCombo(ctx)
  end
  reaper.ImGui_EndDisabled(ctx)
end

-- Mismas columnas para el header y el body: no se pueden desalinear. La
-- ultima es la que se estira, asi las fijas coinciden con y sin scrollbar.
local function setupColumns(ctx)
  local fixed = reaper.ImGui_TableColumnFlags_WidthFixed()
  reaper.ImGui_TableSetupColumn(ctx, 'Pos', fixed, POS_COLUMN_W)
  reaper.ImGui_TableSetupColumn(ctx, 'Dur.(QN)', fixed, DUR_COLUMN_W)
  reaper.ImGui_TableSetupColumn(ctx, 'Roles', fixed, ROLES_COLUMN_W)
  reaper.ImGui_TableSetupColumn(ctx, 'Texto', reaper.ImGui_TableColumnFlags_WidthStretch())
end

-- Los roles que no estan en la lista de Roles se marcan en rojo.
local function drawRoles(ctx, cue, known_roles)
  local label = table.concat(cue.roles, ', ')
  local unknown = Model.unknownRoles(cue, known_roles)
  if #unknown == 0 then
    reaper.ImGui_Text(ctx, label)
    return
  end
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), COLOR_UNKNOWN_ROLE)
  reaper.ImGui_Text(ctx, label)
  reaper.ImGui_PopStyleColor(ctx)
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx, 'No esta en la lista de Roles: ' .. table.concat(unknown, ', '))
  end
end

-- Escape en la tab: con una fila seleccionada la deselecciona; sin
-- seleccion devuelve false y el despacho cae a la accion global. Llamar una
-- vez despues de Keys.init.
function M.register_keys(Keys, H)
  Keys.add_tab('Cues', {
    { id = 'cues.escape', key = 'Escape', override = true,
      fn = function()
        local S = H._cues_ui
        if not S or not S.sel_uid then return false end
        deselectRow(S)
      end },
  })
end

function M.draw(ctx, H, helpers)
  local S = getState(H)

  if S.proj ~= H.last_proj then
    S.proj = H.last_proj
    S.sel_uid = nil
    S.filter_role = nil
    S.last_target = nil
  end
  if S.sel_uid and not Model.find(H.cues, S.sel_uid) then S.sel_uid = nil end

  local changed, value = reaper.ImGui_Checkbox(ctx, 'Seleccionar duracion al hacer click', S.autoselect)
  if changed then
    S.autoselect = value
    reaper.SetExtState(EXT_SECTION, EXT_KEY_AUTOSELECT, value and '1' or '0', true)
  end
  reaper.ImGui_SameLine(ctx)
  drawFilter(ctx, S, H)
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, '+ Cue en cursor##cue_add', 130, 0) then
    addCue(S, H)
  end

  local rows = Model.filtered(H.cues, S.filter_role)
  reaper.ImGui_SameLine(ctx)
  if S.filter_role then
    reaper.ImGui_TextDisabled(ctx, string.format('%d de %d cues', #rows, #H.cues))
  else
    reaper.ImGui_TextDisabled(ctx, string.format('%d cues', #H.cues))
  end
  reaper.ImGui_Spacing(ctx)

  -- Cues activos en la posicion de referencia (reproduccion o cursor). Puede
  -- haber varios. El scroll sigue al primero activo o, si no hay, al proximo.
  local playing = (reaper.GetPlayState() & 1) ~= 0
  local ref_time = playing and reaper.GetPlayPosition() or reaper.GetCursorPosition()
  local ref_qn = reaper.TimeMap2_timeToQN(0, ref_time)
  local active, target_uid = {}, nil
  for _, c in ipairs(Model.activeAt(rows, ref_qn)) do
    active[c.uid] = math.abs(c.qn - ref_qn) <= EXACT_QN
    target_uid = target_uid or c.uid
  end
  if not target_uid then
    for _, c in ipairs(rows) do
      if c.qn > ref_qn then
        target_uid = c.uid
        break
      end
    end
  end
  if target_uid ~= S.last_target then
    S.scroll_target = target_uid
    S.last_target = target_uid
  end

  if reaper.ImGui_BeginTable(ctx, 'cues_header', 4) then
    setupColumns(ctx)
    reaper.ImGui_TableHeadersRow(ctx)
    reaper.ImGui_EndTable(ctx)
  end

  local _, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
  local body_h = math.max(avail_h - helpers.getListFooterReserveH(), 60)
  local sections = helpers.getSections()
  local click_cue = nil

  local body_visible = reaper.ImGui_BeginChild(ctx, 'cues_body', 0, body_h, 0, reaper.ImGui_WindowFlags_NoNav())
  if body_visible then
    if #rows == 0 then
      reaper.ImGui_TextDisabled(ctx, #H.cues == 0
        and 'No hay cues. Agrega uno en el cursor o en la seleccion de tiempo.'
        or 'Ningun cue para ese rol.')
    elseif reaper.ImGui_BeginTable(ctx, 'cues_rows', 4) then
      setupColumns(ctx)
      local last_section = nil
      for _, cue in ipairs(rows) do
        local t = cueTime(cue)
        local s_idx = findSectionIdx(sections, t)
        if s_idx and s_idx ~= last_section then
          reaper.ImGui_TableNextRow(ctx)
          reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_RowBg0(), COLOR_SECTION_BG)
          for _ = 1, 4 do reaper.ImGui_TableNextColumn(ctx) end
          reaper.ImGui_Text(ctx, sections[s_idx].name)
        end
        last_section = s_idx

        reaper.ImGui_TableNextRow(ctx)
        reaper.ImGui_PushID(ctx, cue.uid)
        local exact = active[cue.uid]
        if exact ~= nil then
          reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_RowBg0(),
            exact and COLOR_ACTIVE_EXACT or COLOR_ACTIVE_CARRY)
        end

        reaper.ImGui_TableNextColumn(ctx)
        local clicked = reaper.ImGui_Selectable(ctx,
          reaper.format_timestr_pos(t, '', 2) .. '###cue', cue.uid == S.sel_uid,
          reaper.ImGui_SelectableFlags_SpanAllColumns())
        if clicked then click_cue = cue end

        reaper.ImGui_TableNextColumn(ctx)
        reaper.ImGui_Text(ctx, string.format('%.2f', cue.dur_qn))

        reaper.ImGui_TableNextColumn(ctx)
        drawRoles(ctx, cue, H.roles)

        reaper.ImGui_TableNextColumn(ctx)
        if cue.text == '' then
          reaper.ImGui_TextDisabled(ctx, '(sin texto)')
        else
          reaper.ImGui_Text(ctx, cue.text)
        end

        if S.scroll_target == cue.uid then
          reaper.ImGui_SetScrollHereY(ctx, SCROLL_RATIO)
          S.scroll_target = nil
        end
        if S.scroll_sel and cue.uid == S.sel_uid then
          reaper.ImGui_SetScrollHereY(ctx, SCROLL_RATIO)
          S.scroll_sel = false
        end
        reaper.ImGui_PopID(ctx)
      end
      reaper.ImGui_EndTable(ctx)
    end
  end
  reaper.ImGui_EndChild(ctx)

  S.scroll_target = nil
  S.scroll_sel = false

  if click_cue then onRowClick(S, click_cue) end
end

return M