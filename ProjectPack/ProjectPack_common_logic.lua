-- ProjectPack_common_logic.lua
-- Empaquetado en lote de las pestañas abiertas: chequeos previos, destino, plan
-- de proyectos a zipear y zipeo asíncrono con validación. Solo Windows.

local M = {}

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "ProjectPack_config.lua")
local FolderConfig = dofile(script_dir .. "../ProjectFolder/ProjectFolder_config.lua")
local Paths = dofile(script_dir .. "../_Shared/ProjectPaths_common_logic.lua")
local FV = dofile(script_dir .. "../_Shared/FolderView_common_logic.lua")

M.config = Config

-- Carpeta de destino de los zips: dest_dir si está configurada, si no la
-- carpeta Descargas del usuario. Devuelve nil si no se pudo resolver.
function M.resolve_dest()
  if Config.dest_dir ~= "" then return Paths.norm(Config.dest_dir) end
  local code, out = FV.run_powershell([==[
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
(New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
]==], 15000)
  if code ~= "0" or not out then return nil end
  out = out:gsub("\239\187\191", ""):gsub("[\r\n]+$", "")
  if out == "" then return nil end
  return out
end

-- Lista de problemas que impiden empaquetar (vacía si todo está en orden).
function M.preflight(dest)
  local problems = {}
  if not reaper.GetOS():find("Win") then
    problems[1] = "Solo funciona en Windows."
    return problems
  end
  if not reaper.file_exists(Config.key_file) then
    problems[#problems + 1] = "Falta el archivo de clave: " .. Config.key_file
  end
  if not reaper.file_exists(Config.winrar) then
    problems[#problems + 1] = "No se encontró WinRAR: " .. Config.winrar
  end
  if not dest then
    problems[#problems + 1] = "No se pudo resolver la carpeta de destino."
  elseif not Paths.dir_exists(dest) then
    problems[#problems + 1] = "La carpeta de destino no existe: " .. dest
  end
  return problems
end

-- Recorre las pestañas abiertas. Devuelve (items, skipped):
-- items = { proj, projfn, projdir, name, exclude_dirs, note, dirty }
-- skipped = textos con el motivo de cada pestaña omitida.
-- exclude_dirs son las carpetas que no entran al zip (nombres o rutas relativas
-- al proyecto): la de render por defecto, la de render configurada si está dentro
-- del proyecto y las de exclude_dirs de la config. note avisa cuando la carpeta
-- de render configurada no aporta ninguna exclusión.
function M.build_plan(dest)
  local items, skipped = {}, {}
  local seen_file, seen_name = {}, {}
  local i = 0
  while true do
    local proj, projfn = reaper.EnumProjects(i)
    if not proj then break end
    i = i + 1
    local label = "Pestaña " .. i
    local projdir = projfn ~= "" and Paths.project_dir(proj) or nil
    local name = projdir and projdir:match("([^/\\]+)$") or nil
    if not projdir or not name then
      skipped[#skipped + 1] = label .. ": sin guardar"
    elseif seen_file[projfn:lower()] then
      skipped[#skipped + 1] = label .. ": el mismo .rpp ya está en otra pestaña"
    elseif seen_name[name:lower()] then
      skipped[#skipped + 1] = label .. ": ya hay otro proyecto con la carpeta " .. name
    elseif dest and Paths.relative(dest, projdir) then
      skipped[#skipped + 1] = label .. ": el destino está dentro de la carpeta del proyecto"
    else
      seen_file[projfn:lower()] = true
      seen_name[name:lower()] = true
      local dirs, seen_dir = {}, {}
      local function add_dir(d)
        if d and d ~= "" and not seen_dir[d:lower()] then
          seen_dir[d:lower()] = true
          dirs[#dirs + 1] = d
        end
      end
      add_dir(FolderConfig.render_default)
      for _, d in ipairs(Config.exclude_dirs or {}) do add_dir(d) end
      local render = Paths.render_dir(proj, projdir, FolderConfig.render_default)
      local rel = Paths.relative(render, projdir)
      local note
      if rel == nil then
        note = "la carpeta de render configurada está fuera del proyecto"
      elseif rel == "" then
        note = "el render va a la carpeta del proyecto, no hay carpeta que excluir por ese camino"
      else
        add_dir(rel)
      end
      items[#items + 1] = {
        proj = proj, projfn = projfn, projdir = projdir, name = name,
        exclude_dirs = dirs, note = note, dirty = reaper.IsProjectDirty(proj) ~= 0,
      }
    end
  end
  return items, skipped
end

local EXT = "NikProjectPack"

local function psQuote(s) return "'" .. (s:gsub("'", "''")) .. "'" end

local function ps_array(list)
  local q = {}
  for _, s in ipairs(list or {}) do q[#q + 1] = psQuote(s) end
  return "@(" .. table.concat(q, ",") .. ")"
end

-- Script de PowerShell que zipea cada proyecto a un .tmp.zip, valida cantidad
-- de archivos y bytes contra el zip, y solo entonces reemplaza el zip anterior.
-- Escribe START, OK|nombre|archivos|bytes, FAIL|nombre|motivo y END en el log.
local PS_TEMPLATE = [==[
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$log = @@LOG@@
$dest = @@DEST@@
$winrar = @@WINRAR@@
$prof = @@PROFILE@@
$keyFile = @@KEYFILE@@
$excl = @@EXCL_FILES@@
$projects = @(
@@PROJECTS@@
)
function Log($s) { [System.IO.File]::AppendAllText($log, $s + "`n", $utf8) }
Log 'START'
try {
  $key = [System.IO.File]::ReadAllText($keyFile).TrimEnd("`r", "`n")
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  foreach ($p in $projects) {
    $name = $p.Name
    $dir = $p.Dir
    $zip = Join-Path $dest ($name + '.zip')
    $tmp = Join-Path $dest ($name + '.tmp.zip')
    try {
      if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
      $root = $dir.TrimEnd('\') + '\'
      $dirPats = @()
      foreach ($d in $p.Dirs) { $dirPats += [WildcardPattern]::Escape($d) }
      $expNames = New-Object 'System.Collections.Generic.List[string]'
      $expBytes = [long]0
      foreach ($f in (Get-ChildItem -LiteralPath $dir -Recurse -File -Force)) {
        $rel = $f.FullName.Substring($root.Length)
        $skip = $false
        foreach ($pat in $excl) { if ($f.Name -like $pat) { $skip = $true } }
        foreach ($pat in $dirPats) {
          if (($rel -like ($pat + '\*')) -or ($rel -like ('*\' + $pat + '\*'))) { $skip = $true }
        }
        if (-not $skip) { $expNames.Add($rel); $expBytes += $f.Length }
      }
      $cl = 'a -r -y -ibck "-cp' + $prof + '" "-p' + $key + '"'
      foreach ($pat in $excl) { $cl += ' "-x' + $pat + '"' }
      foreach ($d in $p.Dirs) { $cl += ' "-x' + $d + '" "-x*\' + $d + '" "-x' + $d + '\*" "-x*\' + $d + '\*"' }
      $cl += ' "' + $tmp + '" *'
      $proc = Start-Process -FilePath $winrar -ArgumentList $cl -WorkingDirectory $dir -WindowStyle Hidden -Wait -PassThru
      if ($proc.ExitCode -ne 0) { throw ('WinRAR terminó con código ' + $proc.ExitCode) }
      $z = [System.IO.Compression.ZipFile]::OpenRead($tmp)
      $zipNames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
      $zipCount = 0
      $zipBytes = [long]0
      try {
        foreach ($e in $z.Entries) {
          if ($e.Name -ne '') { [void]$zipNames.Add($e.FullName); $zipCount++; $zipBytes += $e.Length }
        }
      } finally { $z.Dispose() }
      if ($zipCount -ne $expNames.Count -or $zipBytes -ne $expBytes) {
        $missing = @($expNames | Where-Object { -not $zipNames.Contains($_.Replace('\', '/')) } | Select-Object -First 5)
        throw ('Validación: esperados ' + $expNames.Count + ' archivos (' + $expBytes + ' bytes), el zip trae ' + $zipCount + ' (' + $zipBytes + ' bytes). Faltan, por ejemplo: ' + ($missing -join ', '))
      }
      if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
      Move-Item -LiteralPath $tmp -Destination $zip
      Log ('OK|' + $name + '|' + $expNames.Count + '|' + $expBytes)
    } catch {
      if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
      Log ('FAIL|' + $name + '|' + ($_.Exception.Message -replace '[\r\n]+', ' '))
    }
  }
} catch {
  Log ('FAIL|*|' + ($_.Exception.Message -replace '[\r\n]+', ' '))
} finally {
  Log 'END'
}
]==]

local function build_script(items, dest, log)
  local rows = {}
  for _, it in ipairs(items) do
    rows[#rows + 1] = string.format("@{ Name = %s; Dir = %s; Dirs = %s }",
      psQuote(it.name), psQuote(it.projdir), ps_array(it.exclude_dirs))
  end
  local values = {
    LOG = psQuote(log), DEST = psQuote(dest), WINRAR = psQuote(Config.winrar),
    PROFILE = psQuote(Config.winrar_profile), KEYFILE = psQuote(Config.key_file),
    EXCL_FILES = ps_array(Config.exclude_files), PROJECTS = table.concat(rows, ",\n"),
  }
  return (PS_TEMPLATE:gsub("@@(%u[%u_]*)@@", function(k) return values[k] end))
end

local function read_file(path)
  local f = io.open(path, "rb")
  if f then
    local s = f:read("*a")
    f:close()
    return s
  end
  if not reaper.file_exists(path) then return nil end
  local code, out = FV.run_powershell(
    "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8\n[System.IO.File]::ReadAllText("
    .. psQuote(path) .. ")", 15000)
  if code ~= "0" then return nil end
  return out
end

local function parse_line(line)
  local kind, rest = line:match("^(%u+)|?(.*)$")
  if kind == "OK" then
    local name, count, bytes = rest:match("^(.-)|(%d+)|(%d+)$")
    return { kind = kind, name = name, count = tonumber(count), bytes = tonumber(bytes) }
  elseif kind == "FAIL" then
    local name, text = rest:match("^(.-)|(.*)$")
    return { kind = kind, name = name, msg = text }
  end
  return kind and { kind = kind } or nil
end

-- Texto de una línea de progreso (la que recibe on_progress).
function M.describe(e)
  if e.kind == "OK" then
    return string.format("OK: %s (%d archivos, %.1f MB)", e.name or "?", e.count or 0, (e.bytes or 0) / 1048576)
  elseif e.kind == "FAIL" then
    return string.format("FALLÓ: %s - %s", e.name or "?", e.msg or "")
  end
  return e.kind
end

-- Indica si hay un empaquetado en curso (lanzado desde esta sesión de REAPER).
function M.is_running()
  local since = tonumber(reaper.GetExtState(EXT, "running"))
  return since ~= nil and os.time() - since < Config.max_wait_s
end

-- Lanza el zipeo de items sin bloquear REAPER. on_progress(e) recibe cada línea
-- nueva del log ({ kind = START | OK | FAIL | END, ... }); on_done(resumen) se
-- llama una sola vez, con resumen = { results = { OK/FAIL }, error?, timeout? }.
-- Devuelve true, o false y el motivo si no se pudo lanzar.
function M.run_async(items, dest, on_progress, on_done)
  on_progress = on_progress or function() end
  if M.is_running() then return false, "Ya hay un empaquetado en curso." end

  local log = (os.getenv("TEMP") or reaper.GetResourcePath()) .. "\\ProjectPack_run.log"
  os.remove(log)
  local ok, err = FV.start_powershell(build_script(items, dest, log))
  if not ok then return false, err end
  reaper.SetExtState(EXT, "running", tostring(os.time()), false)

  local t0 = reaper.time_precise()
  local next_check, seen, started, finished = 0, 0, false, false
  local results = {}

  local function finish(summary)
    if finished then return end
    finished = true
    reaper.DeleteExtState(EXT, "running", false)
    summary.results = results
    on_done(summary)
  end

  -- Devuelve true mientras haya que seguir esperando.
  local function step()
    local now = reaper.time_precise()
    if now < next_check then return true end
    next_check = now + 1

    local text = read_file(log)
    if text then
      local n = 0
      for line in text:gmatch("[^\r\n]+") do
        n = n + 1
        if n > seen then
          seen = n
          local e = parse_line(line)
          if e then
            if e.kind == "START" then started = true end
            if e.kind == "OK" or e.kind == "FAIL" then results[#results + 1] = e end
            on_progress(e)
            if e.kind == "END" then
              finish({})
              return false
            end
          end
        end
      end
    end

    if not started and now - t0 > 30 then
      finish({ error = "PowerShell no respondió en 30 s." })
      return false
    end
    if now - t0 > Config.max_wait_s then
      finish({ error = "Se superó el tiempo máximo de espera; el proceso puede seguir corriendo.", timeout = true })
      return false
    end
    return true
  end

  local function loop()
    local ok2, cont = pcall(step)
    if not ok2 then
      finish({ error = tostring(cont) })
    elseif cont then
      reaper.defer(loop)
    end
  end
  reaper.defer(loop)
  return true
end

return M