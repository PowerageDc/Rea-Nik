--[[
ProjectFolder_common_logic.lua
Módulo de soporte: abre la carpeta raíz, Media o Render del proyecto activo.
Uso: dofile(...).run("root" | "media" | "render")  (ver Nik_ProjectFolder_Open*.lua)

Qué hace
- Calcula la ruta a partir de la configuración del proyecto (RECORD_PATH y
  RENDER_FILE), sin consultar nada que cree carpetas.
- Si la carpeta no existe, avisa y ofrece crearla. En Windows, al abrir Media
  o Render y si falta, escribe desktop.ini (FolderType=Documents) con
  atributos de sistema, para que Windows no pase la carpeta a vista Música.
- Si RENDER_FILE está vacío (proyectos nuevos), usa render_default de
  ProjectFolder_config.lua.

Qué evitar (aprendido con sondas, ver Tests-Debug/Nik_ProjectFolder_Probe*.lua)
- os.rename / io.open para verificar existencia: fallan con tildes en rutas
  UTF-8. Usar EnumerateSubdirectories, y resetear su caché con índice -1
  antes de enumerar; si no, devuelve datos viejos tras crear o borrar.
- reaper.GetProjectPath(""): se sospecha que crea la carpeta Media como
  efecto secundario (no confirmado aislado), lo que saltea el aviso y el
  desktop.ini. Se lee RECORD_PATH con GetSetProjectInfo_String.
- Leer el render por defecto de la API o de reaper.ini: no está. reaper.ini
  solo guarda lastrenderpath, que cambia en cada render. De ahí el config.
- desktop.ini sin atributos: Windows lo ignora. Hace falta attrib +s en la
  carpeta y +s +h en el archivo.
- os.execute para abrir la carpeta: abre una ventana de cmd. Usar
  CF_ShellExecute (SWS).
- Segmentos con wildcards ($project, etc.) en RENDER_FILE: se descartan.
--]]
local M = {}

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "ProjectFolder_config.lua")
local is_win = reaper.GetOS():find("Win") ~= nil
local SEP = is_win and "\\" or "/"

local function norm(p)
  if is_win then p = p:gsub("/", "\\") else p = p:gsub("\\", "/") end
  p = p:gsub("[/\\]+$", "")
  if p:match("^%a:$") then p = p .. SEP end
  return p
end

local function is_absolute(p)
  if is_win then return p:match("^%a:[/\\]") or p:match("^[/\\][/\\]") end
  return p:sub(1, 1) == "/"
end

local function dir_exists(p)
  if p:match("^%a:[/\\]$") then return true end
  local parent, name = p:match("^(.*)[/\\]([^/\\]+)$")
  if not parent then return false end
  if parent:match("^%a:$") then parent = parent .. SEP end
  reaper.EnumerateSubdirectories(parent, -1)
  local i = 0
  while true do
    local sub = reaper.EnumerateSubdirectories(parent, i)
    if not sub then return false end
    if sub:lower() == name:lower() then return true end
    i = i + 1
  end
end

local function open_folder(p)
  if reaper.CF_ShellExecute then
    reaper.CF_ShellExecute(p)
  elseif is_win then
    os.execute('start "" explorer "' .. p .. '"')
  else
    os.execute('open "' .. p .. '"')
  end
end

local function resolve_setting(raw, projdir, default)
  local clean = {}
  for seg in raw:gmatch("[^/\\]+") do
    if seg:find("%$") then break end
    clean[#clean + 1] = seg
  end
  local rel = table.concat(clean, SEP)
  if rel == "" then
    if default == "" then return projdir end
    return projdir .. SEP .. default
  end
  if is_absolute(raw) then return (raw:match("^([/\\]*)") or "") .. rel end
  return projdir .. SEP .. rel
end

local function apply_documents_view(p)
  if not is_win then return true end
  local ini = p .. "\\desktop.ini"
  local f = io.open(ini, "w")
  if not f then return false end
  f:write("[ViewState]\r\nMode=\r\nVid=\r\nFolderType=Documents\r\n")
  f:close()
  reaper.ExecProcess('cmd.exe /C attrib +s "' .. p .. '" & attrib +s +h "' .. ini .. '"', 5000)
  return reaper.file_exists(ini)
end

function M.run(mode)
  local labels = { root = "Proyecto", media = "Media", render = "Render" }
  local label = labels[mode]
  if not label then
    reaper.MB("Modo desconocido: " .. tostring(mode), "Carpeta del proyecto", 0)
    return
  end

  local _, projfile = reaper.EnumProjects(-1, "")
  local projdir = projfile ~= "" and projfile:match("^(.*)[/\\]") or nil

  local path
  if not projdir then
    reaper.MB("El proyecto no está guardado, no se puede resolver la carpeta de " .. label .. ".",
      "Carpeta de " .. label, 0)
    return
  elseif mode == "root" then
    path = projdir
  elseif mode == "media" then
    local _, rp = reaper.GetSetProjectInfo_String(0, "RECORD_PATH", "", false)
    path = resolve_setting(rp, projdir, "")
  else
    local _, rf = reaper.GetSetProjectInfo_String(0, "RENDER_FILE", "", false)
    path = resolve_setting(rf, projdir, Config.render_default)
  end

  if not path or path == "" then
    reaper.MB("No se pudo determinar la ruta.", "Carpeta de " .. label, 0)
    return
  end
  path = norm(path)

  if not dir_exists(path) then
    local r = reaper.MB(
      "La carpeta " .. label .. " todavía no existe:\n\n" .. path .. "\n\n¿Querés crearla y abrirla?",
      "Carpeta de " .. label, 4)
    if r ~= 6 then return end
    reaper.RecursiveCreateDirectory(path, 0)
    if not dir_exists(path) then
      reaper.MB("No se pudo crear la carpeta.", "Carpeta de " .. label, 0)
      return
    end
    if not apply_documents_view(path) then
      reaper.MB("La carpeta se creó, pero no se pudo configurar la vista Documentos (desktop.ini).", "Carpeta de " .. label, 0)
    end
  end

  if mode ~= "root" and not reaper.file_exists(path .. "\\desktop.ini") then
    apply_documents_view(path)
  end
  open_folder(path)
end

return M