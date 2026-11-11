-- Nik_ProjectPack_PackTabs.lua
-- Empaqueta en un .zip con clave cada proyecto guardado de las pestañas abiertas,
-- sin la carpeta de render. Antes recolecta en Media\Samples los archivos que usan
-- los FX. Pregunta por los proyectos con cambios sin guardar y confirma antes de
-- zipear. El zipeo corre aparte: REAPER sigue usable y avisa al terminar.
-- Solo Windows.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Pack = dofile(script_dir .. "ProjectPack_common_logic.lua")
local Samples = dofile(script_dir .. "../_Shared/ProjectSamples_common_logic.lua")

local TITLE = "ProjectPack"

local function msg(s) reaper.ShowConsoleMsg(s .. "\n") end

local function name_list(items, pred)
  local out = {}
  for _, it in ipairs(items) do
    if not pred or pred(it) then out[#out + 1] = "  - " .. it.name end
  end
  return table.concat(out, "\n")
end

local function on_done(total, summary)
  local n_ok, fails = 0, {}
  for _, r in ipairs(summary.results) do
    if r.kind == "OK" then
      n_ok = n_ok + 1
    else
      fails[#fails + 1] = "  - " .. (r.name or "?") .. ": " .. (r.msg or "")
    end
  end
  local text = string.format("%d de %d proyecto(s) empaquetados.", n_ok, total)
  if summary.error then text = text .. "\n\nError: " .. summary.error end
  if #fails > 0 then text = text .. "\n\nFallaron:\n" .. table.concat(fails, "\n") end
  msg("\n" .. text)
  reaper.MB(text, TITLE, 0)
end

local function main()
  if Pack.is_running() then
    reaper.MB("Ya hay un empaquetado en curso.", TITLE, 0)
    return
  end
  reaper.ClearConsole()
  local dest = Pack.resolve_dest()
  local problems = Pack.preflight(dest)
  if #problems > 0 then
    reaper.MB(table.concat(problems, "\n"), TITLE, 0)
    return
  end

  local items, skipped = Pack.build_plan(dest)
  if #items == 0 then
    reaper.MB("No hay proyectos guardados para empaquetar.\n\n" .. table.concat(skipped, "\n"), TITLE, 0)
    return
  end

  local dirty = name_list(items, function(it) return it.dirty end)
  if dirty ~= "" then
    local r = reaper.MB("Hay proyectos con cambios sin guardar:\n\n" .. dirty
      .. "\n\n¿Guardarlos antes de empaquetar?\n"
      .. "Sí: guardar todos.\nNo: empaquetar lo que hay en disco.\nCancelar: no hacer nada.", TITLE, 3)
    if r == 2 then return end
    if r == 6 then
      for _, it in ipairs(items) do
        if it.dirty then reaper.Main_SaveProject(it.proj, false) end
      end
    end
  end

  local warnings = {}
  for _, it in ipairs(items) do
    local c = Samples.collect(it.proj, it.projfn, msg, {})
    if c.DIFF + c.ERROR + c.MISSING > 0 then
      warnings[#warnings + 1] = string.format("  - %s: %d DIFF, %d ERROR, %d inexistentes",
        it.name, c.DIFF, c.ERROR, c.MISSING)
    end
  end

  local lines = {
    "Se van a empaquetar " .. #items .. " proyecto(s) en:\n" .. dest .. "\n",
    name_list(items),
  }
  local notes = {}
  for _, it in ipairs(items) do
    if it.note then notes[#notes + 1] = "  - " .. it.name .. ": " .. it.note end
  end
  if #notes > 0 then lines[#lines + 1] = "\nNotas:\n" .. table.concat(notes, "\n") end
  if #warnings > 0 then
    lines[#lines + 1] = "\nAvisos de samples (detalle en la consola):\n" .. table.concat(warnings, "\n")
  end
  if #skipped > 0 then lines[#lines + 1] = "\nOmitidas:\n" .. table.concat(skipped, "\n") end
  lines[#lines + 1] = "\n¿Continuar?"
  if reaper.MB(table.concat(lines, "\n"), TITLE, 1) ~= 1 then return end

  msg("\nEmpaquetando " .. #items .. " proyecto(s). REAPER sigue usable; el resultado aparece acá y en un aviso al terminar.")
  local total = #items
  local ok, err = Pack.run_async(items, dest,
    function(e) msg(Pack.describe(e)) end,
    function(summary) on_done(total, summary) end)
  if not ok then reaper.MB("No se pudo lanzar el empaquetado:\n" .. tostring(err), TITLE, 0) end
end

main()