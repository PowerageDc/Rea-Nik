local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local cfg = dofile(script_dir .. "TempoTools_config.lua")
local Base = dofile(script_dir .. "TempoTools_common_logic.lua")
local Read = dofile(script_dir .. "TempoTapRead_common_logic.lua")
local Plan = dofile(script_dir .. "TempoTapPlan_common_logic.lua")
local Items = dofile(script_dir .. "TempoTapItems_common_logic.lua")
local Map = dofile(script_dir .. "TempoTapMap_common_logic.lua")
local Preview = dofile(script_dir .. "TempoTapPreview_common_logic.lua")
local PreviewUi = dofile(script_dir .. "TempoTapPreviewUi_common_logic.lua")

local TITLE = "Tempo taps"

local function show(text, kind)
  return reaper.ShowMessageBox(text, TITLE, kind or 0)
end

local function warnings_text(list)
  local lines = {}
  for _, w in ipairs(list) do
    lines[#lines + 1] = "- " .. (type(w) == "table" and w.text or w)
  end
  return table.concat(lines, "\n")
end

local coll = Items.collect(cfg)
local tapped, group_warnings = Read.group(Read.read_taps())
if #tapped == 0 then
  show("No hay compases para mapear:\n" .. warnings_text(group_warnings))
  return
end
local proj_num, proj_den, proj_bpm = reaper.TimeMap_GetTimeSigAtTime(0, 0)

local function build(measures, preroll_bars)
  return Plan.build(measures, {
    proj_num = proj_num,
    proj_den = proj_den,
    proj_bpm = proj_bpm,
    preroll_bars = preroll_bars,
  })
end

-- measures: compases ya ajustados por el snap. snap: resumen de la vista previa.
local function finish(measures, snap)
  local suggested = cfg.preroll_bars_default
  if not coll.fresh then
    local detected = build(measures, nil)
    if detected then suggested = detected.preroll_bars end
  end

  local ok, input = reaper.GetUserInputs(TITLE, 1, "Compases de pre-roll:", tostring(suggested))
  if not ok then return end
  local n_bars = math.floor(tonumber(input) or 0)
  if n_bars < 1 or n_bars > 8 then
    show("Cantidad de compases no válida: " .. input)
    return
  end

  local plan, plan_warnings = build(measures, n_bars)
  if not plan then
    show("No se pudo calcular el plan:\n" .. warnings_text(plan_warnings))
    return
  end

  local ev = Items.evaluate(coll, plan)
  if ev.blocking then
    show("No se aplica nada:\n" .. warnings_text(ev.warnings))
    return
  end

  local function count(k) return snap.down[k] + snap.beat[k] end
  local lines = {
    string.format("Snap: %d ajustados, %d interpolados, %d sin cambio (%d bloqueados, %d rechazados)",
      count("snapped"), count("interpolated"), count("kept"), snap.locked, snap.rejected),
    string.format("Pre-roll: %d compases de %d/%d a %.2f bpm",
      plan.preroll_bars, plan.init.num, plan.init.den, plan.init.bpm),
    string.format("Desplazamiento: %+.3f s", plan.delta),
    string.format("Items de stems a mover: %d", #ev.stems),
    string.format("Items del count-in a pasar a beats: %d", ev.to_convert or 0),
    string.format("Tempo markers a insertar: %d (se reemplazan los existentes hasta el último downbeat)", #plan.markers),
  }
  if ev.click then
    lines[#lines + 1] = string.format("Click: largo %.3f -> %.3f s", ev.click.len, ev.click.new_len)
  end

  local all = {}
  for _, w in ipairs(plan_warnings) do all[#all + 1] = w end
  for _, w in ipairs(ev.warnings) do all[#all + 1] = w end
  local text = table.concat(lines, "\n")
  if #all > 0 then
    text = text .. "\n\nAvisos:\n" .. warnings_text(all)
  end

  if show(text .. "\n\n¿Aplicar?", 1) ~= 1 then return end

  reaper.Undo_BeginBlock2(0)
  reaper.PreventUIRefresh(1)
  local converted = Items.apply(coll, plan)
  local moved_taps = Base.shift_taps(plan.delta)
  local tail = Map.apply(plan)
  Items.fit_click(coll, plan)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateTimeline()
  reaper.UpdateArrange()
  reaper.Undo_EndBlock2(0, "Tempo taps: alinear contenido y mapear tempo", -1)

  local v = Map.verify(plan, tail)
  reaper.ShowConsoleMsg(string.format(
    "stems movidos: %d | taps movidos: %d | count-in convertidos: %d | delta %+.3f s\n",
    #ev.stems, moved_taps, converted, plan.delta))
  reaper.ShowConsoleMsg(string.format(
    "tempo markers: %d insertados (esperados %d) | desvío máximo de posición: %.4f s\n",
    v.inserted, v.expected, v.max_dev))
  reaper.ShowConsoleMsg(string.format(
    "downbeats fuera de inicio de compás: %d | saltos de compás irregulares: %d | desvío de markers posteriores: %.4f s\n",
    v.off_grid, v.bad_seq, v.tail_dev))
end

local S = Preview.new(tapped, coll, cfg)
PreviewUi.run(S, {
  on_apply = function(measures) finish(measures, S.summary) end,
  on_cancel = function() end,
})