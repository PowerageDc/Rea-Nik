local proj = 0
local _, projfile = reaper.EnumProjects(-1)
reaper.ClearConsole()
reaper.ShowConsoleMsg("Proyecto: " .. tostring(projfile) .. "\n\n")

for t = 0, reaper.CountTracks(proj) - 1 do
  local tr = reaper.GetTrack(proj, t)
  local _, tname = reaper.GetTrackName(tr)
  for fx = 0, reaper.TrackFX_GetCount(tr) - 1 do
    local _, fxname = reaper.TrackFX_GetFXName(tr, fx)
    reaper.ShowConsoleMsg(string.format("[%s] FX %d = %s\n", tname, fx, fxname))
    if true then
      local i = 0
      while true do
        local ok, path = reaper.TrackFX_GetNamedConfigParm(tr, fx, "FILE" .. i)
        if i == 0 then
          reaper.ShowConsoleMsg(string.format("   FILE0 ok=%s path=%q\n", tostring(ok), tostring(path)))
        end
        if not ok or path == "" then break end
        local f = io.open(path, "rb")
        local existe = f ~= nil
        if f then f:close() end
        reaper.ShowConsoleMsg(string.format("[%s] FX %d FILE%d: %s  (existe: %s)\n",
          tname, fx, i, path, tostring(existe)))
        i = i + 1
      end
    end
  end
end