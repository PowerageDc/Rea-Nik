-- Quita el flag de time signature solo en los tempo markers
-- que caen dentro de la seleccion de tiempo actual.
-- Conserva la posicion exacta de cada marker (usa timepos absoluto, sin pasar por compas:beat).

local proj = 0
local sel_start, sel_end = reaper.GetSet_LoopTimeRange2(proj, false, false, 0, 0, false)

if sel_start == sel_end then
  reaper.ShowMessageBox("Hace una seleccion de tiempo primero.", "Info", 0)
  return
end

local count = reaper.CountTempoTimeSigMarkers(proj)
local affected = 0

for i = 0, count - 1 do
  local retval, timepos, _, _, _, timesig_num = reaper.GetTempoTimeSigMarker(proj, i)
  if retval and timepos >= sel_start and timepos < sel_end and timesig_num ~= 0 then
    affected = affected + 1
  end
end

if affected == 0 then
  reaper.ShowMessageBox("No hay markers con cambio de compas en la seleccion.", "Info", 0)
  return
end

local ok = reaper.ShowMessageBox(
  affected .. " markers en la seleccion tienen cambio de compas.\n¿Quitarlo, conservando su posicion?",
  "Confirmar", 1)

if ok == 1 then
  reaper.Undo_BeginBlock()
  for i = count - 1, 0, -1 do
    local retval, timepos, measurepos, beatpos, bpm, timesig_num, timesig_denom, lineartempo =
      reaper.GetTempoTimeSigMarker(proj, i)
    if retval and timepos >= sel_start and timepos < sel_end and timesig_num ~= 0 then
      reaper.SetTempoTimeSigMarker(proj, i, timepos, measurepos, beatpos, bpm, 0, 0, lineartempo)
    end
  end
  reaper.UpdateTimeline()
  reaper.Undo_EndBlock("Quitar time signature en seleccion", -1)
end