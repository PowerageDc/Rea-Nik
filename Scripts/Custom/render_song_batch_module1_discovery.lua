-- ============================================================
-- Render Song Batch — Módulo 1: Discovery de tracks + Estado
-- Test standalone: corre la clasificación de tracks y el
-- guardado/restauración de estado (vol+pan+mute), e imprime un
-- reporte en la consola de Reaper para validar antes de construir
-- la UI (módulo 2, ReaImGui) y el motor de render (módulo 3).
-- ============================================================

-- ================== CONFIG ==================
local STEM_BUS_TRACK_NAME = "Stem Bus"

-- name = nombre de track en inglés (convención) / label_es = nombre en render
local STEMS = {
  { name = "Drums",  label_es = "Batería",  patterns = {"drum"} },
  { name = "Bass",   label_es = "Bajo",     patterns = {"bass"} },
  { name = "Guitar", label_es = "Guitarra", patterns = {"guitar", "gtr", "%f[%a]gt%f[%A]"} },
  { name = "Piano",  label_es = "Piano",    patterns = {"piano", "keys"} },
  { name = "Other",  label_es = "Other",    patterns = {"other"} }, -- sin traducción
  { name = "Vocals", label_es = "Voz",      patterns = {"vocal"} },
}

local INSTRUMENTAL_PATTERNS = {"instrum"}

local COUNTIN_PATTERNS = {
  "count in", "countin", "count",
  "click",
  "metronome", "metr.nomo", -- cubre metronome / metrónomo / metronomo
  "marca",
}

local DEFAULT_BACKGROUND_DB = -15 -- volumen del "resto" en render de stem individual (usado en módulo 3)

-- ==============================================

-- Lowercase que también normaliza vocales acentuadas españolas.
-- string.lower de Reaper/Lua no garantiza tocar bytes UTF-8 no-ASCII
-- según locale del sistema — mismo tipo de gotcha ya visto en el importer.
local ACCENT_MAP = {
  ["\195\129"] = "\195\161", -- Á -> á
  ["\195\137"] = "\195\169", -- É -> é
  ["\195\141"] = "\195\173", -- Í -> í
  ["\195\147"] = "\195\179", -- Ó -> ó
  ["\195\154"] = "\195\186", -- Ú -> ú
  ["\195\145"] = "\195\177", -- Ñ -> ñ
}
local function toLowerEs(str)
  str = string.lower(str)
  for upper, lower in pairs(ACCENT_MAP) do
    str = str:gsub(upper, lower)
  end
  return str
end

local function matchesAny(lname, patterns)
  for _, pat in ipairs(patterns) do
    if lname:find(pat) then return true end
  end
  return false
end

-- Devuelve los tracks hijos directos/anidados de STEM_BUS_TRACK_NAME
local function getStemBusChildren()
  local count = reaper.CountTracks(0)
  local busIdx = nil
  for i = 0, count - 1 do
    local track = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(track)
    if toLowerEs(name) == toLowerEs(STEM_BUS_TRACK_NAME) then
      busIdx = i
      break
    end
  end
  if not busIdx then return {}, nil end

  local busTrack = reaper.GetTrack(0, busIdx)
  local children = {}
  local runningDepth = 0
  for i = busIdx + 1, count - 1 do
    local track = reaper.GetTrack(0, i)
    table.insert(children, track)
    runningDepth = runningDepth + reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    if runningDepth <= -1 then break end
  end
  return children, busTrack
end

-- Clasifica todos los tracks del proyecto en stems / instrumental / countin / extras
local function classifyTracks()
  local children, busTrack = getStemBusChildren()
  local childSet = {}
  for _, t in ipairs(children) do childSet[t] = true end

  local result = {
    stems = {},                     -- [stemName] = track
    unmatchedStemBusChildren = {},  -- hijos del bus que no matchearon ningún patrón de stem
    instrumental = nil,
    countin = nil,
    extras = {},                    -- todo lo demás (VSTi overdubs, etc.)
  }

  -- 1) Clasificar hijos del Stem Bus
  for _, track in ipairs(children) do
    local _, tname = reaper.GetTrackName(track)
    local lname = toLowerEs(tname)
    local matched = false
    for _, stem in ipairs(STEMS) do
      if matchesAny(lname, stem.patterns) then
        if result.stems[stem.name] then
          reaper.ShowConsoleMsg("⚠ AVISO: más de un track matchea '" .. stem.name .. "' (" ..
            tname .. " pisa un match anterior)\n")
        end
        result.stems[stem.name] = track
        matched = true
        break
      end
    end
    if not matched then
      table.insert(result.unmatchedStemBusChildren, tname)
    end
  end

  -- 2) Recorrer el resto de tracks del proyecto (no hijos del bus, no el bus mismo)
  local count = reaper.CountTracks(0)
  for i = 0, count - 1 do
    local track = reaper.GetTrack(0, i)
    if track ~= busTrack and not childSet[track] then
      local _, tname = reaper.GetTrackName(track)
      local lname = toLowerEs(tname)
      if matchesAny(lname, INSTRUMENTAL_PATTERNS) then
        if result.instrumental then
          reaper.ShowConsoleMsg("⚠ AVISO: más de un track matchea patrón instrumental (" .. tname .. ")\n")
        end
        result.instrumental = track
      elseif matchesAny(lname, COUNTIN_PATTERNS) then
        if result.countin then
          reaper.ShowConsoleMsg("⚠ AVISO: más de un track matchea patrón count-in (" .. tname .. ")\n")
        end
        result.countin = track
      else
        table.insert(result.extras, track)
      end
    end
  end

  return result
end

-- Guarda vol + pan + mute de TODOS los tracks del proyecto
local function saveTrackStates()
  local saved = {}
  local count = reaper.CountTracks(0)
  for i = 0, count - 1 do
    local track = reaper.GetTrack(0, i)
    saved[track] = {
      vol  = reaper.GetMediaTrackInfo_Value(track, "D_VOL"),
      pan  = reaper.GetMediaTrackInfo_Value(track, "D_PAN"),
      mute = reaper.GetMediaTrackInfo_Value(track, "B_MUTE"),
    }
  end
  return saved
end

-- Restaura el estado guardado por saveTrackStates()
local function restoreTrackStates(saved)
  for track, state in pairs(saved) do
    if reaper.ValidatePtr(track, "MediaTrack*") then
      reaper.SetMediaTrackInfo_Value(track, "D_VOL", state.vol)
      reaper.SetMediaTrackInfo_Value(track, "D_PAN", state.pan)
      reaper.SetMediaTrackInfo_Value(track, "B_MUTE", state.mute)
    end
  end
  reaper.UpdateArrange()
end

-- ================== TEST / REPORTE ==================
local function trackName(track)
  if not track then return "(no encontrado)" end
  local _, n = reaper.GetTrackName(track)
  return n
end

local function main()
  reaper.ClearConsole()

  local cls = classifyTracks()

  reaper.ShowConsoleMsg("=== STEMS (Stem Bus) ===\n")
  for _, stem in ipairs(STEMS) do
    reaper.ShowConsoleMsg(string.format("  %-8s (%s): %s\n", stem.name, stem.label_es, trackName(cls.stems[stem.name])))
  end
  if #cls.unmatchedStemBusChildren > 0 then
    reaper.ShowConsoleMsg("  ⚠ Hijos del Stem Bus sin match: " .. table.concat(cls.unmatchedStemBusChildren, ", ") .. "\n")
  end

  reaper.ShowConsoleMsg("\n=== INSTRUMENTAL ===\n  " .. trackName(cls.instrumental) .. "\n")
  reaper.ShowConsoleMsg("\n=== COUNT-IN / CLICK ===\n  " .. trackName(cls.countin) .. "\n")

  reaper.ShowConsoleMsg("\n=== EXTRAS (VSTi overdubs, etc.) — se mutean en renders de stem individual ===\n")
  if #cls.extras == 0 then
    reaper.ShowConsoleMsg("  (ninguno)\n")
  else
    for _, t in ipairs(cls.extras) do
      reaper.ShowConsoleMsg("  " .. trackName(t) .. "\n")
    end
  end

  -- Test de guardado/restauración: no modifica nada, solo valida que corre sin error
  local saved = saveTrackStates()
  local n = 0
  for _ in pairs(saved) do n = n + 1 end
  reaper.ShowConsoleMsg("\n=== ESTADO ===\n  Guardados vol/pan/mute de " .. n .. " tracks. (restoreTrackStates disponible; no se aplicó ningún cambio en este test)\n")
end

main()
