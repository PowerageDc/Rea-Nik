-- ProjectPaths_common_logic.lua
-- Rutas de un proyecto de REAPER (carpeta del .rpp, Media y Render) a partir de
-- su configuración, sin consultar nada que cree carpetas. Sirve para cualquier
-- pestaña abierta, no solo la activa.

local M = {}

local is_win = reaper.GetOS():find("Win") ~= nil
local SEP = is_win and "\\" or "/"

function M.norm(p)
  if is_win then p = p:gsub("/", "\\") else p = p:gsub("\\", "/") end
  p = p:gsub("[/\\]+$", "")
  if p:match("^%a:$") then p = p .. SEP end
  return p
end

local function is_absolute(p)
  if is_win then return p:match("^%a:[/\\]") or p:match("^[/\\][/\\]") end
  return p:sub(1, 1) == "/"
end

-- Resuelve los segmentos "." y ".." de una ruta ya normalizada.
local function collapse(p)
  if not p:find("[/\\]%.%.?[/\\]") and not p:find("[/\\]%.%.?$") then return p end
  local prefix, rest = p:match("^(%a:[/\\]?)(.*)$")
  if not prefix then prefix, rest = p:match("^([/\\]*)(.*)$") end
  local out = {}
  for seg in rest:gmatch("[^/\\]+") do
    if seg == ".." then
      if #out > 0 then out[#out] = nil end
    elseif seg ~= "." then
      out[#out + 1] = seg
    end
  end
  return prefix .. table.concat(out, SEP)
end

function M.dir_exists(p)
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

-- Carpeta del .rpp de la pestaña. proj nil o 0 = proyecto activo.
-- Devuelve nil si la pestaña no está guardada.
function M.project_dir(proj)
  local file
  if proj == nil or proj == 0 then
    local _, f = reaper.EnumProjects(-1, "")
    file = f
  else
    local i = 0
    while true do
      local p, f = reaper.EnumProjects(i, "")
      if not p then return nil end
      if p == proj then file = f break end
      i = i + 1
    end
  end
  if not file or file == "" then return nil end
  return file:match("^(.*)[/\\]")
end

function M.media_dir(proj, projdir)
  local _, rp = reaper.GetSetProjectInfo_String(proj or 0, "RECORD_PATH", "", false)
  return collapse(M.norm(resolve_setting(rp, projdir, "")))
end

-- default: carpeta de render que se usa cuando el proyecto no tiene una configurada.
function M.render_dir(proj, projdir, default)
  local _, rf = reaper.GetSetProjectInfo_String(proj or 0, "RENDER_FILE", "", false)
  return collapse(M.norm(resolve_setting(rf, projdir, default or "")))
end

-- Ruta de path relativa a dir: "" si son la misma, nil si path no está dentro de dir.
function M.relative(path, dir)
  local a, b = M.norm(path), M.norm(dir)
  if is_win then a, b = a:lower(), b:lower() end
  if a == b then return "" end
  if a:sub(1, #b + 1) ~= b .. SEP then return nil end
  return M.norm(path):sub(#b + 2)
end

return M