-- Nik_ABPair_Toggle: alterna por solo entre dos tracks (A = el de arriba).
-- Pensado para comparar un track MIDI corregido contra el WAV original.
--
-- Uso:
--   * Con 2 tracks seleccionados distintos del par guardado (o en otro orden):
--     define el par, quita el solo del par anterior y deja A en solo.
--   * En cualquier otro caso (otra selección, o ninguna, p. ej. desde el
--     Piano Roll): alterna entre A y B según el turno guardado.
--
-- Estado en el proyecto (ProjExtState, sección AB_PAIR; viaja con el .rpp):
--   A, B = GUIDs del par. CUR = quién suena ("A", "B" o vacío).
--   Nik_ABPair_Exit.lua usa la misma sección.
-- Solo toca el I_SOLO de A y B: no modifica mute ni solo de otros tracks.

local SECTION = "AB_PAIR"
local proj = 0

local function find_track(guid)
  for i = 0, reaper.CountTracks(proj) - 1 do
    local tr = reaper.GetTrack(proj, i)
    if reaper.GetTrackGUID(tr) == guid then return tr end
  end
end

-- a suena en solo, b se des-solea (no se toca el mute de nadie)
local function make_audible(a, b)
  reaper.SetMediaTrackInfo_Value(b, "I_SOLO", 0)
  reaper.SetMediaTrackInfo_Value(a, "I_SOLO", 1)
end

reaper.Undo_BeginBlock()

local _, stored_a = reaper.GetProjExtState(proj, SECTION, "A")
local _, stored_b = reaper.GetProjExtState(proj, SECTION, "B")

if reaper.CountSelectedTracks(proj) == 2 then
  local t1 = reaper.GetSelectedTrack(proj, 0)
  local t2 = reaper.GetSelectedTrack(proj, 1)
  local g1, g2 = reaper.GetTrackGUID(t1), reaper.GetTrackGUID(t2)

  if g1 ~= stored_a or g2 ~= stored_b then
    -- par nuevo: limpiar el solo del par anterior, guardar y arrancar escuchando A
    for _, g in ipairs({stored_a, stored_b}) do
      local old = find_track(g)
      if old then reaper.SetMediaTrackInfo_Value(old, "I_SOLO", 0) end
    end
    reaper.SetProjExtState(proj, SECTION, "A", g1)
    reaper.SetProjExtState(proj, SECTION, "B", g2)
    make_audible(t1, t2)
    reaper.SetProjExtState(proj, SECTION, "CUR", "A")
    reaper.Undo_EndBlock("A/B: definir par", -1)
    reaper.TrackList_AdjustWindows(false)
    return
  end
end

local a = find_track(stored_a)
local b = find_track(stored_b)

if a and b then
  local _, cur = reaper.GetProjExtState(proj, SECTION, "CUR")
  if cur == "A" then
    make_audible(b, a)  -- sonaba A: pasar a B
    reaper.SetProjExtState(proj, SECTION, "CUR", "B")
  else
    make_audible(a, b)  -- sonaba B (o sin dato): volver a A
    reaper.SetProjExtState(proj, SECTION, "CUR", "A")
  end
else
  reaper.ShowMessageBox("No hay un par A/B definido.\nSeleccione 2 pistas y ejecute el script.", "A/B toggle", 0)
end

reaper.Undo_EndBlock("A/B: alternar", -1)
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
