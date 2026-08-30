-- Quita el flag de cambio de compas de los tempo markers,
-- dejandolos como markers de tempo puro (sin linea de compas forzada)
-- Se salta el marker 1 (1.1.00) por seguridad

local proj = 0
local count = reaper.CountTempoTimeSigMarkers(proj)
local affected = 0

for i = 0, count - 1 do
  local retval, _, _, _, _, timesig_num = reaper.GetTempoTimeSigMarker(proj, i)
  if retval and timesig_num ~= 0 then
    affected = affected + 1
  end
end

if affected == 0 then
  reaper.ShowMessageBox("No hay markers con cambio de compas explicito (fuera del marker 1).", "Info", 0)
  return
end

local ok = reaper.ShowMessageBox(
  affected .. " markers tienen cambio de compas explicito.\n¿Quitarlo y dejarlos como tempo puro?",
  "Confirmar", 1)

if ok == 1 then
  reaper.Undo_BeginBlock()
  for i = count - 1, 0, -1 do
    local retval, timepos, measurepos, beatpos, bpm, timesig_num, timesig_denom, lineartempo =
      reaper.GetTempoTimeSigMarker(proj, i)
    if retval and timesig_num ~= 0 then
      reaper.SetTempoTimeSigMarker(proj, i, timepos, measurepos, beatpos, bpm, 0, 0, lineartempo)
    end
  end
  reaper.UpdateTimeline()
  reaper.Undo_EndBlock("Quitar cambios de compas explicitos en tempo markers", -1)
end