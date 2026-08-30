-- ============================================================
-- MVSEP Stem Importer
-- Selecciona un .zip descargado de MVSEP, lo descomprime en la
-- carpeta Media del proyecto, normaliza los nombres de archivo
-- y coloca cada stem en su track correspondiente dentro del
-- folder configurado como STEM_BUS_TRACK_NAME.
--
-- Requiere en el sistema: "tar" (Windows 10 1809+, incluido por
-- default) o "unzip" (Mac/Linux, normalmente preinstalado).
-- ============================================================

-- ================== CONFIG ==================
local STEM_BUS_TRACK_NAME = "Stem Bus" -- debe matchear EXACTO el nombre de tu folder track
local MEDIA_SUBFOLDER = "Media"        -- subcarpeta relativa a la carpeta del .rpp
local INSTRUMENTAL_PATTERNS = {"instrum"} -- cubre "instrum" e "instrumental"
local ZOOM_PADDING_BARS = 4 -- compases de aire a la derecha del zoom-fit, para desplazar luego (count-in, tempo mapping)
local SAVE_SCREENSET_COMMAND_ID = 40464 -- "Screenset: Save track view #01" (pisa el screenset nombrado "ALL")

-- Familias reconocidas (ampliá/ajustá patterns si MVSEP nombra distinto)
local STEMS = {
  { name = "Vocals", patterns = {"vocal"} },
  { name = "Drums",  patterns = {"drum"} },
  { name = "Bass",   patterns = {"bass"} },
  { name = "Guitar", patterns = {"guitar", "gtr", "%f[%a]gt%f[%A]"} },
  { name = "Piano",  patterns = {"piano", "keys"} },
  { name = "Other",  patterns = {"other"} },
}

local AUDIO_EXTENSIONS = {"wav", "mp3", "flac"} -- extensiones válidas a procesar
-- ==============================================

-- Decodifica un string UTF-8 a una tabla de codepoints Unicode
local function utf8ToCodepoints(str)
  local codepoints = {}
  local i = 1
  local len = #str
  while i <= len do
    local b1 = str:byte(i)
    local cp, size
    if b1 < 0x80 then
      cp, size = b1, 1
    elseif b1 >= 0xF0 then
      local b2, b3, b4 = str:byte(i + 1, i + 3)
      cp = ((b1 - 0xF0) * 262144) + ((b2 - 0x80) * 4096) + ((b3 - 0x80) * 64) + (b4 - 0x80)
      size = 4
    elseif b1 >= 0xE0 then
      local b2, b3 = str:byte(i + 1, i + 2)
      cp = ((b1 - 0xE0) * 4096) + ((b2 - 0x80) * 64) + (b3 - 0x80)
      size = 3
    elseif b1 >= 0xC0 then
      local b2 = str:byte(i + 1)
      cp = ((b1 - 0xC0) * 64) + (b2 - 0x80)
      size = 2
    else
      cp, size = b1, 1 -- byte inválido, se toma literal
    end
    table.insert(codepoints, cp)
    i = i + size
  end
  return codepoints
end

-- Codifica codepoints a bytes UTF-16LE (con soporte de surrogate pairs)
local function codepointsToUtf16LE(codepoints)
  local bytes = {}
  for _, cp in ipairs(codepoints) do
    if cp < 0x10000 then
      table.insert(bytes, string.char(cp % 256))
      table.insert(bytes, string.char(math.floor(cp / 256) % 256))
    else
      cp = cp - 0x10000
      local hi = 0xD800 + math.floor(cp / 1024)
      local lo = 0xDC00 + (cp % 1024)
      table.insert(bytes, string.char(hi % 256))
      table.insert(bytes, string.char(math.floor(hi / 256) % 256))
      table.insert(bytes, string.char(lo % 256))
      table.insert(bytes, string.char(math.floor(lo / 256) % 256))
    end
  end
  return table.concat(bytes)
end

-- Codificador Base64 estándar, sin dependencias externas
local B64CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64Encode(data)
  local result = {}
  for i = 1, #data, 3 do
    local b1, b2, b3 = data:byte(i, i + 2)
    b2 = b2 or 0
    b3 = b3 or 0
    local n = b1 * 65536 + b2 * 256 + b3
    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64
    table.insert(result, B64CHARS:sub(c1 + 1, c1 + 1))
    table.insert(result, B64CHARS:sub(c2 + 1, c2 + 1))
    table.insert(result, (#data - i >= 1) and B64CHARS:sub(c3 + 1, c3 + 1) or '=')
    table.insert(result, (#data - i >= 2) and B64CHARS:sub(c4 + 1, c4 + 1) or '=')
  end
  return table.concat(result)
end

-- Arma un -EncodedCommand a partir de un comando PowerShell en UTF-8.
-- Como el argumento final que recibe CreateProcess es Base64 (solo
-- ASCII), la conversión a codepage ANSI de Windows no puede corromper
-- tildes/ñ: el string acentuado nunca viaja como argv, viaja codificado.
local function toPowershellEncodedCommand(psCommand)
  local codepoints = utf8ToCodepoints(psCommand)
  local utf16bytes = codepointsToUtf16LE(codepoints)
  return base64Encode(utf16bytes)
end

local function getOS()
  return reaper.GetOS()
end

-- Devuelve la carpeta de Descargas del usuario para usarla como
-- directorio inicial del selector de archivos
local function getDownloadsPath()
  if getOS():find("Win") then
    local home = os.getenv("USERPROFILE")
    if home then return home .. "\\Descargas\\" end
  else
    local home = os.getenv("HOME")
    if home then return home .. "/Descargas/" end
  end
  return ""
end

-- Devuelve el directorio donde está guardado el .rpp (NO usar
-- GetProjectPath, que devuelve el recording path, ej: .../Media)
local function getProjectDir()
  local _, projfn = reaper.EnumProjects(-1, "")
  if not projfn or projfn == "" then
    return nil, "El proyecto no está guardado (no tiene .rpp asociado todavía)"
  end
  local dir = projfn:match("^(.*)[/\\][^/\\]+$")
  if not dir then
    return nil, "No se pudo determinar la carpeta del proyecto"
  end
  return dir
end

local function ensureDir(path)
  -- reaper.RecursiveCreateDirectory maneja UTF-8 nativamente,
  -- evitando el problema de codepage de cmd.exe con tildes/ñ
  reaper.RecursiveCreateDirectory(path, 0)
end

-- Marca la carpeta Media como "Elementos generales" en el explorador
-- de Windows, escribiendo el desktop.ini que Explorer espera para
-- ese tipo de vista (equivale al toggle manual en Propiedades >
-- Personalizar). No-op en Mac/Linux.
local function applyMediaFolderView(path)
  if not getOS():find("Win") then return end

  local iniPath = path .. "/desktop.ini"
  local f = io.open(iniPath, "w")
  if not f then return end
  f:write("[ViewState]\r\nMode=\r\nVid=\r\nFolderType=Generic\r\n")
  f:close()

  -- Hidden+System en desktop.ini y ReadOnly en la carpeta: es la
  -- combinación que Windows Explorer necesita para respetar FolderType
  local psCmd = string.format(
    '(Get-Item -LiteralPath "%s" -Force).Attributes = "Hidden,System"; ' ..
    '$f = Get-Item -LiteralPath "%s" -Force; ' ..
    '$f.Attributes = $f.Attributes -bor [System.IO.FileAttributes]::ReadOnly',
    iniPath, path)
  local encoded = toPowershellEncodedCommand(psCmd)
  local cmd = string.format(
    'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand %s 2>&1',
    encoded)
  local handle = io.popen(cmd)
  if handle then
    local out = handle:read("*a")
    local closeOk = handle:close()
    if not closeOk then
      reaper.ShowConsoleMsg("---- Salida al setear atributos de Media ----\n" .. (out or "(sin salida)") .. "\n----------------------------------------------\n")
    end
  end
end

local function extractZip(zipPath, destPath)
  local os_str = getOS()
  local cmd
  if os_str:find("Win") then
    -- Expand-Archive (.NET) maneja Unicode nativamente. El comando
    -- viaja como -EncodedCommand (Base64/UTF-16LE) para que el string
    -- con tildes/ñ nunca pase como argumento de línea de comandos
    -- (evita la conversión a codepage ANSI de CreateProcess)
    local psCmd = string.format(
      'Expand-Archive -LiteralPath "%s" -DestinationPath "%s" -Force',
      zipPath, destPath)
    local encoded = toPowershellEncodedCommand(psCmd)
    cmd = string.format(
      'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand %s 2>&1',
      encoded)
  else
    cmd = string.format('unzip -o "%s" -d "%s" 2>&1', zipPath, destPath)
  end

  local handle = io.popen(cmd)
  local output = handle:read("*a")
  local closeOk = handle:close()

  if not closeOk then
    reaper.ShowConsoleMsg("---- Salida de extracción ----\n" .. (output or "(sin salida)") .. "\n-------------------------------\n")
  end

  return closeOk, output
end

local function detectStem(name)
  local lname = name:lower()
  for _, stem in ipairs(STEMS) do
    for _, pat in ipairs(stem.patterns) do
      if lname:find(pat) then
        return stem
      end
    end
  end
  return nil
end

local function isInstrumental(name)
  local lname = name:lower()
  for _, pat in ipairs(INSTRUMENTAL_PATTERNS) do
    if lname:find(pat) then return true end
  end
  return false
end

-- Busca, por patrón (isInstrumental), el track Instrumental en TODO
-- el proyecto -- es un track hermano, no un hijo del folder Stem Bus
local function findInstrumentalTrack()
  local count = reaper.CountTracks(0)
  for i = 0, count - 1 do
    local track = reaper.GetTrack(0, i)
    local _, tname = reaper.GetTrackName(track)
    if isInstrumental(tname) then return track end
  end
  return nil
end

local function getExtension(filename)
  return filename:match("%.([%w]+)$") or "wav"
end

local function isAudioFile(filename)
  local ext = filename:match("%.([%w]+)$")
  if not ext then return false end
  ext = ext:lower()
  for _, allowed in ipairs(AUDIO_EXTENSIONS) do
    if ext == allowed then return true end
  end
  return false
end

-- Encuentra el track STEM_BUS_TRACK_NAME y devuelve sus hijos directos/anidados
local function getStemBusChildren()
  local count = reaper.CountTracks(0)
  local busIdx = nil
  for i = 0, count - 1 do
    local track = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(track)
    if name == STEM_BUS_TRACK_NAME then
      busIdx = i
      break
    end
  end
  if not busIdx then
    return nil, "No se encontró el track '" .. STEM_BUS_TRACK_NAME .. "'"
  end

  local busTrack = reaper.GetTrack(0, busIdx)
  local depth = reaper.GetMediaTrackInfo_Value(busTrack, "I_FOLDERDEPTH")
  if depth <= 0 then
    return nil, "'" .. STEM_BUS_TRACK_NAME .. "' no está configurado como folder (I_FOLDERDEPTH <= 0)"
  end

  local children = {}
  local runningDepth = 0
  for i = busIdx + 1, count - 1 do
    local track = reaper.GetTrack(0, i)
    table.insert(children, track)
    runningDepth = runningDepth + reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    if runningDepth <= -1 then break end
  end
  return children
end

local function insertItemOnTrack(track, filepath)
  local source = reaper.PCM_Source_CreateFromFile(filepath)
  if not source then return false end
  local item = reaper.AddMediaItemToTrack(track)
  local take = reaper.AddTakeToMediaItem(item)
  reaper.SetMediaItemTake_Source(take, source)
  local length = reaper.GetMediaSourceLength(source)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", length)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", 0)
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", filepath:match("([^/\\]+)$"), true)
  return true, length
end

local function main()
  local ok, zipPath = reaper.GetUserFileNameForRead(getDownloadsPath(), "Seleccioná el .zip de MVSEP", "zip")
  if not ok or zipPath == "" then return end

  local projDir, projErr = getProjectDir()
  if not projDir then
    reaper.ShowMessageBox(projErr, "Error", 0)
    return
  end
  local mediaPath = projDir .. "/" .. MEDIA_SUBFOLDER
  ensureDir(mediaPath)
  applyMediaFolderView(mediaPath)

  local extractOk, extractOutput = extractZip(zipPath, mediaPath)
  if not extractOk then
    reaper.ShowMessageBox(
      "Falló la descompresión. Abrí View > Show console output en REAPER para ver el error exacto.",
      "Error", 0)
    return
  end

  local children, err = getStemBusChildren()
  if not children then
    reaper.ShowMessageBox(err, "Error", 0)
    return
  end

  local placed, unmatched = {}, {}
  local refItemLength = nil
  local i = 0
  while true do
    local fn = reaper.EnumerateFiles(mediaPath, i)
    if not fn then break end
    i = i + 1

    if isAudioFile(fn) then
      if isInstrumental(fn) then
        local ext = getExtension(fn)
        local newName = "Instrumental." .. ext
        local oldFull = mediaPath .. "/" .. fn
        local newFull = mediaPath .. "/" .. newName

        if oldFull ~= newFull then
          os.remove(newFull)
          os.rename(oldFull, newFull)
        end

        local targetTrack = findInstrumentalTrack()
        if targetTrack then
          local _, length = insertItemOnTrack(targetTrack, newFull)
          refItemLength = refItemLength or length
          table.insert(placed, "Instrumental")
        else
          table.insert(unmatched, newName .. " (sin track destino: ningún track matchea patrón 'instrum')")
        end
      else
        local stem = detectStem(fn)
        if stem then
          local ext = getExtension(fn)
          local newName = stem.name .. "." .. ext
          local oldFull = mediaPath .. "/" .. fn
          local newFull = mediaPath .. "/" .. newName

          if oldFull ~= newFull then
            os.remove(newFull)
            os.rename(oldFull, newFull)
          end

          local targetTrack = nil
          for _, track in ipairs(children) do
            local _, tname = reaper.GetTrackName(track)
            if detectStem(tname) == stem then
              targetTrack = track
              break
            end
          end

          if targetTrack then
            local _, length = insertItemOnTrack(targetTrack, newFull)
            refItemLength = refItemLength or length
            table.insert(placed, stem.name)
          else
            table.insert(unmatched, newName .. " (sin track destino)")
          end
        else
          table.insert(unmatched, fn .. " (familia no reconocida)")
        end
      end
    end
  end

  reaper.Main_OnCommand(40047, 0) -- Peaks: Build any missing peaks
  reaper.UpdateArrange()

  if refItemLength then
    local timesig_num, timesig_denom = reaper.TimeMap_GetTimeSigAtTime(0, 0.0)
    local qnPerBar = timesig_num * (4 / timesig_denom)
    local paddingQN = ZOOM_PADDING_BARS * qnPerBar
    local paddingTime = reaper.TimeMap2_beatsToTime(0, paddingQN)
    local endTime = refItemLength + paddingTime
    reaper.BR_SetArrangeView(0, 0, endTime)
    reaper.Main_OnCommand(SAVE_SCREENSET_COMMAND_ID, 0) -- Screenset: Save track view #01 (pisa "ALL")
  end

  local msg = "Importados: " .. (#placed > 0 and table.concat(placed, ", ") or "ninguno")
  if #unmatched > 0 then
    msg = msg .. "\n\nSin track correspondiente: " .. table.concat(unmatched, ", ")
  end
  --reaper.ShowMessageBox(msg, "MVSEP Import", 0)
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Import MVSEP stems", -1)
