-- Nik_ABPair_Exit: quita el solo de A y B y vacía CUR. No borra el par, así
-- que el próximo Nik_ABPair_Toggle retoma desde A. Sección AB_PAIR: ver el
-- encabezado de Nik_ABPair_Toggle.lua.

local SECTION = "AB_PAIR"
local proj = 0

local function find_track(guid)
  for i = 0, reaper.CountTracks(proj) - 1 do
    local tr = reaper.GetTrack(proj, i)
    if reaper.GetTrackGUID(tr) == guid then return tr end
  end
end

local _, ga = reaper.GetProjExtState(proj, SECTION, "A")
local _, gb = reaper.GetProjExtState(proj, SECTION, "B")

reaper.Undo_BeginBlock()
for _, g in ipairs({ga, gb}) do
  local tr = find_track(g)
  if tr then reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", 0) end
end
reaper.SetProjExtState(proj, SECTION, "CUR", "")
reaper.Undo_EndBlock("A/B: salir", -1)
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()