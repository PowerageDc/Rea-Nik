local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local MM = dofile(script_dir .. "../MonitorMix/MonitorMix_common_logic.lua")

local function msg(s) reaper.ShowConsoleMsg(s .. "\n") end

reaper.ClearConsole()
local results, cfg, pname = MM.evaluate(MM.load_config())

msg("Proyecto: " .. pname)
msg("Overrides activos: " .. (#cfg.active > 0 and table.concat(cfg.active, ", ") or "(ninguno)"))
msg("Alias del Stem Bus: " .. table.concat(MM.stem_aliases(), ", "))
msg("")

local n_in = 0
for _, r in ipairs(results) do
  if r.admitted then n_in = n_in + 1 end
  msg(string.format("  [%2d] %-30s %s  %-6s %s",
    r.idx + 1, r.name, r.admitted and "IN " or "out", r.role or "-", r.reason))
end
msg(string.format("\n%d de %d tracks admitidos", n_in, #results))