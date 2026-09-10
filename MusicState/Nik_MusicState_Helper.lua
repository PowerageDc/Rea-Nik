-- Nik_MusicState_Helper.lua
-- Panel nativo ReaImGui para cargar metadata musical (harmony, key, roles, cues)
-- en ProjExtState sin editar el script de publish a mano.
-- Paso 3: + extraccion de bridge reusable, + boton "Guardar y Publicar"
-- (Tonalidad y Roles unicamente -- Armonia y Cues en los proximos pasos).

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Bridge = dofile(script_dir .. "../_Shared/MusicStateBridge_common_logic.lua")
local InputCommit = dofile(script_dir .. "../_Shared/ImGuiInputCommit_common_logic.lua")
local RowInputs = dofile(script_dir .. "../_Shared/MusicStateRowInputs_common_logic.lua")

local ctx = reaper.ImGui_CreateContext('MusicState Helper', 0)    -- Context creation, config_flags=0 para desactivar Nav
local font = reaper.ImGui_CreateFont('sans-serif', 16)
reaper.ImGui_Attach(ctx, font)

local H = {
  key = { tonic_idx = 4, mode_idx = 0 },  -- tonic_idx 4 = "C" (ver TONICS abajo)
  roles = {},
  new_role_buf = '',
  harmony = {},  -- array de {measure, beat, hundredths, chord}; chord == '' -> sentinel null
  save_status = '',
  last_proj = nil,  -- detecta cambio de project tab, ver loop()
}

local TONICS = { 'A', 'A#', 'Bb', 'B', 'C', 'C#', 'Db', 'D', 'D#', 'Eb', 'E', 'F', 'F#', 'Gb', 'G', 'G#', 'Ab' }
local TONICS_STR = table.concat(TONICS, '\0') .. '\0'
local MODES = { 'major', 'minor' }
local MODES_STR = 'major\0minor\0'

local CMD_MEASURE_PREV = 41041
local CMD_MEASURE_NEXT = 41040
local CMD_MARKER_PREV  = 40172
local CMD_MARKER_NEXT  = 40173
local CMD_PLAYSTOP     = 40044
local CMD_PLAYPAUSE    = 40073

local KEY_MEASURE_PREV = reaper.ImGui_Key_LeftArrow()
local KEY_MEASURE_NEXT = reaper.ImGui_Key_RightArrow()
local KEY_MARKER_PREV  = reaper.ImGui_Key_DownArrow()
local KEY_MARKER_NEXT  = reaper.ImGui_Key_UpArrow()

-- Duracion de un beat en QN para el compas dado (depende del denominador,
-- ver IMPL_MusicState.md seccion 4.2/13.3). measure es 1-indexed;
-- TimeMap_GetMeasureInfo espera 0-indexed, de ahi el -1.
local function nikMusicStateBeatUnitQN(proj, measure)
  local _, _, _, _, timesig_denom = reaper.TimeMap_GetMeasureInfo(proj, measure - 1)
  return 4 / timesig_denom
end

-- qn_offset (desde el downbeat del compas) -> beat.hundredths para mostrar
-- en la tabla. Inverso de nikMusicStateBeatToQnOffset.
local function nikMusicStateQnOffsetToBeat(qn_offset, beat_unit_qn)
  local beat_index = math.floor(qn_offset / beat_unit_qn) + 1
  local remainder_qn = qn_offset - (beat_index - 1) * beat_unit_qn
  local hundredths = math.floor((remainder_qn / beat_unit_qn) * 100 + 0.5)
  return beat_index, hundredths
end

-- beat.hundredths -> qn_offset, redondeado a la grilla de 0.25 (resolucion
-- de semicorchea, cerrado en IMPL_MusicState.md seccion 4.2). Inverso de
-- nikMusicStateQnOffsetToBeat.
local function nikMusicStateBeatToQnOffset(beat, hundredths, beat_unit_qn)
  local qn_offset = beat_unit_qn * (beat - 1 + hundredths / 100)
  return math.floor(qn_offset / 0.25 + 0.5) * 0.25
end

-- Recarga H desde ProjExtState del proyecto dado. Se usa al abrir el panel
-- y cada vez que se detecta un cambio de project tab (ver loop()).
-- Parseo manual (sin libreria JSON): formatos de project_key/project_roles
-- son simples a proposito, ver IMPL_MusicState.md seccion 4.2/10.2/11.1.
local function nikMusicStateLoadFromProjExtState(proj)
  local ok_key, key_json = reaper.GetProjExtState(proj, Bridge.NAMESPACE, 'project_key')
  if ok_key > 0 and key_json ~= '' then
    local tonic = key_json:match('"tonic"%s*:%s*"([^"]*)"')
    local mode = key_json:match('"mode"%s*:%s*"([^"]*)"')
    if tonic then
      for i, t in ipairs(TONICS) do
        if t == tonic then H.key.tonic_idx = i - 1 end
      end
    end
    if mode then
      for i, m in ipairs(MODES) do
        if m == mode then H.key.mode_idx = i - 1 end
      end
    end
  end

  local ok_roles, roles_json = reaper.GetProjExtState(proj, Bridge.NAMESPACE, 'project_roles')
  if ok_roles > 0 and roles_json ~= '' then
    local roles = {}
    for role in roles_json:gmatch('"([^"]*)"') do
      table.insert(roles, role)
    end
    H.roles = roles
  else
    H.roles = {}
  end

  local ok_harmony, harmony_json = reaper.GetProjExtState(proj, Bridge.NAMESPACE, 'harmony_data')
  H.harmony = {}
  if ok_harmony > 0 and harmony_json ~= '' then
    for measure_str, events_str in harmony_json:gmatch('"(%d+)"%s*:%s*%[(.-)%]') do
      local measure = tonumber(measure_str)
      local beat_unit_qn = nikMusicStateBeatUnitQN(proj, measure)
      for qn_str, chord_str in events_str:gmatch('"qn_offset"%s*:%s*([%d%.]+).-"chord"%s*:%s*"?([^",}]*)"?') do
        local qn_offset = tonumber(qn_str) or 0
        local beat, hundredths = nikMusicStateQnOffsetToBeat(qn_offset, beat_unit_qn)
        table.insert(H.harmony, {
          measure = measure,
          beat = beat,
          hundredths = hundredths,
          chord = (chord_str == 'null') and '' or chord_str,
        })
      end
    end
  end

  -- cues_data: parseo pendiente, se suma en el proximo paso.
end

local function nikMusicStateCaptureCursorPosition()
  local proj = 0
  local cursor_time = reaper.GetCursorPosition()
  local qn = reaper.TimeMap2_timeToQN(proj, cursor_time)
  local measure, qn_start = reaper.TimeMap_QNToMeasures(proj, qn)
  local _, _, _, timesig_num, timesig_denom = reaper.TimeMap_GetMeasureInfo(proj, measure - 1)

  local qn_offset = qn - qn_start
  local beat_unit_qn = 4 / timesig_denom
  local beat_index = math.floor(qn_offset / beat_unit_qn) + 1
  local remainder_qn = qn_offset - (beat_index - 1) * beat_unit_qn
  local hundredths = math.floor((remainder_qn / beat_unit_qn) * 100 + 0.5)

  return {
    measure = measure,
    qn_offset = qn_offset,
    beat = beat_index,
    hundredths = hundredths,
    timesig_num = timesig_num,
    timesig_denom = timesig_denom,
  }
end

-- Arma los JSON compactos y los escribe en ProjExtState + puente a ExtState.
local function nikMusicStateSaveAndPublish()
  local proj = 0

  local key_json = string.format('{"tonic":"%s","mode":"%s"}',
    TONICS[H.key.tonic_idx + 1], MODES[H.key.mode_idx + 1])

  local roles_parts = {}
  for _, r in ipairs(H.roles) do
    table.insert(roles_parts, string.format('"%s"', r))
  end
  local roles_json = '[' .. table.concat(roles_parts, ',') .. ']'

  -- Agrupa H.harmony (array plano) por compas, convierte beat/hundredths a
  -- qn_offset, y arma el JSON keyed (formato cerrado, IMPL seccion 4.2).
  -- Acorde vacio ('') se escribe como null (sentinel de silencio explicito).
  local by_measure = {}
  for _, row in ipairs(H.harmony) do
    local beat_unit_qn = nikMusicStateBeatUnitQN(proj, row.measure)
    local qn_offset = nikMusicStateBeatToQnOffset(row.beat, row.hundredths, beat_unit_qn)
    local chord_json = (row.chord == '') and 'null' or string.format('"%s"', row.chord)
    local event_json = string.format('{"qn_offset":%.4g,"chord":%s}', qn_offset, chord_json)
    by_measure[row.measure] = by_measure[row.measure] or {}
    table.insert(by_measure[row.measure], { qn_offset = qn_offset, json = event_json })
  end

  local measure_parts = {}
  for measure, events in pairs(by_measure) do
    table.sort(events, function(a, b) return a.qn_offset < b.qn_offset end)
    local event_jsons = {}
    for _, e in ipairs(events) do table.insert(event_jsons, e.json) end
    table.insert(measure_parts, { measure = measure,
      json = string.format('"%d":[%s]', measure, table.concat(event_jsons, ',')) })
  end
  table.sort(measure_parts, function(a, b) return a.measure < b.measure end)
  local measure_jsons = {}
  for _, m in ipairs(measure_parts) do table.insert(measure_jsons, m.json) end
  local harmony_json = '{' .. table.concat(measure_jsons, ',') .. '}'

  reaper.SetProjExtState(proj, Bridge.NAMESPACE, 'project_key', key_json)
  reaper.SetProjExtState(proj, Bridge.NAMESPACE, 'project_roles', roles_json)
  reaper.SetProjExtState(proj, Bridge.NAMESPACE, 'harmony_data', harmony_json)
  -- cues_data: sin tocar todavia (tab pendiente, proximo paso).
  -- Nota: esto NO pisa esa key -- SetProjExtState es por-key, no reemplaza el namespace entero.

  local ok_key = Bridge.bridgeKey(proj, 'project_key')
  local ok_roles = Bridge.bridgeKey(proj, 'project_roles')
  local ok_harmony = Bridge.bridgeKey(proj, 'harmony_data')

  if ok_key and ok_roles and ok_harmony then
    H.save_status = 'Guardado OK.'
  else
    H.save_status = 'Error al publicar (ver consola).'
  end
end

local function drawTonalidadTab()
  local changed
  changed, H.key.tonic_idx = reaper.ImGui_Combo(ctx, 'Tonica', H.key.tonic_idx, TONICS_STR)
  changed, H.key.mode_idx = reaper.ImGui_Combo(ctx, 'Modo', H.key.mode_idx, MODES_STR)
end

local function drawRolesTab()
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
  local enter_commit, enter_key = InputCommit.resolveEnterCommit(ctx)
  if enter_commit then H.consumed_enter = true end

  reaper.ImGui_SameLine(ctx)
  local add_clicked = reaper.ImGui_Button(ctx, 'Agregar', 80, 0)

  if (enter_commit or add_clicked) and H.new_role_buf ~= '' then
    table.insert(H.roles, H.new_role_buf)
    H.new_role_buf = ''
  end
end

local function drawArmoniaTab()
  reaper.ImGui_TextDisabled(ctx, '(acorde vacio = silencio explicito / sentinel "null")')
  reaper.ImGui_Spacing(ctx)

  local remove_idx = nil

  if reaper.ImGui_BeginTable(ctx, 'harmony_table', 6, reaper.ImGui_TableFlags_SizingFixedFit()) then
    reaper.ImGui_TableSetupColumn(ctx, 'Compas')
    reaper.ImGui_TableSetupColumn(ctx, 'Beat')
    reaper.ImGui_TableSetupColumn(ctx, 'Cent.')
    reaper.ImGui_TableSetupColumn(ctx, 'Acorde')
    reaper.ImGui_TableSetupColumn(ctx, '')
    reaper.ImGui_TableSetupColumn(ctx, '')
    reaper.ImGui_TableHeadersRow(ctx)

    for i, row in ipairs(H.harmony) do
      reaper.ImGui_TableNextRow(ctx)
      reaper.ImGui_PushID(ctx, i)

      RowInputs.drawPositionInputs(ctx, row)

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, 100)
      local changed_c
      changed_c, row.chord = reaper.ImGui_InputText(ctx, '##acorde', row.chord)

      reaper.ImGui_TableNextColumn(ctx)
      if RowInputs.drawCursorButton(ctx) then
        RowInputs.applyCursorToRow(row, nikMusicStateCaptureCursorPosition())
      end

      reaper.ImGui_TableNextColumn(ctx)
      if reaper.ImGui_Button(ctx, 'Borrar') then
        remove_idx = i
      end

      reaper.ImGui_PopID(ctx)
    end

    reaper.ImGui_EndTable(ctx)
  end

  if remove_idx then
    table.remove(H.harmony, remove_idx)
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  if reaper.ImGui_Button(ctx, '+ Agregar fila (cursor actual)', 220, 0) then
    local pos = nikMusicStateCaptureCursorPosition()
    table.insert(H.harmony, {
      measure = pos.measure,
      beat = pos.beat,
      hundredths = pos.hundredths,
      chord = '',
    })
  end
end

local function loop()
  H.consumed_enter = false

  local current_proj = reaper.EnumProjects(-1)
  if current_proj ~= H.last_proj then
    nikMusicStateLoadFromProjExtState(current_proj)
    H.last_proj = current_proj
    H.save_status = 'Proyecto activo cambio -- datos recargados.'
  end

  reaper.ImGui_SetNextWindowSize(ctx, 520, 440, reaper.ImGui_Cond_FirstUseEver())
  reaper.ImGui_PushFont(ctx, font, 16)
  local visible, open = reaper.ImGui_Begin(ctx, 'MusicState Helper', true, reaper.ImGui_WindowFlags_NoNav())

  if visible then
    local pos = nikMusicStateCaptureCursorPosition()

    reaper.ImGui_Text(ctx, string.format(
      'Cursor: Compas %d, Beat %d.%02d  (comp. %d/%d)',
      pos.measure, pos.beat, pos.hundredths,
      pos.timesig_num, pos.timesig_denom
    ))

    reaper.ImGui_Separator(ctx)

    if InputCommit.globalKeyPressed(ctx, reaper.ImGui_Key_Space(), false) then
      reaper.Main_OnCommand(CMD_PLAYSTOP, 0)
    end
    if InputCommit.globalKeyPressed(ctx, reaper.ImGui_Key_Enter(), H.consumed_enter) then
      reaper.Main_OnCommand(CMD_PLAYPAUSE, 0)
    end
    if InputCommit.globalKeyPressed(ctx, KEY_MEASURE_PREV, false) then
      reaper.Main_OnCommand(CMD_MEASURE_PREV, 0)
    end
    if InputCommit.globalKeyPressed(ctx, KEY_MEASURE_NEXT, false) then
      reaper.Main_OnCommand(CMD_MEASURE_NEXT, 0)
    end
    if InputCommit.globalKeyPressed(ctx, KEY_MARKER_PREV, false) then
      reaper.Main_OnCommand(CMD_MARKER_PREV, 0)
    end
    if InputCommit.globalKeyPressed(ctx, KEY_MARKER_NEXT, false) then
      reaper.Main_OnCommand(CMD_MARKER_NEXT, 0)
    end

    if reaper.ImGui_BeginTabBar(ctx, 'MusicStateTabs') then
      if reaper.ImGui_BeginTabItem(ctx, 'Tonalidad') then
        drawTonalidadTab()
        reaper.ImGui_EndTabItem(ctx)
      end
      if reaper.ImGui_BeginTabItem(ctx, 'Roles') then
        drawRolesTab()
        reaper.ImGui_EndTabItem(ctx)
      end
      if reaper.ImGui_BeginTabItem(ctx, 'Armonia') then
        drawArmoniaTab()
        reaper.ImGui_EndTabItem(ctx)
      end
      if reaper.ImGui_BeginTabItem(ctx, 'Cues') then
        reaper.ImGui_TextDisabled(ctx, '(proximo paso)')
        reaper.ImGui_EndTabItem(ctx)
      end
      reaper.ImGui_EndTabBar(ctx)
    end

    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_Button(ctx, 'Guardar y Publicar', 180, 0) then
      nikMusicStateSaveAndPublish()
    end
    if H.save_status ~= '' then
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx, H.save_status)
    end

    reaper.ImGui_End(ctx)
  end

  reaper.ImGui_PopFont(ctx)

  if open then
    reaper.defer(loop)
  end
end

reaper.defer(loop)