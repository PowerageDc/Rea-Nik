-- FolderView_common_logic.lua
-- Crea una carpeta y le fija la vista del Explorador de Windows
-- (desktop.ini + atributos), para que no la pase a vista Música.
-- No-op de vista en Mac/Linux.

local M = {}

local function is_windows()
  return reaper.GetOS():find("Win") ~= nil
end

local function psQuote(s)
  return "'" .. (s:gsub("'", "''")) .. "'"
end

local function utf8ToCodepoints(str)
  local cps, i, len = {}, 1, #str
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
      cp, size = b1, 1
    end
    cps[#cps + 1] = cp
    i = i + size
  end
  return cps
end

local function codepointsToUtf16LE(cps)
  local bytes = {}
  for _, cp in ipairs(cps) do
    if cp < 0x10000 then
      bytes[#bytes + 1] = string.char(cp % 256, math.floor(cp / 256) % 256)
    else
      cp = cp - 0x10000
      local hi = 0xD800 + math.floor(cp / 1024)
      local lo = 0xDC00 + (cp % 1024)
      bytes[#bytes + 1] = string.char(hi % 256, math.floor(hi / 256) % 256,
        lo % 256, math.floor(lo / 256) % 256)
    end
  end
  return table.concat(bytes)
end

local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64Encode(data)
  local out = {}
  for i = 1, #data, 3 do
    local b1, b2, b3 = data:byte(i, i + 2)
    local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)
    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64
    out[#out + 1] = B64:sub(c1 + 1, c1 + 1)
    out[#out + 1] = B64:sub(c2 + 1, c2 + 1)
    out[#out + 1] = b2 and B64:sub(c3 + 1, c3 + 1) or '='
    out[#out + 1] = b3 and B64:sub(c4 + 1, c4 + 1) or '='
  end
  return table.concat(out)
end

-- Ejecuta un comando PowerShell sin ventana. El comando viaja en Base64
-- (-EncodedCommand), así que tildes y ñ no pasan por la codepage ANSI.
-- Devuelve (código de salida como string, salida de texto) o (nil, nil).
function M.run_powershell(psCommand, timeoutMs)
  local encoded = base64Encode(codepointsToUtf16LE(utf8ToCodepoints(psCommand)))
  local cmd = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' .. encoded
  local ret = reaper.ExecProcess(cmd, timeoutMs or 0)
  if not ret then return nil, nil end
  local code, out = ret:match("^(%-?%d+)\r?\n?(.*)$")
  return code, out or ret
end

-- Crea la carpeta (y los padres que falten) y, si todavía no tiene
-- desktop.ini, lo escribe y fija los atributos que Explorer necesita.
-- folder_type: "Documents", "Generic", etc. (solo letras y números).
-- Devuelve (true) o (false, mensaje).
function M.ensure_folder(path, folder_type)
  folder_type = folder_type or "Documents"
  if not folder_type:match("^%w+$") then
    return false, "folder_type inválido: " .. tostring(folder_type)
  end

  reaper.RecursiveCreateDirectory(path, 0)
  if not is_windows() then return true end
  if reaper.file_exists(path .. "/desktop.ini") then return true end

  local ps = string.format([==[
$ErrorActionPreference = 'Stop'
$p = %s
$ini = Join-Path $p 'desktop.ini'
$txt = "[ViewState]`r`nMode=`r`nVid=`r`nFolderType=%s`r`n"
[System.IO.File]::WriteAllText($ini, $txt, [System.Text.Encoding]::ASCII)
(Get-Item -LiteralPath $ini -Force).Attributes = 'Hidden,System'
$f = Get-Item -LiteralPath $p -Force
$f.Attributes = $f.Attributes -bor [System.IO.FileAttributes]::ReadOnly -bor [System.IO.FileAttributes]::System
]==], psQuote(path:gsub("/", "\\")), folder_type)

  local code, out = M.run_powershell(ps, 15000)
  if code ~= "0" then
    return false, out or "(sin salida)"
  end
  return true
end

return M