local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Pack = dofile(script_dir .. "../ProjectPack/ProjectPack_common_logic.lua")

local function msg(s) reaper.ShowConsoleMsg(s .. "\n") end

reaper.ClearConsole()
local dest = Pack.resolve_dest()
msg("Destino: " .. tostring(dest))
for _, p in ipairs(Pack.preflight(dest)) do msg("PROBLEMA: " .. p) end

local items, skipped = Pack.build_plan(dest)
for _, it in ipairs(items) do
  msg(string.format("%s.zip  (cambios sin guardar: %s)", it.name, tostring(it.dirty)))
  msg("  carpeta: " .. it.projdir)
  msg("  excluye carpetas: " .. table.concat(it.exclude_dirs, " | "))
  if it.note then msg("  nota: " .. it.note) end
end
for _, s in ipairs(skipped) do msg("Omitida - " .. s) end