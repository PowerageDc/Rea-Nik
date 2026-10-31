-- Medición, aplicación y verificación de la posición/tamaño del área cliente
-- de ventanas flotantes de FX. Requiere JS_ReaScriptAPI.
-- Las coordenadas son de pantalla; el área cliente es la que ve una captura
-- de pantalla (sin bordes ni barra de título).

local M = {}

function M.has_js_api()
  return reaper.JS_Window_GetRect ~= nil
    and reaper.JS_Window_GetClientRect ~= nil
    and reaper.JS_Window_SetPosition ~= nil
    and reaper.JS_Window_ListAllChild ~= nil
    and reaper.JS_Window_HandleFromAddress ~= nil
end

function M.load_config(script_dir)
  return dofile(script_dir .. "FxWindow_config.lua")
end

-- Primera entrada del config cuyo `match` es subcadena del nombre del FX.
function M.find_entry(config, fx_name)
  local upper = fx_name:upper()
  for _, entry in ipairs(config) do
    if upper:find(entry.match:upper(), 1, true) then
      return entry
    end
  end
  return nil
end

function M.list_fx(track)
  local list = {}
  for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
    local _, name = reaper.TrackFX_GetFXName(track, fx, "")
    list[#list + 1] = { index = fx, name = name }
  end
  return list
end

local function text_of(fn, hwnd)
  local ok, a, b = pcall(fn, hwnd, "")
  if not ok then ok, a, b = pcall(fn, hwnd) end
  if not ok then return "" end
  if type(b) == "string" then return b end
  return type(a) == "string" and a or ""
end

local VIEW_CLASS = "reaperPluginHostWrapProc"

-- Rect en pantalla de la vista del plugin dentro de la ventana flotante, o nil.
-- Se busca por clase: el nombre de la hija JUCE cambia en cada ejecución.
function M.measure_view(hwnd)
  local _, list = reaper.JS_Window_ListAllChild(hwnd)
  for addr in (list or ""):gmatch("[^,]+") do
    local child = reaper.JS_Window_HandleFromAddress(tonumber(addr))
    if child and text_of(reaper.JS_Window_GetClassName, child) == VIEW_CLASS then
      local _, l, t, r, b = reaper.JS_Window_GetRect(child)
      return { x = l, y = t, w = r - l, h = b - t }
    end
  end
  return nil
end

-- Rect de ventana, rect cliente, vista del plugin y grosor de cada borde (en px de pantalla).
function M.measure(hwnd)
  local _, wl, wt, wr, wb = reaper.JS_Window_GetRect(hwnd)
  local _, cl, ct, cr, cb = reaper.JS_Window_GetClientRect(hwnd)
  return {
    win = { x = wl, y = wt, w = wr - wl, h = wb - wt },
    cli = { x = cl, y = ct, w = cr - cl, h = cb - ct },
    frame = { left = cl - wl, top = ct - wt, right = wr - cr, bottom = wb - cb },
    view = M.measure_view(hwnd),
  }
end

-- Mueve y redimensiona la ventana para que su área cliente caiga en el rect
-- de `entry`. `shrink` (opcional) resta esos px al ancho y al alto: un cambio de
-- tamaño grande hace que el plugin reajuste su UI al volver al tamaño exacto.
-- Devuelve la medición resultante.
function M.apply(hwnd, entry, shrink)
  local f = M.measure(hwnd).frame
  local s = shrink or 0
  reaper.JS_Window_SetPosition(
    hwnd,
    entry.x - f.left,
    entry.y - f.top,
    entry.w + f.left + f.right - s,
    entry.h + f.top + f.bottom - s
  )
  return M.measure(hwnd)
end

-- nil si el área cliente coincide con `entry`; si no, texto con las diferencias.
function M.differences(measured, entry)
  local parts = {}
  for _, k in ipairs({ "x", "y", "w", "h" }) do
    if measured.cli[k] ~= entry[k] then
      parts[#parts + 1] = string.format("%s esperado %d, real %d", k, entry[k], measured.cli[k])
    end
  end
  if entry.view_w and entry.view_h then
    local v = measured.view
    if not v then
      parts[#parts + 1] = "vista del plugin no encontrada"
    elseif v.w ~= entry.view_w or v.h ~= entry.view_h then
      parts[#parts + 1] = string.format(
        "vista esperada %dx%d, real %dx%d", entry.view_w, entry.view_h, v.w, v.h)
    end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, "; ")
end

-- Línea lista para pegar en FxWindow_config.lua.
function M.format_entry(match, cli, view)
  if view then
    return string.format(
      '  { match = "%s", x = %d, y = %d, w = %d, h = %d, view_w = %d, view_h = %d },',
      match, cli.x, cli.y, cli.w, cli.h, view.w, view.h
    )
  end
  return string.format(
    '  { match = "%s", x = %d, y = %d, w = %d, h = %d },',
    match, cli.x, cli.y, cli.w, cli.h
  )
end

return M