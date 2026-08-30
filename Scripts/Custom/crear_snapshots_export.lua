--[[
  Crear Snapshots de Exportacion de Stems
  ----------------------------------------
  Genera automaticamente snapshots SWS para exportar cada instrumento
  al frente de la mezcla (resto de instrumentos atenuados).

  Requiere: SWS/S&M Extensions
  Testeado en: Reaper v7.76 / Windows 10

  Estructura de proyecto esperada:
    - "Stem Bus" (track folder) con los stems importados como hijos
    - "Instrumental" (track hermano, opcional) = referencia karaoke
    - Tracks VSTi de maqueta (guitarra/bajo/teclado/bateria, etc.)
    - Tracks de click/metronomo (se ignoran siempre)

  Snapshots generadas:
    SN_Base                -> estado original (para restaurar)
    SN_<NombreDelStem>      -> uno por cada hijo de "Stem Bus"
    SN_Instrumental         -> si existe track "Instrumental"
    SN_Instrumental_Auto    -> fallback: mutea el stem de voz si no hay Instrumental

  Limite: 12 snapshots scripteables (accion nativa SWS). Si
  1 (Base) + stems + 1 (Instrumental) supera 12, el script aborta.
]]

-- =========================================================================
-- CONFIGURACION
-- =========================================================================

local ATTEN_DB       = -18        -- atenuacion absoluta para instrumentos no protagonistas
local SNAPSHOT_PREFIX = "SN_"
local MAX_SLOTS       = 12

local METRONOME_PATTERNS = { "metronome", "metronomo", "click", "count in", "count" }
local VOCAL_PATTERNS     = { "vocals", "vocal", "voice", "voz" }
local STEMBUS_PATTERNS   = { "stem bus" }
local INSTRUMENTAL_PATTERNS = { "instrumental" }

-- Command IDs (SWS/S&M) -- confirmados desde el Action List del usuario
local CMD_TOGGLE_SELONLY = "_SWSSNAPSHOT_SELONLY"
local CMD_SAVEFILT       = "_SWSSNAPSHOT_SAVEFILT"
local CMD_RESTFILT       = "_SWSSNAPSHOT_RESTFILT"

local function save_cmd(n) return "_SWSSNAPSHOT_SAVE" .. n end
local function get_cmd(n)  return "_SWSSNAPSHOT_GET" .. n end

-- =========================================================================
-- UTILIDADES DE TEXTO (acentos / normalizacion)
-- =========================================================================

local ACCENT_MAP = {
  ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ñ"] = "n",
  ["Á"] = "A", ["É"] = "E", ["Í"] = "I", ["Ó"] = "O", ["Ú"] = "U", ["Ñ"] = "N",
  ["ü"] = "u", ["Ü"] = "U",
}

local function strip_accents(s)
  local out = s
  for k, v in pairs(ACCENT_MAP) do
    out = out:gsub(k, v)
  end
  return out
end

local function normalize(s)
  return strip_accents(s):lower()
end

local function name_matches_any(name, patterns)
  local n = normalize(name)
  for _, p in ipairs(patterns) do
    if n:find(p, 1, true) then return true end
  end
  return false
end

-- =========================================================================
-- UTILIDADES DE TRACKS
-- =========================================================================

local function get_track_name(track)
  local _, name = reaper.GetTrackName(track)
  return name
end

local function find_track_by_pattern(patterns, exclude_set)
  local count = reaper.CountTracks(0)
  for i = 0, count - 1 do
    local t = reaper.GetTrack(0, i)
    if not (exclude_set and exclude_set[t]) then
      if name_matches_any(get_track_name(t), patterns) then
        return t
      end
    end
  end
  return nil
end

-- Devuelve los tracks hijos de un folder (asume estructura plana, sin
-- sub-folders anidados dentro de Stem Bus).
local function get_folder_children(folder_track)
  local children = {}
  local count = reaper.CountTracks(0)
  local folder_num = reaper.GetMediaTrackInfo_Value(folder_track, "IP_TRACKNUMBER")
  local i = folder_num -- 0-based index del primer hijo (IP_TRACKNUMBER es 1-based)
  local depth = 1
  while i < count and depth > 0 do
    local t = reaper.GetTrack(0, i)
    table.insert(children, t)
    local d = reaper.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
    depth = depth + d
    i = i + 1
  end
  return children
end

local function select_only(tracks)
  local set = {}
  for _, t in ipairs(tracks) do set[t] = true end
  local count = reaper.CountTracks(0)
  for i = 0, count - 1 do
    local t = reaper.GetTrack(0, i)
    reaper.SetTrackSelected(t, set[t] == true)
  end
end

local function set_track_mute(track, muted)
  reaper.SetMediaTrackInfo_Value(track, "B_MUTE", muted and 1 or 0)
end

local function db_to_vol(db)
  return 10 ^ (db / 20)
end

local function set_track_vol_db(track, db)
  reaper.SetMediaTrackInfo_Value(track, "D_VOL", db_to_vol(db))
end

-- =========================================================================
-- CLASIFICACION DE TRACKS
-- =========================================================================

local function classify_tracks()
  local stem_bus = find_track_by_pattern(STEMBUS_PATTERNS)
  if not stem_bus then
    return nil, "No se encontro el track folder 'Stem Bus'. Abortando."
  end

  local stem_children = get_folder_children(stem_bus)
  if #stem_children == 0 then
    return nil, "El folder 'Stem Bus' no tiene tracks hijos. Abortando."
  end

  local in_stembus = { [stem_bus] = true }
  for _, t in ipairs(stem_children) do in_stembus[t] = true end

  local instrumental = find_track_by_pattern(INSTRUMENTAL_PATTERNS, in_stembus)

  local vocals_child = nil
  for _, t in ipairs(stem_children) do
    if name_matches_any(get_track_name(t), VOCAL_PATTERNS) then
      vocals_child = t
      break
    end
  end

  -- VSTi = todo lo que no sea Stem Bus (ni sus hijos), ni Instrumental,
  -- ni patron de Metronomo/Click/Count.
  local vsti_tracks = {}
  local count = reaper.CountTracks(0)
  for i = 0, count - 1 do
    local t = reaper.GetTrack(0, i)
    if not in_stembus[t] and t ~= instrumental then
      if not name_matches_any(get_track_name(t), METRONOME_PATTERNS) then
        table.insert(vsti_tracks, t)
      end
    end
  end

  return {
    stem_bus      = stem_bus,
    stem_children = stem_children,
    instrumental  = instrumental,
    vocals_child  = vocals_child,
    vsti_tracks   = vsti_tracks,
  }
end

local function build_full_selection(ctx)
  local list = {}
  for _, t in ipairs(ctx.stem_children) do table.insert(list, t) end
  if ctx.instrumental then table.insert(list, ctx.instrumental) end
  for _, t in ipairs(ctx.vsti_tracks) do table.insert(list, t) end
  return list
end

-- =========================================================================
-- APLICACION DE ESTADOS (volumen / mute) POR SNAPSHOT
-- =========================================================================

-- Protagonista sin cambios (queda como en SN_Base). Resto de Stem Bus a
-- ATTEN_DB. Instrumental muteado. VSTi muteado.
local function apply_protagonist_state(ctx, protagonist)
  for _, t in ipairs(ctx.stem_children) do
    if t ~= protagonist then
      set_track_vol_db(t, ATTEN_DB)
    end
  end
  if ctx.instrumental then
    set_track_mute(ctx.instrumental, true)
  end
  for _, t in ipairs(ctx.vsti_tracks) do
    set_track_mute(t, true)
  end
end

-- Devuelve (nombre_snapshot, ok). ok=false si no hay forma de generar
-- la snapshot de Instrumental (ni track real ni fallback por Vocals).
local function apply_instrumental_state(ctx)
  if ctx.instrumental then
    for _, t in ipairs(ctx.stem_children) do
      set_track_mute(t, true)
    end
    for _, t in ipairs(ctx.vsti_tracks) do
      set_track_mute(t, true)
    end
    return SNAPSHOT_PREFIX .. "Instrumental", true
  end

  if ctx.vocals_child then
    set_track_mute(ctx.vocals_child, true)
    for _, t in ipairs(ctx.vsti_tracks) do
      set_track_mute(t, true)
    end
    return SNAPSHOT_PREFIX .. "Instrumental_Auto", true
  end

  return nil, false
end

-- =========================================================================
-- SNAPSHOTS SWS (guardar / recordar / renombrar via archivo .rpp en disco)
-- =========================================================================

local pending_renames = {}

local function run_action(cmd_id_str)
  local id = reaper.NamedCommandLookup(cmd_id_str)
  if id == 0 then
    error("No se encontro el comando de accion: " .. cmd_id_str)
  end
  reaper.Main_OnCommand(id, 0)
end

local function ensure_selected_only_on()
  local id = reaper.NamedCommandLookup(CMD_TOGGLE_SELONLY)
  if id == 0 then
    error("No se encontro el comando: " .. CMD_TOGGLE_SELONLY)
  end
  if reaper.GetToggleCommandStateEx(0, id) == 0 then
    reaper.Main_OnCommand(id, 0)
  end
end

local function recall_slot(n)
  run_action(get_cmd(n))
end

-- Busca el N-esimo bloque <SWSSNAPSHOT "..." y reemplaza su nombre.
local function set_snapshot_name_in_chunk(chunk, slot_index, new_name)
  local search_pos = 1
  local count = 0
  while true do
    local s, e = chunk:find('<SWSSNAPSHOT%s+"', search_pos)
    if not s then
      return nil, "No se encontraron suficientes bloques SWSSNAPSHOT en el chunk (se esperaba al menos " .. slot_index .. ")"
    end
    count = count + 1
    local name_start = e + 1
    local name_end = chunk:find('"', name_start)
    if not name_end then
      return nil, "Formato de snapshot inesperado en el chunk (falta comilla de cierre)"
    end
    if count == slot_index then
      local clean_name = new_name:gsub('"', "")
      return chunk:sub(1, name_start - 1) .. clean_name .. chunk:sub(name_end)
    end
    search_pos = name_end + 1
  end
end

local function save_and_rename(slot_index, name)
  run_action(save_cmd(slot_index))
  table.insert(pending_renames, { slot = slot_index, name = name })
end

local function get_saved_project_path()
  local _, project_path = reaper.EnumProjects(-1, "")
  if project_path == "" then
    error("El proyecto no esta guardado en disco. Guarda el proyecto (.rpp) antes de correr este script.")
  end
  return project_path
end

local function apply_pending_renames(project_path)
  if #pending_renames == 0 then return end

  reaper.Main_SaveProject(0, false)

  local file, open_err = io.open(project_path, "r")
  if not file then
    error("No se pudo abrir el proyecto guardado para renombrar snapshots: " .. tostring(open_err))
  end
  local content = file:read("*a")
  file:close()

  for _, item in ipairs(pending_renames) do
    local new_content, rename_err = set_snapshot_name_in_chunk(content, item.slot, item.name)
    if not new_content then
      error("Error renombrando snapshot en slot " .. item.slot .. ": " .. tostring(rename_err))
    end
    content = new_content
  end

  local out_file, write_err = io.open(project_path, "w")
  if not out_file then
    error("No se pudo escribir el proyecto para renombrar snapshots: " .. tostring(write_err))
  end
  out_file:write(content)
  out_file:close()

  reaper.Main_openProject(project_path)
end

-- =========================================================================
-- FLUJO PRINCIPAL
-- =========================================================================

local function main()
  local project_path = get_saved_project_path()

  local ctx, err = classify_tracks()
  if not ctx then
    error(err)
  end

  local total_slots = 1 + #ctx.stem_children + 1
  if total_slots > MAX_SLOTS then
    error(string.format(
      "Se necesitan %d snapshots (Base + %d instrumentos + Instrumental) pero el maximo scripteable es %d. Abortando.",
      total_slots, #ctx.stem_children, MAX_SLOTS))
  end

  run_action(CMD_SAVEFILT)
  ensure_selected_only_on()

  local selection = build_full_selection(ctx)

  -- Slot 1: Base (estado original, sin modificar nada)
  select_only(selection)
  save_and_rename(1, "SN_Base")

  -- Slots 2..N: uno por instrumento protagonista
  local slot = 2
  for _, protagonist in ipairs(ctx.stem_children) do
    recall_slot(1)
    apply_protagonist_state(ctx, protagonist)
    select_only(selection)
    save_and_rename(slot, SNAPSHOT_PREFIX .. get_track_name(protagonist))
    slot = slot + 1
  end

  -- Ultimo slot: Instrumental (real o fallback por Vocals)
  recall_slot(1)
  local instrumental_name, ok_case = apply_instrumental_state(ctx)
  if ok_case then
    select_only(selection)
    save_and_rename(slot, instrumental_name)
  else
    reaper.ShowConsoleMsg("[Export Snapshots] Aviso: no se genero snapshot de Instrumental (no hay track 'Instrumental' ni stem de voz detectado)\n")
  end

  -- Restaurar todo al estado original
  recall_slot(1)

  run_action(CMD_RESTFILT)

  apply_pending_renames(project_path)
end

-- =========================================================================
-- EJECUCION
-- =========================================================================

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local ok_run, err_run = pcall(main)

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Crear snapshots de exportacion de stems", -1)

if not ok_run then
  reaper.ShowMessageBox(tostring(err_run), "Export Snapshots - Error", 0)
end
