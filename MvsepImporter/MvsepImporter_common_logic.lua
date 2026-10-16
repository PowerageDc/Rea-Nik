-- MvsepImporter_common_logic.lua
-- Lógica compartida de los scripts del importer de MVSEP: capa de
-- sistema (PowerShell, rutas, zips), clasificación de archivos por
-- familia de stem y colocación de items en el folder Stem Bus.

local M = {}

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local CFG = dofile(script_dir .. "MvsepImporter_config.lua")
local StemBus = dofile(script_dir .. "../_Shared/StemBus_common_logic.lua")

M.config = CFG

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
function M.to_powershell_encoded_command(psCommand)
  local codepoints = utf8ToCodepoints(psCommand)
  local utf16bytes = codepointsToUtf16LE(codepoints)
  return base64Encode(utf16bytes)
end

function M.is_windows()
  return reaper.GetOS():find("Win") ~= nil
end

-- Ejecuta un comando PowerShell sin ventana. timeoutMs = 0 espera sin
-- límite. Devuelve (código de salida como string, salida de texto), o
-- (nil, nil) si no se pudo lanzar el proceso.
function M.run_powershell(psCommand, timeoutMs)
  local cmd = string.format(
    'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand %s',
    M.to_powershell_encoded_command(psCommand))
  local ret = reaper.ExecProcess(cmd, timeoutMs or 0)
  if not ret then return nil, nil end
  local code, out = ret:match("^(%-?%d+)\r?\n?(.*)$")
  return code, out or ret
end

-- Devuelve la carpeta de Descargas del usuario para usarla como
-- directorio inicial del selector de archivos
function M.get_downloads_path()
  if M.is_windows() then
    -- Lee la ruta real de Descargas del registro (respeta redirecciones
    -- y no depende del idioma de Windows). Salida forzada a UTF-8 para
    -- no corromper tildes/ñ en la ruta.
    local psCmd = [==[
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$p = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders').'{374DE290-123F-4565-9164-39C4925E467B}'
[Environment]::ExpandEnvironmentVariables($p)
]==]
    local _, out = M.run_powershell(psCmd, 10000)
    if out then
      local path = ""
      for line in out:gmatch("[^\r\n]+") do
        if line:match("^%a:[/\\]") or line:match("^\\\\") then
          path = line:gsub("%s+$", "")
          break
        end
      end
      if path ~= "" then
        if not path:match("[/\\]$") then path = path .. "\\" end
        return path
      end
    end
    -- Fallback: ubicación por defecto de Windows
    local home = os.getenv("USERPROFILE")
    if home then return home .. "\\Downloads\\" end
  else
    local home = os.getenv("HOME")
    if home then return home .. "/Downloads/" end
  end
  return ""
end

-- Devuelve el directorio donde está guardado el .rpp (NO usar
-- GetProjectPath, que devuelve el recording path, ej: .../Media)
function M.get_project_dir()
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

-- Marca la carpeta como "Elementos generales" en el explorador de
-- Windows, escribiendo el desktop.ini que Explorer espera para ese tipo
-- de vista (equivale al toggle manual en Propiedades > Personalizar).
-- No-op en Mac/Linux.
local function applyMediaFolderView(path)
  if not M.is_windows() then return end

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
  local code, out = M.run_powershell(psCmd, 15000)
  if code ~= "0" then
    reaper.ShowConsoleMsg("---- Salida al setear atributos de Media ----\n" .. (out or "(sin salida)") .. "\n----------------------------------------------\n")
  end
end

-- Crea la carpeta de medios del proyecto si falta y devuelve su ruta. La
-- vista de Explorer se aplica solo si la carpeta todavía no tiene su
-- desktop.ini, para no reescribirlo en cada importación.
function M.ensure_media_folder(project_dir, subfolder)
  local media_path = project_dir .. "/" .. subfolder
  -- RecursiveCreateDirectory maneja UTF-8 nativamente, evitando el
  -- problema de codepage de cmd.exe con tildes/ñ
  reaper.RecursiveCreateDirectory(media_path, 0)
  if not reaper.file_exists(media_path .. "/desktop.ini") then
    applyMediaFolderView(media_path)
  end
  return media_path
end

local function psQuote(s)
  return "'" .. (s:gsub("'", "''")) .. "'"
end

local ZIP_PS_PREAMBLE = [==[
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.IO.Compression.FileSystem
]==]

-- Lista los archivos del zip sin extraer nada. Devuelve un array de
-- { full = ruta interna, name = nombre de archivo sin carpeta }, o
-- (nil, mensaje de error).
function M.list_zip_entries(zip_path, extensions)
  local out
  if M.is_windows() then
    local quoted = {}
    for _, ext in ipairs(extensions or {}) do table.insert(quoted, psQuote(ext)) end
    local ps = ZIP_PS_PREAMBLE .. string.format([==[
$exts = @(%s)
$zip = [System.IO.Compression.ZipFile]::OpenRead(%s)
try {
  $count = 0
  foreach ($e in $zip.Entries) {
    if ($e.Name -eq '') { continue }
    $ext = [System.IO.Path]::GetExtension($e.Name).TrimStart('.')
    if ($exts.Count -gt 0 -and ($exts -notcontains $ext)) { continue }
    Write-Output $e.FullName
    $count++
    if ($count -ge 200) { break }
  }
} catch {
  Write-Output $_.Exception.Message
  exit 1
} finally {
  $zip.Dispose()
}
]==], table.concat(quoted, ","), psQuote(zip_path))
    local t0 = reaper.time_precise()
    local code, text = M.run_powershell(ps, 30000)
    if code ~= "0" then
      return nil, string.format("código de salida: %s, tiempo: %.1f s\n%s",
        tostring(code), reaper.time_precise() - t0, text or "(sin salida)")
    end
    out = text
  else
    local handle = io.popen(string.format('unzip -Z1 "%s" 2>&1', zip_path))
    if not handle then return nil, "No se pudo ejecutar unzip" end
    out = handle:read("*a")
    if not handle:close() then return nil, out end
  end

  out = out:gsub("\239\187\191", "")
  local entries = {}
  for line in out:gmatch("[^\r\n]+") do
    if not line:match("/$") then
      table.insert(entries, { full = line, name = line:match("([^/\\]+)$") or line })
    end
  end
  return entries
end

-- Extrae entradas puntuales del zip directo a su ruta final.
-- jobs = array de { entry = ruta interna, dest = ruta de destino }.
-- Devuelve (ok, salida); si falla, vuelca la salida a la consola.
function M.extract_zip_entries(zip_path, jobs)
  if #jobs == 0 then return true, "" end
  local ok, output

  if M.is_windows() then
    local lines = {}
    for _, j in ipairs(jobs) do
      table.insert(lines, string.format("  %s = %s", psQuote(j.entry), psQuote(j.dest)))
    end
    local ps = ZIP_PS_PREAMBLE .. string.format([==[
$jobs = @{
%s
}
$zip = [System.IO.Compression.ZipFile]::OpenRead(%s)
try {
  foreach ($k in $jobs.Keys) {
    $e = $zip.GetEntry($k)
    if ($null -eq $e) { throw "Entrada no encontrada en el zip: $k" }
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $jobs[$k], $true)
  }
} catch {
  Write-Output $_.Exception.Message
  exit 1
} finally {
  $zip.Dispose()
}
]==], table.concat(lines, "\n"), psQuote(zip_path))
    local code, text = M.run_powershell(ps, 0)
    ok, output = (code == "0"), text
  else
    ok, output = true, ""
    for _, j in ipairs(jobs) do
      local res = os.execute(string.format('unzip -p "%s" "%s" > "%s"', zip_path, j.entry, j.dest))
      if res ~= true and res ~= 0 then
        ok = false
        output = output .. "Falló la extracción de: " .. j.entry .. "\n"
      end
    end
  end

  if not ok then
    reaper.ShowConsoleMsg("---- Salida de extracción ----\n" .. (output or "(sin salida)") .. "\n-------------------------------\n")
  end
  return ok, output
end

local function matchesAny(name, patterns)
  local lname = name:lower()
  for _, pat in ipairs(patterns) do
    if lname:find(pat) then return true end
  end
  return false
end

-- Devuelve la entrada de CFG.stems cuyo patrón coincide con el nombre
function M.detect_stem(name)
  for _, stem in ipairs(CFG.stems) do
    if matchesAny(name, stem.patterns) then return stem end
  end
  return nil
end

function M.is_instrumental(name)
  return matchesAny(name, CFG.instrumental_patterns)
end

function M.get_extension(filename)
  return filename:match("%.([%w]+)$") or "wav"
end

function M.is_audio_file(filename)
  local ext = filename:match("%.([%w]+)$")
  if not ext then return false end
  ext = ext:lower()
  for _, allowed in ipairs(CFG.audio_extensions) do
    if ext == allowed then return true end
  end
  return false
end

-- Devuelve los hijos del folder Stem Bus, o (nil, mensaje de error)
function M.get_stem_bus_children()
  local bus = StemBus.find_bus_track()
  if not bus then
    return nil, "No se encontró el track 'Stem Bus'"
  end
  if reaper.GetMediaTrackInfo_Value(bus, "I_FOLDERDEPTH") <= 0 then
    return nil, "'Stem Bus' no está configurado como folder (I_FOLDERDEPTH <= 0)"
  end
  return StemBus.get_folder_children(bus)
end

-- Inserta en el track un item con el archivo completo, en la posición
-- dada (segundos, 0 por defecto). Devuelve (item, largo del source), o
-- nil si no se pudo crear el source.
function M.insert_audio_item(track, filepath, position)
  local source = reaper.PCM_Source_CreateFromFile(filepath)
  if not source then return nil end
  local item = reaper.AddMediaItemToTrack(track)
  local take = reaper.AddTakeToMediaItem(item)
  reaper.SetMediaItemTake_Source(take, source)
  local length = reaper.GetMediaSourceLength(source)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", length)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", position or 0)
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", filepath:match("([^/\\]+)$"), true)
  return item, length
end

return M
