--[[
  Generador de Regiones de Render — Practice Rig / Stems Player
  Parte 1: Configuración + funciones auxiliares

  Este script (en construcción por etapas) va a generar automáticamente,
  a partir de los markers de sección existentes, las regiones de render
  para las 12 combinaciones (6 protagonista + 6 "sin instrumento") por
  cada sección, con count-in y padding incluidos.
--]]

------------------------------------------------------------
-- CONFIGURACIÓN (editable)
------------------------------------------------------------

-- Padding de silencio (segundos) al inicio y al final de cada región
local PADDING_SEC = 1.0

-- Patrón de count-in por defecto para todas las secciones
-- Valores posibles: "4_NEGRAS" | "2_BLANCAS_4_NEGRAS"
local DEFAULT_COUNT_IN_PATTERN = "4_NEGRAS"

-- Excepciones puntuales de patrón de count-in por nombre de marker/sección
-- (dejar vacío {} si no hay excepciones)
local SECTION_COUNT_IN_OVERRIDES = {
  -- ["CORO 1"] = "2_BLANCAS_4_NEGRAS",
}

-- Correspondencia Track (inglés) -> Instrumento (español), en el orden
-- en que se van a generar las combinaciones por sección
local INSTRUMENT_MAP = {
  { track = "Drums",  es = "Batería"  },
  { track = "Bass",   es = "Bajo"     },
  { track = "Guitar", es = "Guitarra" },
  { track = "Piano",  es = "Piano"    },
  { track = "Other",  es = "Otros"    },
  { track = "Vocals", es = "Voz"      },
}

-- Plantillas de nombre de región (= nombre de archivo final)
local FILENAME_TEMPLATE_PROTAGONISTA = "🎵 Audio - %s - %s"
local FILENAME_TEMPLATE_SIN          = "🎵 Audio - Sin %s - %s"

-- Si true, al terminar la generación se intenta ocultar el lane donde
-- quedaron las regiones creadas (TODO: verificar en Paso 7.4 si el
-- mecanismo elegido realmente afecta solo ese lane y no todas las
-- regiones/markers del proyecto)
local HIDE_REGION_LANE_AFTER_GENERATION = false

------------------------------------------------------------
-- FUNCIONES AUXILIARES
------------------------------------------------------------

-- Devuelve el BPM vigente en una posición de tiempo dada (segundos)
local function get_bpm_at_position(pos)
  local bpm = reaper.TimeMap2_GetDividedBpmAtTime(0, pos)
  return bpm
end

-- Calcula la duración en segundos de un patrón de count-in a un BPM dado
local function count_in_duration_sec(bpm, pattern)
  local quarter_note_sec = 60.0 / bpm

  if pattern == "4_NEGRAS" then
    return 4 * quarter_note_sec
  elseif pattern == "2_BLANCAS_4_NEGRAS" then
    -- 2 blancas = 4 negras de duración, + 4 negras = 8 negras en total
    return 8 * quarter_note_sec
  else
    reaper.ShowConsoleMsg("ADVERTENCIA: patrón de count-in desconocido: " .. tostring(pattern) .. "\n")
    return 4 * quarter_note_sec -- fallback
  end
end

-- Devuelve el patrón de count-in a usar para una sección dada,
-- respetando excepciones puntuales definidas en SECTION_COUNT_IN_OVERRIDES
local function get_count_in_pattern_for_section(section_name)
  return SECTION_COUNT_IN_OVERRIDES[section_name] or DEFAULT_COUNT_IN_PATTERN
end

------------------------------------------------------------
-- ENUMERACIÓN DE MARKERS DE SECCIÓN
------------------------------------------------------------

-- Devuelve una lista ordenada de markers (no regiones) del proyecto:
-- { {name=..., pos=...}, ... }
local function get_section_markers()
  local markers = {}
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local total = num_markers + num_regions

  for i = 0, total - 1 do
    local retval, isrgn, pos, _, name = reaper.EnumProjectMarkers3(0, i)
    if retval > 0 and not isrgn then
      table.insert(markers, { name = name, pos = pos })
    end
  end

  table.sort(markers, function(a, b) return a.pos < b.pos end)
  return markers
end

------------------------------------------------------------
-- ARMADO DEL PLAN DE REGIONES (sin crear nada todavía)
------------------------------------------------------------

-- Por cada sección, arma las 12 combinaciones (6 protagonista + 6 sin
-- instrumento), calculando inicio/fin con count-in + padding incluidos.
local function build_planned_regions(section_markers)
  local planned = {}
  local project_end = reaper.GetProjectLength(0)

  for i, marker in ipairs(section_markers) do
    local section_start = marker.pos
    local section_end = section_markers[i + 1] and section_markers[i + 1].pos or project_end

    local pattern = get_count_in_pattern_for_section(marker.name)
    local bpm = get_bpm_at_position(section_start)
    local count_in_dur = count_in_duration_sec(bpm, pattern)

    local region_start = section_start - count_in_dur - PADDING_SEC
    local region_end = section_end + PADDING_SEC

    for _, instr in ipairs(INSTRUMENT_MAP) do
      table.insert(planned, {
        name = string.format(FILENAME_TEMPLATE_PROTAGONISTA, instr.es, marker.name),
        start_pos = region_start,
        end_pos = region_end,
        bpm = bpm,
        pattern = pattern,
        count_in_dur = count_in_dur,
      })
      table.insert(planned, {
        name = string.format(FILENAME_TEMPLATE_SIN, instr.es, marker.name),
        start_pos = region_start,
        end_pos = region_end,
        bpm = bpm,
        pattern = pattern,
        count_in_dur = count_in_dur,
      })
    end
  end

  return planned
end

------------------------------------------------------------
-- VISTA PREVIA + CONFIRMACIÓN
------------------------------------------------------------

-- Imprime el detalle completo en la consola de ReaScript y pide
-- confirmación por diálogo antes de crear nada.
local function show_preview_and_confirm(planned)
  reaper.ClearConsole()
  reaper.ShowConsoleMsg("===== VISTA PREVIA: REGIONES A GENERAR =====\n")
  reaper.ShowConsoleMsg(string.format("Total de regiones a crear: %d\n\n", #planned))

  for _, r in ipairs(planned) do
    reaper.ShowConsoleMsg(string.format(
      "  %-45s  [%7.2fs -> %7.2fs]  (bpm=%.1f, patrón=%s, count-in=%.2fs)\n",
      r.name, r.start_pos, r.end_pos, r.bpm, r.pattern, r.count_in_dur
    ))
  end

  reaper.ShowConsoleMsg("\n=============================================\n")

  local msg = string.format(
    "Se van a crear %d regiones nuevas.\n\n" ..
    "El detalle completo está impreso en la consola de ReaScript.\n\n" ..
    "¿Confirmás la generación?",
    #planned
  )
  local ret = reaper.MB(msg, "Confirmar generación de regiones", 1) -- 1 = OK/Cancel
  return ret == 1 -- 1 = OK
end

------------------------------------------------------------
-- CREACIÓN DE REGIONES (recién acá se modifica el proyecto)
------------------------------------------------------------

local function create_regions(planned)
  reaper.Undo_BeginBlock()
  for _, r in ipairs(planned) do
    reaper.AddProjectMarker2(0, true, r.start_pos, r.end_pos, r.name, -1, 0)
  end
  reaper.Undo_EndBlock("Generar regiones de render (batch)", -1)
end

------------------------------------------------------------
-- MAIN
------------------------------------------------------------

local function main()
  local section_markers = get_section_markers()

  if #section_markers == 0 then
    reaper.MB("No se encontraron markers de sección en el proyecto.", "Aviso", 0)
    return
  end

  local planned = build_planned_regions(section_markers)
  local confirmed = show_preview_and_confirm(planned)

  if confirmed then
    create_regions(planned)
    reaper.MB(string.format("Listo. Se crearon %d regiones.", #planned), "Generación completa", 0)
  else
    reaper.ShowConsoleMsg("\nGeneración cancelada por el usuario. No se creó ninguna región.\n")
  end
end

main()
