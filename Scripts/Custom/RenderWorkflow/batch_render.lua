--[[
  Batch Render — Practice Rig / Stems Player
  Parte 1: Configuración + funciones auxiliares

  Este script (en construcción por etapas) toma las regiones ya creadas
  por el generador (render_regions_generator.lua), permite filtrar cuáles
  procesar, recupera el snapshot SWS correspondiente a cada una (leyendo
  el .rpp guardado en disco, sin depender de un mapeo fijo), y dispara
  el render de cada región individualmente.
--]]

------------------------------------------------------------
-- CONFIGURACIÓN (editable)
------------------------------------------------------------

-- Nombre EXACTO del track dedicado al count-in (ajustar si difiere)
local COUNT_IN_TRACK_NAME = "COUNT IN"

-- Prefijo común de las regiones de render (debe coincidir con el usado
-- por render_regions_generator.lua)
local REGION_PREFIX = "🎵 Audio - "

-- Command ID de la acción nativa:
-- "File: Render project, using the most recent render settings, auto-close render dialog"
local RENDER_ACTION_ID = 42230

-- Correspondencia Track (inglés) / Instrumento (español) / nombres de
-- snapshot esperados (ver 01_CONVENCIONES.md)
local INSTRUMENT_MAP = {
  { track = "Drums",  es = "Batería",  snap_protagonist = "SN_Drums",  snap_muted = "SN_Drums_Muted"  },
  { track = "Bass",   es = "Bajo",     snap_protagonist = "SN_Bass",   snap_muted = "SN_Bass_Muted"   },
  { track = "Guitar", es = "Guitarra", snap_protagonist = "SN_Guitar", snap_muted = "SN_Guitar_Muted" },
  { track = "Piano",  es = "Piano",    snap_protagonist = "SN_Piano",  snap_muted = "SN_Piano_Muted"  },
  { track = "Other",  es = "Otros",    snap_protagonist = "SN_Other",  snap_muted = "SN_Other_Muted"  },
  { track = "Vocals", es = "Voz",      snap_protagonist = "SN_Vocals", snap_muted = "SN_Instrumental" },
}

------------------------------------------------------------
-- FUNCIONES AUXILIARES: TRACKS
------------------------------------------------------------

local function find_track_by_exact_name(name)
  local count = reaper.CountTracks(0)
  for i = 0, count - 1 do
    local t = reaper.GetTrack(0, i)
    local _, tname = reaper.GetTrackName(t)
    if tname == name then return t end
  end
  return nil
end

local function set_track_mute(track, muted)
  reaper.SetMediaTrackInfo_Value(track, "B_MUTE", muted and 1 or 0)
end

------------------------------------------------------------
-- FUNCIONES AUXILIARES: SNAPSHOTS (guardar proyecto + leer .rpp del disco)
------------------------------------------------------------

-- Obtiene la ruta del proyecto guardado en disco (error si no está guardado)
local function get_saved_project_path()
  local _, project_path = reaper.EnumProjects(-1, "")
  if project_path == "" then
    error("El proyecto no está guardado en disco. Guardalo antes de correr el batch.")
  end
  return project_path
end

-- Devuelve un mapa { nombre_snapshot = numero_de_slot }, guardando el
-- proyecto y leyendo el .rpp directamente del disco (GetProjectStateChunk
-- no existe a nivel de proyecto en la API de REAPER; este es el mecanismo
-- correcto, igual al usado por crear_snapshots_export.lua).
local function get_snapshot_slot_map()
  local project_path = get_saved_project_path()

  local save_confirmed = reaper.MB(
    "Para leer los snapshots actuales es necesario guardar el proyecto.\n\n¿Guardar ahora y continuar?",
    "Confirmar guardado del proyecto",
    1 -- OK/Cancel
  )
  if save_confirmed ~= 1 then
    error("Batch cancelado: se necesita guardar el proyecto para leer los snapshots.")
  end

  reaper.Main_SaveProject(0, false) -- asegura que el .rpp en disco esté al día

  local file, open_err = io.open(project_path, "r")
  if not file then
    error("No se pudo abrir el proyecto para leer los snapshots: " .. tostring(open_err))
  end
  local chunk = file:read("*a")
  file:close()

  local map = {}
  local slot = 0
  local search_pos = 1

  while true do
    local s, e = chunk:find('<SWSSNAPSHOT%s+"', search_pos)
    if not s then break end
    slot = slot + 1
    local name_start = e + 1
    local name_end = chunk:find('"', name_start)
    if not name_end then break end
    map[chunk:sub(name_start, name_end - 1)] = slot
    search_pos = name_end + 1
  end

  return map
end

-- Recupera (recall) el snapshot ubicado en un slot dado
local function recall_snapshot_slot(slot)
  local id = reaper.NamedCommandLookup("_SWSSNAPSHOT_GET" .. slot)
  if id == 0 then
    error("No se encontró la acción de recall para el slot " .. slot)
  end
  reaper.Main_OnCommand(id, 0)
end

------------------------------------------------------------
-- FUNCIONES AUXILIARES: PARSEO DE NOMBRE DE REGIÓN
------------------------------------------------------------

-- Busca la entrada de INSTRUMENT_MAP correspondiente a un nombre en español
local function find_instrument_by_es(es_name)
  for _, instr in ipairs(INSTRUMENT_MAP) do
    if instr.es == es_name then return instr end
  end
  return nil
end

-- Parsea el nombre de una región de render y devuelve:
-- { instrument_es = "Bajo", section = "Coro 1", muted = false }
-- o nil si el nombre no matchea el patrón esperado
local function parse_region_name(name)
  if name:sub(1, #REGION_PREFIX) ~= REGION_PREFIX then
    return nil
  end

  local rest = name:sub(#REGION_PREFIX + 1)
  local instr_part, section = rest:match("^(.-) %- (.+)$")
  if not instr_part then
    return nil
  end

  local muted = false
  local sin_prefix = "Sin "
  if instr_part:sub(1, #sin_prefix) == sin_prefix then
    muted = true
    instr_part = instr_part:sub(#sin_prefix + 1)
  end

  return { instrument_es = instr_part, section = section, muted = muted }
end

------------------------------------------------------------
-- ENUMERACIÓN DE REGIONES EXISTENTES
------------------------------------------------------------

-- Devuelve todas las regiones de render existentes, ya parseadas:
-- { {name=..., start_pos=..., end_pos=..., instrument_es=..., section=..., muted=...}, ... }
local function get_existing_render_regions()
  local regions = {}
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local total = num_markers + num_regions

  for i = 0, total - 1 do
    local retval, isrgn, pos, rgnend, name = reaper.EnumProjectMarkers3(0, i)
    if retval > 0 and isrgn then
      local parsed = parse_region_name(name)
      if parsed then
        table.insert(regions, {
          name = name,
          start_pos = pos,
          end_pos = rgnend,
          instrument_es = parsed.instrument_es,
          section = parsed.section,
          muted = parsed.muted,
        })
      end
    end
  end

  return regions
end

------------------------------------------------------------
-- FILTRO POR UI
------------------------------------------------------------

-- Pide filtros de texto (parcial, insensible a mayúsculas) por sección
-- e instrumento. Vacío = sin filtrar por ese campo.
local function ask_filters()
  local ok, csv = reaper.GetUserInputs(
    "Filtro de regiones a renderizar",
    2,
    "Filtro de sección (ej: Coro),Filtro de instrumento (ej: Bajo)",
    ","
  )
  if not ok then return nil end

  local section_filter, instrument_filter = csv:match("^([^,]*),?(.*)$")
  return {
    section = (section_filter or ""):lower(),
    instrument = (instrument_filter or ""):lower(),
  }
end

local function region_matches_filters(region, filters)
  if filters.section ~= "" and not region.section:lower():find(filters.section, 1, true) then
    return false
  end
  if filters.instrument ~= "" and not region.instrument_es:lower():find(filters.instrument, 1, true) then
    return false
  end
  return true
end

------------------------------------------------------------
-- VISTA PREVIA + CONFIRMACIÓN
------------------------------------------------------------

local function show_batch_preview_and_confirm(regions)
  reaper.ClearConsole()
  reaper.ShowConsoleMsg("===== VISTA PREVIA: REGIONES A RENDERIZAR =====\n")
  reaper.ShowConsoleMsg(string.format("Total: %d\n\n", #regions))

  for _, r in ipairs(regions) do
    reaper.ShowConsoleMsg(string.format("  %s\n", r.name))
  end

  reaper.ShowConsoleMsg("\n================================================\n")

  local msg = string.format(
    "Se van a renderizar %d regiones.\n\n" ..
    "El detalle está en la consola de ReaScript.\n\n¿Confirmás?",
    #regions
  )
  local ret = reaper.MB(msg, "Confirmar batch de render", 1) -- OK/Cancel
  return ret == 1
end

------------------------------------------------------------
-- RENDER DE UNA REGIÓN PUNTUAL (sin depender de "Selected Regions")
------------------------------------------------------------

local function set_render_bounds(start_pos, end_pos)
  reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 0, true) -- 0 = Custom time range
  reaper.GetSetProjectInfo(0, "RENDER_STARTPOS", start_pos, true)
  reaper.GetSetProjectInfo(0, "RENDER_ENDPOS", end_pos, true)
end

local function set_render_filename(name)
  reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", name, true)
end

local function trigger_render()
  reaper.Main_OnCommand(RENDER_ACTION_ID, 0)
end

-- Resuelve snapshot, recupera estado, setea bounds/nombre y dispara el
-- render de una región. Devuelve true si se renderizó, false si se omitió.
local function render_region(region, snapshot_map)
  local instr = find_instrument_by_es(region.instrument_es)
  if not instr then
    reaper.ShowConsoleMsg(string.format(
      "  [OMITIDA] %s -> instrumento desconocido: %s\n", region.name, region.instrument_es
    ))
    return false
  end

  local snapshot_name = region.muted and instr.snap_muted or instr.snap_protagonist
  local slot = snapshot_map[snapshot_name]
  if not slot then
    reaper.ShowConsoleMsg(string.format(
      "  [OMITIDA] %s -> snapshot no encontrado: %s\n", region.name, snapshot_name
    ))
    return false
  end

  recall_snapshot_slot(slot)
  set_render_bounds(region.start_pos, region.end_pos)
  set_render_filename(region.name)
  trigger_render()

  reaper.ShowConsoleMsg(string.format(
    "  [OK] %s  (snapshot=%s, slot=%d)\n", region.name, snapshot_name, slot
  ))
  return true
end

------------------------------------------------------------
-- MAIN
------------------------------------------------------------

local function main()
  local count_in_track = find_track_by_exact_name(COUNT_IN_TRACK_NAME)
  if not count_in_track then
    reaper.MB("No se encontró el track de count-in: " .. COUNT_IN_TRACK_NAME, "Error", 0)
    return
  end

  local all_regions = get_existing_render_regions()
  if #all_regions == 0 then
    reaper.MB("No se encontraron regiones de render en el proyecto.", "Aviso", 0)
    return
  end

  local filters = ask_filters()
  if not filters then
    reaper.ShowConsoleMsg("Batch cancelado (filtro).\n")
    return
  end

  local filtered = {}
  for _, r in ipairs(all_regions) do
    if region_matches_filters(r, filters) then
      table.insert(filtered, r)
    end
  end

  if #filtered == 0 then
    reaper.MB("Ninguna región coincide con el filtro.", "Aviso", 0)
    return
  end

  if not show_batch_preview_and_confirm(filtered) then
    reaper.ShowConsoleMsg("Batch cancelado por el usuario.\n")
    return
  end

  local snapshot_map = get_snapshot_slot_map()

  set_track_mute(count_in_track, false)
  reaper.ShowConsoleMsg("\n===== EJECUTANDO BATCH =====\n")

  local ok_count, skip_count = 0, 0
  for _, r in ipairs(filtered) do
    if render_region(r, snapshot_map) then
      ok_count = ok_count + 1
    else
      skip_count = skip_count + 1
    end
  end

  set_track_mute(count_in_track, true)

  reaper.ShowConsoleMsg(string.format(
    "\n===== FIN: %d renderizadas, %d omitidas =====\n", ok_count, skip_count
  ))
  reaper.MB(string.format(
    "Listo. %d regiones renderizadas, %d omitidas (detalle en consola).", ok_count, skip_count
  ), "Batch completo", 0)
end

main()
