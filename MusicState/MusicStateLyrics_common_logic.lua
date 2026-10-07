local M = {}

M.TRACK_NAME_PATTERN = "lyrics"

function M.FindLyricsTrack(proj)
  proj = proj or 0
  for i = 0, reaper.CountTracks(proj) - 1 do
    local tr = reaper.GetTrack(proj, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if name:lower():find(M.TRACK_NAME_PATTERN, 1, true) then
      return tr, name
    end
  end
  return nil
end

return M