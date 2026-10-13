local function out(s) reaper.ShowConsoleMsg(s .. "\n") end
local function q(s) return string.format("%q", tostring(s)) end

local _, projfile = reaper.EnumProjects(-1, "")
local projdir = projfile ~= "" and projfile:match("^(.*)[/\\]") or nil

out("--- ProjectFolder probe ---")
out("projfile: " .. q(projfile))
out("projdir: " .. q(projdir))
out("GetProjectPath: " .. q(reaper.GetProjectPath("")))

local _, rf = reaper.GetSetProjectInfo_String(0, "RENDER_FILE", "", false)
local _, rp = reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "", false)
out("RENDER_FILE: " .. q(rf))
out("RENDER_PATTERN: " .. q(rp))

local ok, r, v = pcall(reaper.get_config_var_string, "defrenderpath")
out("config defrenderpath: ok=" .. tostring(ok) .. " ret=" .. tostring(r) .. " val=" .. q(v))

if reaper.BR_Win32_GetPrivateProfileString then
  local _, val = reaper.BR_Win32_GetPrivateProfileString("REAPER", "defrenderpath", "<vacio>", reaper.get_ini_file())
  out("ini defrenderpath: " .. q(val))
end

if projdir then
  local i = 0
  while true do
    local sub = reaper.EnumerateSubdirectories(projdir, i)
    if not sub then break end
    out("subdir: " .. q(sub))
    i = i + 1
  end
  out("Media\\desktop.ini existe: " .. tostring(reaper.file_exists(projdir .. "\\Media\\desktop.ini")))
end