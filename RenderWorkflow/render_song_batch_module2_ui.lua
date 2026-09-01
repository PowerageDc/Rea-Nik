-- ============================================================
-- Render Song Batch
-- UI (ReaImGui) para configurar tonalidad, tempo, Master/Karaoke,
-- extras y stems (protagonista/backing/count-in/overrides), con
-- resumen de archivos y motor de render integrado. El render
-- guarda el estado original de todos los tracks (vol/pan/mute) y
-- lo restaura entre cada archivo y al finalizar, incluso si el
-- batch se interrumpe por error.
--
-- Requiere: ReaImGui (ReaPack). Antes de correrlo, configurar una
-- vez el diálogo de Render (Ctrl+Alt+R) con MP3 192kbps y tocar
-- "Save settings" — el script no toca formato/bitrate, solo
-- bounds de tiempo, nombre de archivo y mute/vol/pan de tracks.
-- ============================================================

if not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox(
    "Este script necesita ReaImGui. Instalalo vía ReaPack (ReaTeam Extensions) y volvé a correrlo.",
    "Falta ReaImGui", 0)
  return
end

-- ================== CONFIG ==================
local STEM_BUS_TRACK_NAME = "Stem Bus"
local STEMS_SUBFOLDER = "PISTAS POR INSTRUMENTO"
local MUTE_SUFFIX = " mute" -- sufijo para backing tracks (alternativa: "🚫")
local DEFAULT_BACKGROUND_DB = -15
local RENDER_PADDING_SECONDS = 1.0 -- padding al inicio/fin del render (evita cortar transientes/colas; ver 01_CONVENCIONES.md)
-- RENDER_FORMAT devuelve un blob binario (no un fourcc plano de 4 chars),
-- así que el chequeo de abajo es heurístico: busca "mp3"/"l3pm" como substring

local STEMS = {
  { name = "Drums",  label_es = "Batería",  patterns = {"drum"},  hasBacking = true },
  { name = "Bass",   label_es = "Bajo",     patterns = {"bass"},  hasBacking = true },
  { name = "Guitar", label_es = "Guitarra", patterns = {"guitar", "gtr", "%f[%a]gt%f[%A]"}, hasBacking = true },
  { name = "Piano",  label_es = "Piano",    patterns = {"piano", "keys"}, hasBacking = true },
  { name = "Other",  label_es = "Other",    patterns = {"other"}, hasBacking = true },
  { name = "Vocals", label_es = "Voz",      patterns = {"vocal"}, hasBacking = false }, -- cubierto por Karaoke
}

local INSTRUMENTAL_PATTERNS = {"instrum"}
local COUNTIN_PATTERNS = {
  "count in", "countin", "count", "click",
  "metronome", "metr.nomo", "marca",
}

local EXT_NAMESPACE = "RenderSongBatch"
-- ==============================================

-- ---------- Discovery (igual que Módulo 1) ----------
local ACCENT_MAP = {
  ["\195\129"] = "\195\161", ["\195\137"] = "\195\169", ["\195\141"] = "\195\173",
  ["\195\147"] = "\195\179", ["\195\154"] = "\195\186", ["\195\145"] = "\195\177",
}
local function toLowerEs(str)
  str = string.lower(str)
  for upper, lower in pairs(ACCENT_MAP) do str = str:gsub(upper, lower) end
  return str
end

local function matchesAny(lname, patterns)
  for _, pat in ipairs(patterns) do
    if lname:find(pat) then return true end
  end
  return false
end

local function getStemBusChildren()
  local count = reaper.CountTracks(0)
  local busIdx = nil
  for i = 0, count - 1 do
    local track = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(track)
    if toLowerEs(name) == toLowerEs(STEM_BUS_TRACK_NAME) then busIdx = i break end
  end
  if not busIdx then return {}, nil end
  local busTrack = reaper.GetTrack(0, busIdx)
  local children, runningDepth = {}, 0
  for i = busIdx + 1, count - 1 do
    local track = reaper.GetTrack(0, i)
    table.insert(children, track)
    runningDepth = runningDepth + reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    if runningDepth <= -1 then break end
  end
  return children, busTrack
end

local function classifyTracks()
  local children, busTrack = getStemBusChildren()
  local childSet = {}
  for _, t in ipairs(children) do childSet[t] = true end
  local result = { stems = {}, instrumental = nil, countin = nil, extras = {} }

  for _, track in ipairs(children) do
    local _, tname = reaper.GetTrackName(track)
    local lname = toLowerEs(tname)
    for _, stem in ipairs(STEMS) do
      if matchesAny(lname, stem.patterns) then
        result.stems[stem.name] = track
        break
      end
    end
  end

  local count = reaper.CountTracks(0)
  for i = 0, count - 1 do
    local track = reaper.GetTrack(0, i)
    if track ~= busTrack and not childSet[track] then
      local _, tname = reaper.GetTrackName(track)
      local lname = toLowerEs(tname)
      if matchesAny(lname, INSTRUMENTAL_PATTERNS) then
        result.instrumental = track
      elseif matchesAny(lname, COUNTIN_PATTERNS) then
        result.countin = track
      else
        table.insert(result.extras, track)
      end
    end
  end
  return result
end

local function trackDisplayName(track)
  if not track then return "" end
  local _, n = reaper.GetTrackName(track)
  return n
end

-- ---------- Estado inicial ----------
local cls = classifyTracks()

local function dbToLinear(db) return 10 ^ (db / 20) end

local function muteTrack(track, mute)
  if track then reaper.SetMediaTrackInfo_Value(track, "B_MUTE", mute and 1 or 0) end
end

local function setVol(track, db)
  if track then reaper.SetMediaTrackInfo_Value(track, "D_VOL", dbToLinear(db)) end
end

-- Guarda vol+pan+mute de TODOS los tracks, para restaurar después de cada render
local function saveAllTrackStates()
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

local function restoreAllTrackStates(saved)
  for track, s in pairs(saved) do
    if reaper.ValidatePtr(track, "MediaTrack*") then
      reaper.SetMediaTrackInfo_Value(track, "D_VOL", s.vol)
      reaper.SetMediaTrackInfo_Value(track, "D_PAN", s.pan)
      reaper.SetMediaTrackInfo_Value(track, "B_MUTE", s.mute)
    end
  end
  reaper.UpdateArrange()
end

-- Rango de tiempo de la canción: min posición / max fin entre items de los stems presentes
local function getSongTimeRange()
  local minPos, maxEnd = nil, nil
  for _, track in pairs(cls.stems) do
    local n = reaper.CountTrackMediaItems(track)
    for i = 0, n - 1 do
      local item = reaper.GetTrackMediaItem(track, i)
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local endPos = pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      if not minPos or pos < minPos then minPos = pos end
      if not maxEnd or endPos > maxEnd then maxEnd = endPos end
    end
  end
  return minPos or 0, maxEnd or 0
end

-- Busca, en el track de Count-in, el item con la posición más tardía que sea
-- <= referenceStart (el "click" que precede inmediatamente al comienzo real).
-- Si no hay ninguno, devuelve referenceStart sin modificar (no hay count-in ahí).
local function getCountinStartBefore(referenceStart)
  if not cls.countin then return referenceStart end
  local best = nil
  local n = reaper.CountTrackMediaItems(cls.countin)
  for i = 0, n - 1 do
    local item = reaper.GetTrackMediaItem(cls.countin, i)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    if pos <= referenceStart + 0.001 then -- pequeño margen por redondeo
      if not best or pos > best then best = pos end
    end
  end
  return best or referenceStart
end

local _, savedTonalidad = reaper.GetProjExtState(0, EXT_NAMESPACE, "Tonalidad")
local autoTempo = reaper.TimeMap2_GetDividedBpmAtTime(0, 0)

local state = {
  tonalidad = savedTonalidad ~= "" and savedTonalidad or "",
  tempo = tostring(math.floor(autoTempo + 0.5)),
  tonalidadOriginal = true,
  useTrackNameGlobal = false,
  renderMaster = true,
  masterCountin = true,
  renderKaraoke = true,
  karaokeCountin = true,
  extrasOpen = false,
  extrasOverride = {}, -- [track] = true (audible) / nil o false (muteado, default)
  showSummary = false,
  rows = {},
}

for _, stem in ipairs(STEMS) do
  local track = cls.stems[stem.name]
  state.rows[stem.name] = {
    present = track ~= nil,
    track = track,
    protagonist = track ~= nil,
    backing = (track ~= nil) and stem.hasBacking,
    countin = true,
    nameOverride = "",
    bgDb = tostring(DEFAULT_BACKGROUND_DB),
    offsetSec = "0.0",
  }
end

-- ---------- Helpers de nombre / resumen ----------
local function stemLabel(stemDef, row)
  if row.nameOverride ~= "" then return row.nameOverride end
  if state.useTrackNameGlobal then return trackDisplayName(row.track) end
  return stemDef.label_es
end

local function buildFileList()
  local files = {}
  local tonalidad = state.tonalidad ~= "" and state.tonalidad or "(sin definir)"
  local tempo = state.tempo ~= "" and state.tempo or "(sin definir)"

  if state.renderMaster then
    table.insert(files, { path = string.format("🎵 Master (%s - %s BPM).mp3", tonalidad, tempo),
      desc = "Mezcla completa · " .. (state.masterCountin and "con count-in" or "sin count-in"),
      type = "master" })
  end

  if state.renderKaraoke then
    local karaokeSrc = state.tonalidadOriginal and "fuente: Instrumental (MVSEP)" or "fuente: Stem Bus con Voz muteada"
    table.insert(files, { path = string.format("🎵 Karaoke (%s - %s BPM).mp3", tonalidad, tempo),
      desc = karaokeSrc .. " · " .. (state.karaokeCountin and "con count-in" or "sin count-in"),
      type = "karaoke" })
  end

  for _, stem in ipairs(STEMS) do
    local row = state.rows[stem.name]
    if row.present then
      if row.protagonist then
        local label = stemLabel(stem, row)
        table.insert(files, {
          path = STEMS_SUBFOLDER .. "/🎵 " .. label .. ".mp3",
          desc = string.format("Protagonista (resto a %s dB) · %s", row.bgDb, row.countin and "con count-in" or "sin count-in"),
          type = "stem_protagonist", stemDef = stem, row = row,
        })
      end
      if stem.hasBacking and row.backing then
        local label = stemLabel(stem, row)
        table.insert(files, {
          path = STEMS_SUBFOLDER .. "/🎵 " .. label .. MUTE_SUFFIX .. ".mp3",
          desc = "Backing (mezcla completa sin este instrumento) · " .. (row.countin and "con count-in" or "sin count-in"),
          type = "stem_backing", stemDef = stem, row = row,
        })
      end
    end
  end
  return files
end

-- ---------- Motor de render ----------

-- Extras: muteados por default en todo, salvo override explícito por track
local function applyExtrasDefaults()
  for _, track in ipairs(cls.extras) do
    muteTrack(track, not state.extrasOverride[track])
  end
end

local function applyCountin(active)
  muteTrack(cls.countin, not active)
end

local function applyMasterState()
  applyExtrasDefaults()
  muteTrack(cls.instrumental, true)
  for _, track in pairs(cls.stems) do muteTrack(track, false) end
  applyCountin(state.masterCountin)
end

local function applyKaraokeState()
  applyExtrasDefaults()
  applyCountin(state.karaokeCountin)
  if state.tonalidadOriginal then
    for _, track in pairs(cls.stems) do muteTrack(track, true) end
    muteTrack(cls.instrumental, false)
  else
    muteTrack(cls.instrumental, true)
    for name, track in pairs(cls.stems) do
      muteTrack(track, name == "Vocals")
    end
  end
end

-- Protagonista: instrumento a volumen original, resto a bgDb (texto no numérico = silenciar)
local function applyStemProtagonistState(stemDef, row)
  applyExtrasDefaults()
  muteTrack(cls.instrumental, true)
  applyCountin(row.countin)
  for _, s in ipairs(STEMS) do
    local track = cls.stems[s.name]
    if track then
      if s.name == stemDef.name then
        muteTrack(track, false)
      else
        local db = tonumber(row.bgDb)
        if db then
          muteTrack(track, false)
          setVol(track, db)
        else
          muteTrack(track, true) -- ej: usuario escribió "mute" en vez de un número
        end
      end
    end
  end
end

-- Backing: mezcla completa (volumen original) menos el instrumento protagonista, muteado
local function applyStemBackingState(stemDef, row)
  applyExtrasDefaults()
  muteTrack(cls.instrumental, true)
  applyCountin(row.countin)
  for _, s in ipairs(STEMS) do
    local track = cls.stems[s.name]
    if track then muteTrack(track, s.name == stemDef.name) end
  end
end

local function setRenderBoundsAndPattern(pattern, startPos, endPos)
  reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 0, true) -- 0 = custom time bounds
  reaper.GetSetProjectInfo(0, "RENDER_STARTPOS", startPos, true)
  reaper.GetSetProjectInfo(0, "RENDER_ENDPOS", endPos, true)
  reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", pattern, true)
end

local function triggerRender()
  reaper.Main_OnCommand(42230, 0) -- Render, últimos ajustes usados, cierra diálogo automáticamente
end

-- El script NO toca formato/bitrate (ver notas de la sesión) — solo avisa si no parece MP3.
-- RENDER_FORMAT devuelve texto Base64 (confirmado por hex dump); hay que decodificarlo
-- antes de comparar. El fourcc queda guardado con los bytes invertidos ("mp3l" -> "l3pm",
-- "wave" -> "evaw"), mismo patrón en ambos casos observados.
local B64CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local B64LOOKUP = {}
for i = 1, #B64CHARS do B64LOOKUP[B64CHARS:sub(i, i)] = i - 1 end

local function base64Decode(data)
  data = data:gsub('[^A-Za-z0-9+/=]', '')
  local bytes = {}
  local i = 1
  while i <= #data do
    local c1, c2, c3, c4 = data:sub(i, i), data:sub(i + 1, i + 1), data:sub(i + 2, i + 2), data:sub(i + 3, i + 3)
    local n1, n2 = B64LOOKUP[c1], B64LOOKUP[c2]
    local n3 = (c3 ~= '=' and c3 ~= '') and B64LOOKUP[c3] or nil
    local n4 = (c4 ~= '=' and c4 ~= '') and B64LOOKUP[c4] or nil
    if n1 and n2 then
      table.insert(bytes, string.char(((n1 << 2) | (n2 >> 4)) & 0xFF))
      if n3 then
        table.insert(bytes, string.char((((n2 & 0xF) << 4) | (n3 >> 2)) & 0xFF))
        if n4 then
          table.insert(bytes, string.char((((n3 & 0x3) << 6) | n4) & 0xFF))
        end
      end
    end
    i = i + 4
  end
  return table.concat(bytes)
end

local function looksLikeMp3Format(raw)
  if not raw or raw == "" then return false end
  local ok, decoded = pcall(base64Decode, raw)
  if not ok or not decoded or #decoded < 4 then return false end
  local head = decoded:sub(1, 4):lower()
  return head == "l3pm" or head == "mp3l"
end

local function toHexDump(str)
  local out = {}
  for i = 1, #str do
    table.insert(out, string.format("%02X", str:byte(i)))
  end
  return table.concat(out, " ")
end

local function checkRenderFormat()
  local _, raw = reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT", "", false)
  if not looksLikeMp3Format(raw) then
    reaper.ShowConsoleMsg("[DEBUG] RENDER_FORMAT raw (len=" .. #raw .. "):\n" .. toHexDump(raw) .. "\n" ..
      "(seleccionable acá en la consola — copiar y pegar en el chat si el warning persiste)\n\n")
    local resp = reaper.ShowMessageBox(
      "No se pudo confirmar que el formato de render sea MP3.\n\n" ..
      "Abrí el diálogo de Render (Ctrl+Alt+R), verificá MP3 192kbps y tocá 'Save settings' si hace falta.\n\n¿Renderizar de todos modos?",
      "Verificar formato de render", 4) -- 4 = Yes/No
    if resp ~= 6 then return false end -- 6 = Yes
  end
  return true
end

local function runBatch()
  reaper.ClearConsole()
  if not checkRenderFormat() then return end

  local songStart, songEnd = getSongTimeRange()
  if songEnd <= songStart then
    reaper.ShowMessageBox("No se encontraron items en los stems del 'Stem Bus'. Nada para renderizar.", "Render Song Batch", 0)
    return
  end

  local files = buildFileList()
  local baseline = saveAllTrackStates()

  local ok, err = pcall(function()
    for _, f in ipairs(files) do
      local pattern = f.path:gsub("%.mp3$", "")
      local startPos, endPos = songStart, songEnd
      local countinActive = false
      local isCustomStart = false

      if f.type == "master" then
        applyMasterState()
        countinActive = state.masterCountin
      elseif f.type == "karaoke" then
        applyKaraokeState()
        countinActive = state.karaokeCountin
      elseif f.type == "stem_protagonist" then
        applyStemProtagonistState(f.stemDef, f.row)
        local customStart = tonumber(f.row.offsetSec)
        if customStart and customStart > songStart then
          startPos = customStart -- posición elegida a propósito: sin padding, sin ajuste de count-in
          isCustomStart = true
        else
          countinActive = f.row.countin
        end
      elseif f.type == "stem_backing" then
        applyStemBackingState(f.stemDef, f.row)
        countinActive = f.row.countin
      end

      if countinActive then
        startPos = getCountinStartBefore(startPos)
      end

      if not isCustomStart then
        startPos = startPos - RENDER_PADDING_SECONDS
      end
      endPos = endPos + RENDER_PADDING_SECONDS

      if startPos < 0 then
        reaper.ShowConsoleMsg(string.format(
          "[AVISO] %s: no hay margen antes del inicio (start calculado=%.3f). " ..
          "Reaper clampea esto a 0 igual, así que el transiente puede quedar cortado. " ..
          "Considerá dejar ~%.1fs de margen antes del primer item de Count-in.\n",
          pattern, startPos, RENDER_PADDING_SECONDS))
        startPos = 0
      end

      reaper.ShowConsoleMsg(string.format("[DEBUG] %s | start=%.3f end=%.3f countin=%s custom=%s\n",
        pattern, startPos, endPos, tostring(countinActive), tostring(isCustomStart)))

      setRenderBoundsAndPattern(pattern, startPos, endPos)
      triggerRender()
      restoreAllTrackStates(baseline)
    end
  end)

  restoreAllTrackStates(baseline)

  if ok then
    reaper.ShowMessageBox("Batch terminado: " .. #files .. " archivo(s) renderizado(s).", "Render Song Batch", 0)
  else
    reaper.ShowMessageBox("El batch se interrumpió por un error:\n" .. tostring(err) ..
      "\n\nEl estado original de los tracks fue restaurado.", "Render Song Batch — Error", 0)
  end
end

-- ---------- UI ----------
local ctx = reaper.ImGui_CreateContext('Render Song Batch', reaper.ImGui_ConfigFlags_NoSavedSettings())

local function drawHeader()
  reaper.ImGui_SeparatorText(ctx, "Datos generales")

  reaper.ImGui_SetNextItemWidth(ctx, 140)
  local rv, v = reaper.ImGui_InputText(ctx, "Tonalidad", state.tonalidad)
  if rv then state.tonalidad = v end

  reaper.ImGui_SameLine(ctx, 0, 30)
  reaper.ImGui_SetNextItemWidth(ctx, 80)
  local rv2, v2 = reaper.ImGui_InputText(ctx, "Tempo (BPM)", state.tempo)
  if rv2 then state.tempo = v2 end

  local rvA, vA = reaper.ImGui_Checkbox(ctx, "Tonalidad original (define fuente del Karaoke)", state.tonalidadOriginal)
  if rvA then state.tonalidadOriginal = vA end

  reaper.ImGui_TextDisabled(ctx, "Track de Count-in detectado: " .. (cls.countin and trackDisplayName(cls.countin) or "no encontrado en el proyecto"))

  local rvC, vC = reaper.ImGui_Checkbox(ctx, "Usar nombre de track en vez del nombre en español", state.useTrackNameGlobal)
  if rvC then state.useTrackNameGlobal = vC end
end

local function drawMasterKaraoke()
  reaper.ImGui_SeparatorText(ctx, "Master / Karaoke")
  local flags = reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg()
  if reaper.ImGui_BeginTable(ctx, "master_karaoke_table", 3, flags) then
    reaper.ImGui_TableSetupColumn(ctx, "", reaper.ImGui_TableColumnFlags_WidthFixed(), 90)
    reaper.ImGui_TableSetupColumn(ctx, "Renderizar", reaper.ImGui_TableColumnFlags_WidthFixed(), 90)
    reaper.ImGui_TableSetupColumn(ctx, "Count-in", reaper.ImGui_TableColumnFlags_WidthFixed(), 90)
    reaper.ImGui_TableHeadersRow(ctx)

    reaper.ImGui_TableNextRow(ctx)
    reaper.ImGui_TableNextColumn(ctx)
    reaper.ImGui_Text(ctx, "Master")
    reaper.ImGui_TableNextColumn(ctx)
    local rv1, v1 = reaper.ImGui_Checkbox(ctx, "##render_master", state.renderMaster)
    if rv1 then state.renderMaster = v1 end
    reaper.ImGui_TableNextColumn(ctx)
    if not state.renderMaster then reaper.ImGui_BeginDisabled(ctx, true) end
    local rv2, v2 = reaper.ImGui_Checkbox(ctx, "##countin_master", state.masterCountin)
    if rv2 then state.masterCountin = v2 end
    if not state.renderMaster then reaper.ImGui_EndDisabled(ctx) end

    reaper.ImGui_TableNextRow(ctx)
    reaper.ImGui_TableNextColumn(ctx)
    reaper.ImGui_Text(ctx, "Karaoke")
    reaper.ImGui_TableNextColumn(ctx)
    local rv3, v3 = reaper.ImGui_Checkbox(ctx, "##render_karaoke", state.renderKaraoke)
    if rv3 then state.renderKaraoke = v3 end
    reaper.ImGui_TableNextColumn(ctx)
    if not state.renderKaraoke then reaper.ImGui_BeginDisabled(ctx, true) end
    local rv4, v4 = reaper.ImGui_Checkbox(ctx, "##countin_karaoke", state.karaokeCountin)
    if rv4 then state.karaokeCountin = v4 end
    if not state.renderKaraoke then reaper.ImGui_EndDisabled(ctx) end

    reaper.ImGui_EndTable(ctx)
  end
end

local function drawExtras()
  if reaper.ImGui_CollapsingHeader(ctx, "Extras (" .. #cls.extras .. ") — muteados por default, override disponible") then
    if #cls.extras == 0 then
      reaper.ImGui_TextDisabled(ctx, "No se detectaron tracks extra.")
    else
      for _, track in ipairs(cls.extras) do
        local current = state.extrasOverride[track] or false
        local rv, v = reaper.ImGui_Checkbox(ctx, "Audible en este batch##" .. tostring(track), current)
        reaper.ImGui_SameLine(ctx, 0, 10)
        reaper.ImGui_Text(ctx, trackDisplayName(track))
        if rv then state.extrasOverride[track] = v end
      end
    end
  end
end

local function drawStemsTable()
  reaper.ImGui_SeparatorText(ctx, "Stems")
  local flags = reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg()
  if reaper.ImGui_BeginTable(ctx, "stems_table", 7, flags) then
    reaper.ImGui_TableSetupColumn(ctx, "Instrumento", reaper.ImGui_TableColumnFlags_WidthFixed(), 90)
    reaper.ImGui_TableSetupColumn(ctx, "Prot.", reaper.ImGui_TableColumnFlags_WidthFixed(), 45)
    reaper.ImGui_TableSetupColumn(ctx, "Backing", reaper.ImGui_TableColumnFlags_WidthFixed(), 55)
    reaper.ImGui_TableSetupColumn(ctx, "Count-in", reaper.ImGui_TableColumnFlags_WidthFixed(), 60)
    reaper.ImGui_TableSetupColumn(ctx, "Nombre override", reaper.ImGui_TableColumnFlags_WidthStretch())
    reaper.ImGui_TableSetupColumn(ctx, "Vol. fondo (dB)", reaper.ImGui_TableColumnFlags_WidthFixed(), 95)
    reaper.ImGui_TableSetupColumn(ctx, "Inicio (s)", reaper.ImGui_TableColumnFlags_WidthFixed(), 110)
    reaper.ImGui_TableHeadersRow(ctx)

    for _, stem in ipairs(STEMS) do
      local row = state.rows[stem.name]
      reaper.ImGui_TableNextRow(ctx)

      if not row.present then reaper.ImGui_BeginDisabled(ctx, true) end

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_Text(ctx, stem.label_es .. (row.present and "" or " (ausente)"))

      reaper.ImGui_TableNextColumn(ctx)
      local rv1, v1 = reaper.ImGui_Checkbox(ctx, "##prot_" .. stem.name, row.protagonist)
      if rv1 then row.protagonist = v1 end

      reaper.ImGui_TableNextColumn(ctx)
      if stem.hasBacking then
        local rv2, v2 = reaper.ImGui_Checkbox(ctx, "##back_" .. stem.name, row.backing)
        if rv2 then row.backing = v2 end
      else
        reaper.ImGui_TextDisabled(ctx, "(Karaoke)")
      end

      reaper.ImGui_TableNextColumn(ctx)
      local rvCi, vCi = reaper.ImGui_Checkbox(ctx, "##countin_" .. stem.name, row.countin)
      if rvCi then row.countin = vCi end

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, -1)
      local rv3, v3 = reaper.ImGui_InputTextWithHint(ctx, "##name_" .. stem.name, "(default: " .. stem.label_es .. ")", row.nameOverride)
      if rv3 then row.nameOverride = v3 end

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, -1)
      local rv4, v4 = reaper.ImGui_InputText(ctx, "##bg_" .. stem.name, row.bgDb)
      if rv4 then row.bgDb = v4 end

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, 70)
      local rv5, v5 = reaper.ImGui_InputText(ctx, "##off_" .. stem.name, row.offsetSec)
      if rv5 then row.offsetSec = v5 end
      reaper.ImGui_SameLine(ctx, 0, 6)
      if reaper.ImGui_Button(ctx, "🎯##cursor_" .. stem.name) then
        row.offsetSec = string.format("%.2f", reaper.GetCursorPosition())
      end
      if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Tomar posición actual del cursor de edición")
      end

      if not row.present then reaper.ImGui_EndDisabled(ctx) end
    end
    reaper.ImGui_EndTable(ctx)
  end
end

local function drawSummary()
  reaper.ImGui_SeparatorText(ctx, "Resumen — archivos a generar")
  reaper.ImGui_TextDisabled(ctx, "Revisá la lista antes de confirmar. El render toca el proyecto (mute/vol/pan) y lo restaura al terminar.")
  reaper.ImGui_Spacing(ctx)

  local files = buildFileList()
  if reaper.ImGui_BeginTable(ctx, "summary_table", 2, reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg()) then
    reaper.ImGui_TableSetupColumn(ctx, "Archivo (relativo a Render/)", reaper.ImGui_TableColumnFlags_WidthStretch())
    reaper.ImGui_TableSetupColumn(ctx, "Detalle", reaper.ImGui_TableColumnFlags_WidthFixed(), 260)
    reaper.ImGui_TableHeadersRow(ctx)
    for _, f in ipairs(files) do
      reaper.ImGui_TableNextRow(ctx)
      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_Text(ctx, f.path)
      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_TextWrapped(ctx, f.desc)
    end
    reaper.ImGui_EndTable(ctx)
  end

  reaper.ImGui_Spacing(ctx)
  if reaper.ImGui_Button(ctx, "‹ Volver a editar") then
    state.showSummary = false
  end
  reaper.ImGui_SameLine(ctx, 0, 20)
  if reaper.ImGui_Button(ctx, "Confirmar y renderizar", 220, 32) then
    runBatch()
  end
end

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 760, 620, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, 'Render Song Batch', true)
  if visible then
    if not state.showSummary then
      drawHeader()
      reaper.ImGui_Spacing(ctx)
      drawMasterKaraoke()
      reaper.ImGui_Spacing(ctx)
      drawExtras()
      reaper.ImGui_Spacing(ctx)
      drawStemsTable()
      reaper.ImGui_Spacing(ctx)
      if reaper.ImGui_Button(ctx, "Ver resumen y renderizar", 260, 32) then
        reaper.SetProjExtState(0, EXT_NAMESPACE, "Tonalidad", state.tonalidad)
        state.showSummary = true
      end
    else
      drawSummary()
    end
    reaper.ImGui_End(ctx)
  end
  if open then
    reaper.defer(loop)
  end
end

reaper.defer(loop)
