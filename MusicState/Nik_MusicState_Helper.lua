-- @description Nik MusicState — Suite completa (metadata musical + publish)
-- @version 1.0
-- @author Nik
-- @metapackage
-- @provides
--   [main] Nik_MusicState_PublishAll.lua
--   ../_Shared/ImGuiInputCommit_common_logic.lua
--   ../_Shared/MusicStateBridge_common_logic.lua
--   ../_Shared/MusicStateRowInputs_common_logic.lua
--   MusicStateTonalidad_common_logic.lua
--   MusicStateRoles_common_logic.lua
--   MusicStateArmonia_common_logic.lua
--   MusicStateCues_common_logic.lua
-- @about
--   Panel nativo ReaImGui para cargar y publicar metadata musical
--   (tonalidad, roles, armonia, cues) en ProjExtState, mas el script
--   que puentea esos datos a ExtState global para que la UI web de
--   instrumentista los consuma.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Bridge = dofile(script_dir .. "../_Shared/MusicStateBridge_common_logic.lua")
local InputCommit = dofile(script_dir .. "../_Shared/ImGuiInputCommit_common_logic.lua")
local RowInputs = dofile(script_dir .. "../_Shared/MusicStateRowInputs_common_logic.lua")
local Tonalidad = dofile(script_dir .. "MusicStateTonalidad_common_logic.lua")
local Roles = dofile(script_dir .. "MusicStateRoles_common_logic.lua")
local Armonia = dofile(script_dir .. "MusicStateArmonia_common_logic.lua")
local Cues = dofile(script_dir .. "MusicStateCues_common_logic.lua")

local ctx = reaper.ImGui_CreateContext('MusicState Helper', 0)    -- Context creation, config_flags=0 para desactivar Nav
local font = reaper.ImGui_CreateFont('sans-serif', 16)
reaper.ImGui_Attach(ctx, font)

local H = {
  key = { tonic_idx = 4, mode_idx = 0 },  -- tonic_idx 4 = "C" (ver TONICS abajo)
  roles = {},
  new_role_buf = '',
  harmony = {},  -- array de {measure, beat, hundredths, chord}; chord == '' -> sentinel null
  cues = {},  -- array de {measure, beat, hundredths, roles_str, text, duration_qn}
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

-- timesig_num del compas dado -- maximo valido para el campo Beat de una
-- fila (Armonia/Cues), ver MusicStateRowInputs_common_logic.lua. measure
-- 1-indexed, TimeMap_GetMeasureInfo espera 0-indexed, igual que arriba.
local function nikMusicStateTimesigNum(proj, measure)
  local _, _, _, timesig_num = reaper.TimeMap_GetMeasureInfo(proj, measure - 1)
  return timesig_num
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

  local ok_ver, ver_str = reaper.GetProjExtState(proj, Bridge.NAMESPACE, 'publish_version')
  H.publish_version = (ok_ver > 0 and tonumber(ver_str)) or 0

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

  -- cues_data: formato con array anidado (roles) dentro de cada evento --
  -- el regex simple de harmony_data (no-greedy hasta el primer "]") no
  -- alcanza aca, se rompe con el "]" de roles. Se usa %b[]/%b{} (balance
  -- nativo de Lua) para el array por compas y para cada objeto.
  local ok_cues, cues_json = reaper.GetProjExtState(proj, Bridge.NAMESPACE, 'cues_data')
  H.cues = {}
  if ok_cues > 0 and cues_json ~= '' then
    local search_pos = 1
    while true do
      local s, bracket_pos, measure_str = cues_json:find('"(%d+)"%s*:%s*%[', search_pos)
      if not s then break end
      local array_str = cues_json:match('%b[]', bracket_pos)
      if not array_str then break end
      local measure = tonumber(measure_str)
      local beat_unit_qn = nikMusicStateBeatUnitQN(proj, measure)
      local inner = array_str:sub(2, -2)
      local obj_pos = 1
      while true do
        local obj_start = inner:find('{', obj_pos)
        if not obj_start then break end
        local obj_str = inner:match('%b{}', obj_start)
        if not obj_str then break end
        local qn_str = obj_str:match('"qn_offset"%s*:%s*([%d%.]+)')
        local roles_block = obj_str:match('"roles"%s*:%s*%[(.-)%]')
        local text = obj_str:match('"text"%s*:%s*"([^"]*)"')
        local dur_str = obj_str:match('"duration_qn"%s*:%s*([%d%.]+)')
        local qn_offset = tonumber(qn_str) or 0
        local beat, hundredths = nikMusicStateQnOffsetToBeat(qn_offset, beat_unit_qn)
        local roles_list = {}
        if roles_block then
          for r in roles_block:gmatch('"([^"]*)"') do table.insert(roles_list, r) end
        end
        table.insert(H.cues, {
          measure = measure,
          beat = beat,
          hundredths = hundredths,
          roles_str = table.concat(roles_list, ','),
          text = text or '',
          duration_qn = tonumber(dur_str) or 0,
        })
        obj_pos = obj_start + #obj_str
      end
      search_pos = bracket_pos + #array_str
    end
  end
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

-- Convierte measure/beat/hundredths de una fila (Armonia/Cues) a tiempo de
-- proyecto absoluto. Separado de nikMusicStateMoveCursorToRow para poder
-- reusarlo al agrupar filas por seccion (ver helpers.getSections).
local function nikMusicStateRowToTime(row)
  local proj = 0
  local beat_unit_qn = nikMusicStateBeatUnitQN(proj, row.measure)
  local qn_offset = nikMusicStateBeatToQnOffset(row.beat, row.hundredths, beat_unit_qn)
  local _, qn_start = reaper.TimeMap_GetMeasureInfo(proj, row.measure - 1)
  return reaper.TimeMap2_QNToTime(proj, qn_start + qn_offset)
end

-- Mueve el cursor de edicion de REAPER a la posicion de una fila (scroll de
-- arrange incluido). Usado por el boton "Ir" de Armonia/Cues.
local function nikMusicStateMoveCursorToRow(row)
  reaper.SetEditCurPos(nikMusicStateRowToTime(row), true, false)
end

-- Escanea markers del proyecto (excluye regiones) y devuelve una lista
-- ordenada por tiempo: { {name=, time=}, ... }. No filtra por nomenclatura
-- (ver 01_CONVENCIONES.md) -- cualquier marker cuenta como seccion, para no
-- bloquear la nomenclatura alternativa abreviada (V1, V2, PC...) todavia
-- sin parser. Nombres repetidos (ej. "INTRO" x2) quedan como instancias
-- separadas -- el llamador agrupa por indice, no por nombre.
local function nikMusicStateGetSections()
  local proj = 0
  local sections = {}
  local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)
  for i = 0, num_markers + num_regions - 1 do
    local _, is_region, pos, _, name = reaper.EnumProjectMarkers3(proj, i)
    if not is_region then
      table.insert(sections, { name = (name ~= '' and name) or '(sin nombre)', time = pos })
    end
  end
  table.sort(sections, function(a, b) return a.time < b.time end)
  return sections
end

-- Tabla de dependencias compartidas que el contenedor le pasa a cada modulo
-- de tab -- se arma una sola vez aca, nunca dofile por modulo de tab (ver
-- IMPL_MusicState.md, sesion modularizacion). Se va extendiendo a medida
-- que se extraigan Roles/Armonia/Cues.
local helpers = {
  TONICS_STR = TONICS_STR,
  MODES_STR = MODES_STR,
  captureCursorPosition = nikMusicStateCaptureCursorPosition,
  RowInputs = RowInputs,
  InputCommit = InputCommit,
  moveCursorToRow = nikMusicStateMoveCursorToRow,
  rowToTime = nikMusicStateRowToTime,
  getSections = nikMusicStateGetSections,
  getMaxBeats = function(measure) return nikMusicStateTimesigNum(0, measure) end,
  -- Alto que el contenedor reserva DESPUES del TabBar (Separator + boton
  -- "Guardar y Publicar" + texto de estado) -- las tabs con tabla+scroll
  -- (Armonia, Cues) tienen que restarlo del alto disponible, si no la
  -- tabla se come ese espacio y aparece un scroll exterior no deseado.
  getListFooterReserveH = function() return reaper.ImGui_GetFrameHeightWithSpacing(ctx) * 2 end,
}

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

  -- Mismo criterio que harmony_data (agrupar por compas, ordenar por
  -- qn_offset dentro de cada compas), con los campos propios de cues.
  local cues_by_measure = {}
  for _, row in ipairs(H.cues) do
    local beat_unit_qn = nikMusicStateBeatUnitQN(proj, row.measure)
    local qn_offset = nikMusicStateBeatToQnOffset(row.beat, row.hundredths, beat_unit_qn)
    local roles_parts = {}
    for role in (row.roles_str or ''):gmatch('[^,]+') do
      table.insert(roles_parts, string.format('"%s"', role:match('^%s*(.-)%s*$')))
    end
    local roles_json = '[' .. table.concat(roles_parts, ',') .. ']'
    local event_json = string.format('{"qn_offset":%.4g,"roles":%s,"text":"%s","duration_qn":%.4g}',
      qn_offset, roles_json, row.text or '', row.duration_qn or 0)
    cues_by_measure[row.measure] = cues_by_measure[row.measure] or {}
    table.insert(cues_by_measure[row.measure], { qn_offset = qn_offset, json = event_json })
  end

  local cues_measure_parts = {}
  for measure, events in pairs(cues_by_measure) do
    table.sort(events, function(a, b) return a.qn_offset < b.qn_offset end)
    local event_jsons = {}
    for _, e in ipairs(events) do table.insert(event_jsons, e.json) end
    table.insert(cues_measure_parts, { measure = measure,
      json = string.format('"%d":[%s]', measure, table.concat(event_jsons, ',')) })
  end
  table.sort(cues_measure_parts, function(a, b) return a.measure < b.measure end)
  local cues_measure_jsons = {}
  for _, m in ipairs(cues_measure_parts) do table.insert(cues_measure_jsons, m.json) end
  local cues_json = '{' .. table.concat(cues_measure_jsons, ',') .. '}'

  H.publish_version = (H.publish_version or 0) + 1

  reaper.SetProjExtState(proj, Bridge.NAMESPACE, 'project_key', key_json)
  reaper.SetProjExtState(proj, Bridge.NAMESPACE, 'project_roles', roles_json)
  reaper.SetProjExtState(proj, Bridge.NAMESPACE, 'harmony_data', harmony_json)
  reaper.SetProjExtState(proj, Bridge.NAMESPACE, 'cues_data', cues_json)
  reaper.SetProjExtState(proj, Bridge.NAMESPACE, 'publish_version', tostring(H.publish_version))

  local ok_key = Bridge.bridgeKey(proj, 'project_key')
  local ok_roles = Bridge.bridgeKey(proj, 'project_roles')
  local ok_harmony = Bridge.bridgeKey(proj, 'harmony_data')
  local ok_cues = Bridge.bridgeKey(proj, 'cues_data')
  local ok_ver = Bridge.bridgeKey(proj, 'publish_version')

  if ok_key and ok_roles and ok_harmony and ok_cues and ok_ver then
    H.save_status = 'Guardado OK.'
  else
    H.save_status = 'Error al publicar (ver consola).'
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
        Tonalidad.draw(ctx, H, helpers)
        reaper.ImGui_EndTabItem(ctx)
      end
      if reaper.ImGui_BeginTabItem(ctx, 'Roles') then
        Roles.draw(ctx, H, helpers)
        reaper.ImGui_EndTabItem(ctx)
      end
      if reaper.ImGui_BeginTabItem(ctx, 'Armonia') then
        Armonia.draw(ctx, H, helpers)
        reaper.ImGui_EndTabItem(ctx)
      end
      if reaper.ImGui_BeginTabItem(ctx, 'Cues') then
        Cues.draw(ctx, H, helpers)
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