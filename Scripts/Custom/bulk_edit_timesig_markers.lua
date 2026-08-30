-- Editor generalizado de compas para tempo markers.
-- Lista los markers con time signature en la seleccion de tiempo (o todo el proyecto),
-- permite editar todos de una vez via un solo dialogo, y aplica por API
-- (timepos fijo, sin pasar por el dialogo nativo que come markers).

local proj = 0
local sel_start, sel_end = reaper.GetSet_LoopTimeRange2(proj, false, false, 0, 0, false)

if sel_start == sel_end then
  sel_start = 0
  sel_end = reaper.GetProjectLength(proj)
end

local count = reaper.CountTempoTimeSigMarkers(proj)
local markers = {}

for i = 0, count - 1 do
  local retval, timepos, measurepos, beatpos, bpm, timesig_num, timesig_denom, lineartempo =
    reaper.GetTempoTimeSigMarker(proj, i)
  if retval and timepos >= sel_start and timepos < sel_end and timesig_num ~= 0 then
    table.insert(markers, {
      idx = i, timepos = timepos, measurepos = measurepos, beatpos = beatpos,
      bpm = bpm, num = timesig_num, denom = timesig_denom, lineartempo = lineartempo
    })
  end
end

if #markers == 0 then
  reaper.ShowMessageBox("No hay markers con cambio de compas en el rango.", "Info", 0)
  return
end

-- Referencia en consola
reaper.ClearConsole()
reaper.ShowConsoleMsg("Markers con compas en el rango:\n")
local default_vals = {}
for i, m in ipairs(markers) do
  local minutes = math.floor(m.timepos / 60)
  local seconds = m.timepos - minutes * 60
  reaper.ShowConsoleMsg(string.format("%d) %d:%05.2f -> %d/%d\n", i, minutes, seconds, m.num, m.denom))
  table.insert(default_vals, m.num .. "/" .. m.denom)
end

local default_csv = table.concat(default_vals, ",")
local ok, result = reaper.GetUserInputs(
  "Editar compases (N/D, o 0 para quitar el flag)", 1,
  "Compases separados por coma:", default_csv)

if not ok then return end

local new_vals = {}
for val in (result .. ","):gmatch("([^,]*),") do
  table.insert(new_vals, val:match("^%s*(.-)%s*$"))
end

if #new_vals ~= #markers then
  reaper.ShowMessageBox("La cantidad de valores no coincide con la cantidad de markers.", "Error", 0)
  return
end

local changes = 0
for i, m in ipairs(markers) do
  local v = new_vals[i]
  if v == "0" or v == "" then
    if m.num ~= 0 then changes = changes + 1 end
  else
    local n, d = v:match("^(%d+)%s*/%s*(%d+)$")
    if n and (tonumber(n) ~= m.num or tonumber(d) ~= m.denom) then
      changes = changes + 1
    end
  end
end

if changes == 0 then
  reaper.ShowMessageBox("No hay cambios para aplicar.", "Info", 0)
  return
end

local confirm = reaper.ShowMessageBox(changes .. " markers van a cambiar.\n¿Aplicar?", "Confirmar", 1)
if confirm ~= 1 then return end

reaper.Undo_BeginBlock()

-- Pasada 1: aplicar los compases nuevos
for i = 1, #markers do
  local v = new_vals[i]
  local new_num, new_denom
  if v == "0" or v == "" then
    new_num, new_denom = 0, 0
  else
    local n, d = v:match("^(%d+)%s*/%s*(%d+)$")
    if n then new_num, new_denom = tonumber(n), tonumber(d)
    else new_num, new_denom = markers[i].num, markers[i].denom end
  end
  markers[i].new_num, markers[i].new_denom = new_num, new_denom
  reaper.SetTempoTimeSigMarker(proj, markers[i].idx, markers[i].timepos, -1, -1, markers[i].bpm, new_num, new_denom, markers[i].lineartempo)
end

-- Pasada 2: re-forzar timepos original para corregir cualquier corrimiento en cascada
for i = 1, #markers do
  reaper.SetTempoTimeSigMarker(proj, markers[i].idx, markers[i].timepos, -1, -1, markers[i].bpm, markers[i].new_num, markers[i].new_denom, markers[i].lineartempo)
end

reaper.UpdateTimeline()
reaper.Undo_EndBlock("Editar compases de tempo markers en bloque", -1)