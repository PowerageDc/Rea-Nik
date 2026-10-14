-- MvsepImporter_common_logic.lua
-- Capa de sistema del importer de MVSEP: ejecución de PowerShell con
-- comandos codificados, ruta de Descargas, carpeta del proyecto y
-- carpeta Media. No conoce stems, tracks ni recetas.

local M = {}

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

return M
