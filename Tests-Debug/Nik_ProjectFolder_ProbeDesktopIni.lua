local function out(s) reaper.ShowConsoleMsg(s .. "\n") end
local _, projfile = reaper.EnumProjects(-1, "")
local projdir = projfile:match("^(.*)[/\\]")
local media = projdir .. "\\Media"

local function has_media()
  local i = 0
  while true do
    local sub = reaper.EnumerateSubdirectories(projdir, i)
    if not sub then return false end
    if sub == "Media" then return true end
    i = i + 1
  end
end

out("--- ProbeDesktopIni ---")
out("1) Media existe al inicio: " .. tostring(has_media()))
reaper.GetProjectPath("")
out("2) tras GetProjectPath: " .. tostring(has_media()))
reaper.RecursiveCreateDirectory(media, 0)
out("3) tras RecursiveCreateDirectory: " .. tostring(has_media()))

local ini = media .. "\\desktop.ini"
local f, err = io.open(ini, "w")
out("4) io.open: " .. tostring(f ~= nil) .. " err=" .. tostring(err))
if f then
  f:write("[ViewState]\r\nMode=\r\nVid=\r\nFolderType=Documents\r\n")
  f:close()
end
out("5) file_exists tras escribir: " .. tostring(reaper.file_exists(ini)))
out("6) attrib +s: " .. tostring(reaper.ExecProcess('cmd.exe /C attrib +s "' .. media .. '" & attrib +s +h "' .. ini .. '"', 5000)))
out("7) file_exists tras attrib: " .. tostring(reaper.file_exists(ini)))
out("8) atributos: " .. tostring(reaper.ExecProcess('cmd.exe /C attrib "' .. ini .. '"', 5000)))