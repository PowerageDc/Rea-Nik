local PS = 'powershell.exe -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 6; '
  .. "Set-Content -Path (Join-Path $env:TEMP 'pp_probe_%s.txt') -Value ok\""

local variants = {
  { "A (timeout -1)", "A", function(cmd) return reaper.ExecProcess(cmd, -1) end },
  { "B (timeout -2)", "B", function(cmd) return reaper.ExecProcess(cmd, -2) end },
  { "C (cmd start /B)", "C", function(cmd)
      return reaper.ExecProcess('cmd.exe /C start "" /B ' .. cmd .. " >nul 2>&1", 20000)
    end },
}

local function msg(s) reaper.ShowConsoleMsg(s .. "\n") end

reaper.ClearConsole()
local tmp = os.getenv("TEMP") or ""
for _, v in ipairs(variants) do
  os.remove(tmp .. "\\pp_probe_" .. v[2] .. ".txt")
end

for _, v in ipairs(variants) do
  local t0 = reaper.time_precise()
  local ret = v[3](string.format(PS, v[2]))
  msg(string.format("%s: la llamada volvió en %.2f s, retorno = %s",
    v[1], reaper.time_precise() - t0, tostring(ret)))
end

local t_end = reaper.time_precise() + 10
local function check()
  if reaper.time_precise() < t_end then
    reaper.defer(check)
    return
  end
  for _, v in ipairs(variants) do
    local path = tmp .. "\\pp_probe_" .. v[2] .. ".txt"
    msg(v[1] .. ": archivo de salida " .. (reaper.file_exists(path) and "SÍ apareció" or "NO apareció"))
    os.remove(path)
  end
end
reaper.defer(check)