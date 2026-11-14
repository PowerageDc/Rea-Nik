-- MusicStateCuesEdit_common_logic.lua
-- Panel de edicion del cue seleccionado de la tab Cues. Consumido solo por
-- la tab. Estado en S.edit (S = H._cues_ui). Todo cambio pasa por las
-- operaciones de MusicStateCuesModel_common_logic.lua.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Model = dofile(script_dir .. "MusicStateCuesModel_common_logic.lua")

local M = {}

local STEPS = { -100, -20, 20, 100 }
-- Minimo de una seleccion de tiempo para usarla como duracion.
local MIN_RANGE_S = 0.02
-- El nombre de este flag depende de la version de ReaImGui.
local no_close_fn = reaper.ImGui_SelectableFlags_NoAutoClosePopups
  or reaper.ImGui_SelectableFlags_DontClosePopups
local NO_CLOSE_FLAG = no_close_fn and no_close_fn() or 0

local function getEd(S)
  if not S.edit then
    S.edit = { key_uid = nil, buf = '', orig = '', active = false, msg = ' ' }
  end
  return S.edit
end

local function qnToTime(qn) return reaper.TimeMap2_QNToTime(0, qn) end
local function timeToQn(t) return reaper.TimeMap2_timeToQN(0, t) end

local function posStr(cue)
  return reaper.format_timestr_pos(qnToTime(cue.qn), '', 2)
end

-- Mueve el inicio conservando la duracion. Si hay toggle de seleccion de
-- tiempo, el rango sigue al cue.
local function moveStart(S, Ed, H, cue, new_time, tools)
  local qn = timeToQn(new_time)
  Model.move(H.cues, cue.uid, qn)
  S.scroll_sel = true
  if S.autoselect then tools.selectTimeRange(cue) end
  Ed.msg = qn <= 0 and 'Movido al inicio del proyecto.' or ('Movido a ' .. posStr(cue))
end

local function setDur(S, Ed, H, cue, dur_qn, tools, follow_range)
  Model.setDuration(H.cues, cue.uid, dur_qn)
  if follow_range and S.autoselect then tools.selectTimeRange(cue) end
  Ed.msg = string.format('Duracion: %.2f QN', cue.dur_qn)
end

-- Fila de botones de nudge en ms. on_nudge(d, cue) solo se llama con cue.
local function nudgeRow(ctx, id, label, cue, on_nudge)
  reaper.ImGui_Text(ctx, label)
  reaper.ImGui_SameLine(ctx, 60)
  for _, d in ipairs(STEPS) do
    if reaper.ImGui_Button(ctx, string.format('%+d##%s%d', d, id, d), 48, 0) and cue then
      on_nudge(d, cue)
    end
    reaper.ImGui_SameLine(ctx)
  end
end

-- Opciones del selector: 'todos', los roles del proyecto y los roles del
-- cue que ya no estan en la lista (para poder quitarlos).
local function drawRoleOptions(ctx, H, cue)
  local opts, seen = { Model.ALL_ROLE }, { [Model.ALL_ROLE] = true }
  for _, r in ipairs(H.roles) do
    if not seen[r] then
      seen[r] = true
      opts[#opts + 1] = r
    end
  end
  local is_unknown = {}
  for _, r in ipairs(Model.unknownRoles(cue, H.roles)) do
    is_unknown[r] = true
    if not seen[r] then
      seen[r] = true
      opts[#opts + 1] = r
    end
  end
  for _, r in ipairs(opts) do
    local label = (is_unknown[r] and (r .. ' (no esta en Roles)') or r) .. '##role_' .. r
    if reaper.ImGui_Selectable(ctx, label, Model.hasRole(cue, r), NO_CLOSE_FLAG) then
      Model.setRoles(H.cues, cue.uid, Model.toggledRoles(cue.roles, r))
    end
  end
end

-- tools: { selectTimeRange(cue), clearTimeRange() } de la tab.
function M.draw(ctx, S, H, helpers, tools)
  local Ed = getEd(S)
  local cue = S.sel_uid and Model.find(H.cues, S.sel_uid) or nil

  -- Borrador: se recarga solo con el campo inactivo, si cambio el cue
  -- seleccionado o su texto (edicion externa).
  if cue and not Ed.active then
    if Ed.key_uid ~= cue.uid or Ed.orig ~= cue.text then
      if Ed.key_uid ~= cue.uid then Ed.msg = ' ' end
      Ed.key_uid, Ed.buf, Ed.orig = cue.uid, cue.text, cue.text
    end
  end

  if cue then
    reaper.ImGui_Text(ctx, string.format('Cue en %s  (%.2f QN)', posStr(cue), cue.dur_qn))
  else
    reaper.ImGui_TextDisabled(ctx, 'Selecciona un cue de la lista para editarlo.')
  end

  -- Commit al perder el foco (Enter, Tab o click afuera). Usa la clave del
  -- borrador, no la seleccion actual: el click en otra fila desactiva el
  -- campo antes de que la seleccion cambie.
  reaper.ImGui_BeginDisabled(ctx, not cue)
  reaper.ImGui_SetNextItemWidth(ctx, -1)
  if S.focus_text and cue then
    reaper.ImGui_SetKeyboardFocusHere(ctx)
    S.focus_text = false
  end
  local changed, v = reaper.ImGui_InputTextWithHint(ctx, '##cue_text', 'Texto del cue', Ed.buf)
  if changed then Ed.buf = v end
  local deact = reaper.ImGui_IsItemDeactivatedAfterEdit(ctx)
  Ed.active = reaper.ImGui_IsItemActive(ctx)
  reaper.ImGui_EndDisabled(ctx)
  if deact and Ed.key_uid then
    local text = helpers.Lyrics.CleanText(Ed.buf)
    if text ~= Ed.orig then
      if Model.setText(H.cues, Ed.key_uid, text) then
        Ed.orig = text
        Ed.msg = 'Texto actualizado.'
      else
        Ed.msg = 'El cue ya no existe.'
      end
    end
    Ed.buf = Ed.orig
  end

  reaper.ImGui_BeginDisabled(ctx, not cue)

  reaper.ImGui_Text(ctx, 'Roles')
  reaper.ImGui_SameLine(ctx, 60)
  reaper.ImGui_SetNextItemWidth(ctx, 240)
  if reaper.ImGui_BeginCombo(ctx, '##cue_roles', cue and table.concat(cue.roles, ', ') or '') then
    if cue then drawRoleOptions(ctx, H, cue) end
    reaper.ImGui_EndCombo(ctx)
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, 'Ir al inicio##cue_goto', 100, 0) and cue then
    reaper.SetEditCurPos(qnToTime(cue.qn), true, false)
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, 'Borrar cue##cue_del', 100, 0) and cue then
    Model.delete(H.cues, cue.uid)
    S.sel_uid = nil
    if S.autoselect then tools.clearTimeRange() end
    Ed.msg = 'Cue borrado.'
  end

  -- Posicion: nudge en ms y "Al cursor". La duracion se conserva.
  nudgeRow(ctx, 'start', 'Inicio', cue, function(d, c)
    moveStart(S, Ed, H, c, qnToTime(c.qn) + d / 1000, tools)
  end)
  if reaper.ImGui_Button(ctx, 'Al cursor##cue_start_cur', 90, 0) and cue then
    moveStart(S, Ed, H, cue, reaper.GetCursorPosition(), tools)
  end

  -- Duracion: el nudge mueve el fin del cue.
  nudgeRow(ctx, 'dur', 'Dur.', cue, function(d, c)
    local end_t = qnToTime(c.qn + c.dur_qn) + d / 1000
    setDur(S, Ed, H, c, timeToQn(end_t) - c.qn, tools, true)
  end)
  if reaper.ImGui_Button(ctx, 'Fin al cursor##cue_end_cur', 100, 0) and cue then
    local end_qn = timeToQn(reaper.GetCursorPosition())
    if end_qn <= cue.qn then
      Ed.msg = 'El cursor esta antes del inicio del cue.'
    else
      setDur(S, Ed, H, cue, end_qn - cue.qn, tools, true)
    end
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, 'Dur. = seleccion##cue_dur_sel', 130, 0) and cue then
    local s, e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if e - s <= MIN_RANGE_S then
      Ed.msg = 'No hay seleccion de tiempo.'
    else
      setDur(S, Ed, H, cue, timeToQn(e) - timeToQn(s), tools, false)
    end
  end

  reaper.ImGui_EndDisabled(ctx)

  -- Linea de aviso siempre reservada: si aparece y desaparece, el layout se
  -- corre y se pierde el click.
  reaper.ImGui_TextDisabled(ctx, Ed.msg)
  S.focus_text = false
end

return M