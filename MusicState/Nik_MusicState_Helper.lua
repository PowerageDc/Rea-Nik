-- Nik_MusicState_Helper.lua
-- Panel nativo ReaImGui para cargar metadata musical (harmony, key, roles, cues)
-- en ProjExtState sin editar el script de publish a mano.
-- Paso 3: + extraccion de bridge reusable, + boton "Guardar y Publicar"
-- (Tonalidad y Roles unicamente -- Armonia y Cues en los proximos pasos).

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Bridge = dofile(script_dir .. "../_Shared/MusicStateBridge_common_logic.lua")
local InputCommit = dofile(script_dir .. "../_Shared/ImGuiInputCommit_common_logic.lua")

local ctx = reaper.ImGui_CreateContext('MusicState Helper')
local font = reaper.ImGui_CreateFont('sans-serif', 16)
reaper.ImGui_Attach(ctx, font)

local H = {
  key = { tonic_idx = 4, mode_idx = 0 },  -- tonic_idx 4 = "C" (ver TONICS abajo)
  roles = {},
  new_role_buf = '',
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

-- Context creation, config_flags=0 para desactivar Nav
local ctx = reaper.ImGui_CreateContext('MusicState Helper', 0)

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

  -- harmony_data / cues_data: parseo pendiente, se suma en los pasos 4-5.
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

  reaper.SetProjExtState(proj, Bridge.NAMESPACE, 'project_key', key_json)
  reaper.SetProjExtState(proj, Bridge.NAMESPACE, 'project_roles', roles_json)
  -- harmony_data / cues_data: sin tocar todavia (tabs pendientes, pasos 4-5).
  -- Nota: esto NO pisa esas dos keys -- SetProjExtState es por-key, no reemplaza el namespace entero.

  local ok_key = Bridge.bridgeKey(proj, 'project_key')
  local ok_roles = Bridge.bridgeKey(proj, 'project_roles')

  if ok_key and ok_roles then
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
        reaper.ImGui_TextDisabled(ctx, '(proximo paso)')
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