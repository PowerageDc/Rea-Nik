-- Nik_ProjectFolder_CollectSamples.lua
-- Recorre las pestañas abiertas y copia a <carpeta del .rpp>\Media\Samples
-- los archivos que usan los FX con lista de archivos (ReaSamplOmatic5000,
-- ReaVerb, etc.) y que están fuera de la carpeta del proyecto.
-- Solo Windows.

local RELINK = false                    -- true: apunta el FX a la copia
local SAMPLES_SUBFOLDER = "Media\\Samples"
local FOLDER_VIEW = "Documents"

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local FV = dofile(script_dir .. "../_Shared/FolderView_common_logic.lua")

local function msg(s) reaper.ShowConsoleMsg(s .. "\n") end
local function norm(p) return (p:gsub("/", "\\")) end
local function basename(p) return p:match("([^/\\]+)$") end
local function psQuote(s) return "'" .. (s:gsub("'", "''")) .. "'" end

local function is_inside(path, dir)
  local a = norm(path):lower()
  local b = norm(dir):lower() .. "\\"
  return a:sub(1, #b) == b
end

-- Todos los archivos que declaran los FX de las pistas del proyecto.
-- No se filtra por nombre de FX: una instancia renombrada igual responde.
local function find_files(proj)
  local found = {}
  for t = 0, reaper.CountTracks(proj) - 1 do
    local tr = reaper.GetTrack(proj, t)
    local _, tname = reaper.GetTrackName(tr)
    for fx = 0, reaper.TrackFX_GetCount(tr) - 1 do
      local i = 0
      while true do
        local ok, path = reaper.TrackFX_GetNamedConfigParm(tr, fx, "FILE" .. i)
        if not ok or path == "" then break end
        found[#found + 1] = { tr = tr, tname = tname, fx = fx, idx = i, src = path }
        i = i + 1
      end
    end
  end
  return found
end

-- jobs = array de { src, dest }. Devuelve un mapa dest -> estado
-- (COPIED, SAME, DIFF o ERROR). Una sola llamada a PowerShell por proyecto.
local function copy_jobs(jobs)
  local items = {}
  for _, j in ipairs(jobs) do
    items[#items + 1] = psQuote(j.src .. "|" .. j.dest)
  end
  local ps = string.format([==[
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$jobs = @(%s)
foreach ($j in $jobs) {
  $s, $d = $j.Split('|')
  try {
    if (Test-Path -LiteralPath $d) {
      if ((Get-Item -LiteralPath $d).Length -eq (Get-Item -LiteralPath $s).Length) { Write-Output "SAME|$d" }
      else { Write-Output "DIFF|$d" }
    } else {
      Copy-Item -LiteralPath $s -Destination $d
      Write-Output "COPIED|$d"
    }
  } catch { Write-Output ("ERROR|" + $d + "|" + $_.Exception.Message) }
}
]==], table.concat(items, ","))

  local code, out = FV.run_powershell(ps, 0)
  local status = {}
  if code ~= "0" then
    msg("  Error al copiar: " .. tostring(out))
    return status
  end
  out = out:gsub("\239\187\191", "")
  for line in out:gmatch("[^\r\n]+") do
    local st, dest, extra = line:match("^(%u+)|([^|]*)|?(.*)$")
    if st then status[dest] = { st = st, extra = extra } end
  end
  return status
end

local function process_project(proj, projfn)
  local projdir = projfn:match("^(.*)[/\\][^/\\]+$")
  local dest_dir = projdir .. "\\" .. SAMPLES_SUBFOLDER
  msg("Proyecto: " .. projfn)

  local jobs, by_dest, targets = {}, {}, {}
  for _, f in ipairs(find_files(proj)) do
    local tag = string.format("[%s] FX %d FILE%d", f.tname, f.fx, f.idx)
    if not reaper.file_exists(f.src) then
      msg("  " .. tag .. ": no existe, se omite: " .. f.src)
    elseif is_inside(f.src, projdir) then
      msg("  " .. tag .. ": ya está dentro del proyecto")
    else
      local dest = dest_dir .. "\\" .. basename(f.src)
      local prev = by_dest[dest]
      if prev and prev ~= f.src then
        msg("  " .. tag .. ": mismo nombre que otro sample distinto, se omite: " .. f.src)
      else
        if not prev then
          by_dest[dest] = f.src
          jobs[#jobs + 1] = { src = f.src, dest = dest }
        end
        f.dest = dest
        targets[#targets + 1] = f
      end
    end
  end

  if #jobs == 0 then return end

  local ok, err = FV.ensure_folder(dest_dir, FOLDER_VIEW)
  if not ok then
    msg("  No se pudo preparar la carpeta Samples: " .. tostring(err))
    return
  end

  local status = copy_jobs(jobs)
  for _, j in ipairs(jobs) do
    local s = status[j.dest]
    local label = s and s.st or "SIN RESPUESTA"
    if s and s.st == "ERROR" then label = label .. " (" .. s.extra .. ")" end
    if s and s.st == "DIFF" then
      label = "DIFF (ya hay un archivo con otro tamaño, no se pisó)"
    end
    msg(string.format("  %s: %s", label, j.dest))
  end

  if RELINK then
    for _, f in ipairs(targets) do
      local s = status[f.dest]
      if s and (s.st == "COPIED" or s.st == "SAME") then
        reaper.TrackFX_SetNamedConfigParm(f.tr, f.fx, "FILE" .. f.idx, f.dest)
        reaper.TrackFX_SetNamedConfigParm(f.tr, f.fx, "DONE", "")
        reaper.MarkProjectDirty(proj)
      end
    end
  end
end

local function main()
  if not reaper.GetOS():find("Win") then
    reaper.MB("Este script solo funciona en Windows.", "CollectSamples", 0)
    return
  end
  reaper.ClearConsole()
  local i = 0
  while true do
    local proj, projfn = reaper.EnumProjects(i)
    if not proj then break end
    i = i + 1
    if projfn == "" then
      msg("Pestaña " .. i .. ": sin guardar, se omite")
    else
      process_project(proj, projfn)
    end
  end
  msg("Listo.")
end

main()