local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "MidiEdit_config.lua")
local CcCurve = dofile(script_dir .. "MidiEditCcCurve_common_logic.lua")
local ButtonStyle = dofile(script_dir .. "../_Shared/ImGuiButtonStyle_common_logic.lua")
local EditorFocus = dofile(script_dir .. "../_Shared/ImGuiEditorFocus_common_logic.lua")

local TITLE = "MidiEdit Curva CC"
local RETURN_FOCUS_TO_EDITOR = true
local PREVIEW_MS = 2000
local PREVIEW_H = 110
local PREVIEW_STEPS = 200
local cfg = Config.cc_curve

local P, err = CcCurve.load(Config)
if not P then
  reaper.ShowConsoleMsg("[MidiEdit CcCurve] " .. err .. "\n")
  return
end
P.bend_range_st = P.bend_range_st or 2

local preset_opts = {}
for name in pairs(cfg.presets) do preset_opts[#preset_opts + 1] = { name, name } end
table.sort(preset_opts, function(a, b) return a[1] < b[1] end)

local LANE_OPTS = { { "active", "Activa" }, { "pitchbend", "Pitch bend" }, { "cc", "CC" } }
local CHAN_OPTS = { { "active", "Activo" }, { "fixed", "Fijo" } }
local MODE_OPTS = { { "replace", "Reemplazar" }, { "merge", "Mezclar" } }
local RES_OPTS = { { "native", "Nativa" }, { "dense", "Densa" } }
local RATE_OPTS = { { "hz", "Hz" }, { "cycles", "Ciclos" } }
local POINT_OPTS = { { "base", "Base" }, { "previous", "Anterior" }, { "value", "Valor" } }
local WAVE_OPTS = {
  { "sine", "Seno" }, { "triangle", "Triangulo" }, { "square", "Cuadrada" },
  { "saw_up", "Sierra +" }, { "saw_down", "Sierra -" },
}
local SHAPE_OPTS = {
  { 0, "Cuadrada" }, { 1, "Lineal" }, { 2, "Suave" }, { 3, "Inicio rapido" }, { 4, "Final rapido" },
}
-- Campos de valores por motor: clave, etiqueta y si es una amplitud (sin signo).
local VALUE_FIELDS = {
  swell = { { "lo", "Minimo" }, { "hi", "Maximo" }, { "base", "Base" } },
  ramp = { { "from", "Desde" }, { "to", "Hasta" }, { "base", "Base" } },
  osc = { { "center", "Centro" }, { "depth", "Profundidad", true }, { "base", "Base" } },
}
local SCALAR_KEYS = { "peak", "shape", "tension", "phase", "fade_in", "hz", "cycles" }

local function modified()
  local base = cfg.presets[P.name]
  if not base then return true end
  for _, k in ipairs(SCALAR_KEYS) do
    local a, b = P[k], base[k]
    if (a == nil) ~= (b == nil) then return true end
    if a and math.abs(a - b) > 1e-6 then return true end
  end
  if P.wave ~= base.wave or (P.close == true) ~= (base.close == true) then return true end
  for _, kind in ipairs({ "cc", "pitchbend" }) do
    for k, v in pairs(P[kind] or {}) do
      local b = base[kind] and base[kind][k]
      if b == nil or math.abs(v - b) > 1e-6 then return true end
    end
  end
  return false
end

local ctx = reaper.ImGui_CreateContext(TITLE)
local last_editor
local status = ""
local need_save = false
local need_live = false
local live = false
local point = { mode = "base", value = 0 }
local focus_tick = EditorFocus.new(ctx, function() return last_editor end)

-- Take del ultimo MIDI Editor visto (el activo puede ser nil con el foco
-- en este panel).
local function target_take()
  local ed = reaper.MIDIEditor_GetActive()
  if ed then last_editor = ed end
  if not last_editor then return nil end
  local take = reaper.MIDIEditor_GetTake(last_editor)
  if take and reaper.ValidatePtr(take, "MediaItem_Take*") then return take end
  last_editor = nil
  return nil
end

local function changed_live()
  need_save = true
  need_live = true
end

-- Cambia de preset conservando lane, canal, modo, resolucion y bend range.
local function select_preset(name)
  local np = CcCurve.resolve(Config, name)
  if not np then return end
  for _, k in ipairs({ "lane", "channel", "mode", "bend_range_st" }) do np[k] = P[k] end
  np.resolution = cfg.presets[name].resolution or P.resolution
  P = np
  changed_live()
end

local function set_rate_unit(unit, dur_ms)
  if unit == "hz" and not P.hz then
    P.hz, P.cycles = (P.cycles or 1) * 1000 / dur_ms, nil
  elseif unit == "cycles" and not P.cycles then
    P.cycles, P.hz = (P.hz or 1) * dur_ms / 1000, nil
  end
end

local function choice_row(id, options, current, on_pick, quiet)
  reaper.ImGui_PushID(ctx, id)
  for i, o in ipairs(options) do
    if i > 1 then reaper.ImGui_SameLine(ctx) end
    local kind = (o[1] == current) and "primary" or "neutral"
    if ButtonStyle.button(ctx, o[2], kind, { pad = 8 }) then
      on_pick(o[1])
      need_save = true
      if not quiet then need_live = true end
    end
  end
  reaper.ImGui_PopID(ctx)
end

local function combo(id, label, options, current, on_pick, suffix)
  local shown = ""
  for _, o in ipairs(options) do
    if o[1] == current then shown = o[2] end
  end
  reaper.ImGui_SetNextItemWidth(ctx, 200)
  if reaper.ImGui_BeginCombo(ctx, label .. "###" .. id, shown .. (suffix or "")) then
    for _, o in ipairs(options) do
      if reaper.ImGui_Selectable(ctx, o[2] .. "###" .. id .. "_" .. tostring(o[1]), o[1] == current) then
        on_pick(o[1])
      end
    end
    reaper.ImGui_EndCombo(ctx)
  end
end

-- quiet: el cambio se guarda pero no re-aplica en vivo.
local function edited(quiet)
  if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
    need_save = true
    if not quiet then need_live = true end
  end
end

-- Sliders a todo el ancho disponible menos el espacio de la etiqueta: el
-- recorrido completo del rango cabe en el ancho del control. Ctrl+clic
-- escribe un valor exacto.
local LABEL_W = 130

local function slider_int(label, tbl, key, min, max, fmt, quiet)
  reaper.ImGui_SetNextItemWidth(ctx, -LABEL_W)
  local changed, v = reaper.ImGui_SliderInt(ctx, label, tbl[key], min, max, fmt,
    reaper.ImGui_SliderFlags_AlwaysClamp())
  if changed then tbl[key] = v end
  edited(quiet)
end

local function slider_dbl(label, tbl, key, min, max, fmt, quiet)
  reaper.ImGui_SetNextItemWidth(ctx, -LABEL_W)
  local changed, v = reaper.ImGui_SliderDouble(ctx, label, tbl[key], min, max, fmt,
    reaper.ImGui_SliderFlags_AlwaysClamp())
  if changed then tbl[key] = v end
  edited(quiet)
end

-- Valor de la lane: entero en CC; en pitch bend, en cents (de menos a mas el
-- bend range).
local function slider_val(label, tbl, key, kind, amp, quiet)
  if kind ~= "pitchbend" then
    slider_int(label, tbl, key, 0, 127, "%d", quiet)
    return
  end
  local max_c = P.bend_range_st * 100
  slider_dbl(label, tbl, key, amp and 0 or -max_c, max_c, "%.0f cents", quiet)
end

local function draw_preview(kind, dur_ms)
  local w = reaper.ImGui_GetContentRegionAvail(ctx)
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
  reaper.ImGui_Dummy(ctx, w, PREVIEW_H)
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + PREVIEW_H, 0x00000066, 4)

  local lo, hi = 0, 127
  if kind == "pitchbend" then
    lo, hi = -8192, 8191
    local ymid = y + PREVIEW_H * hi / (hi - lo)
    reaper.ImGui_DrawList_AddLine(dl, x, ymid, x + w, ymid, 0xFFFFFF33, 1)
  end

  local points, perr = CcCurve.build_points(P, kind, dur_ms)
  if not points then
    reaper.ImGui_DrawList_AddText(dl, x + 8, y + 8, 0xFFFFFFFF, tostring(perr))
    return
  end
  local vals = CcCurve.sample(points, PREVIEW_STEPS)
  local function py(v)
    v = math.max(lo, math.min(hi, v))
    return y + PREVIEW_H * (1 - (v - lo) / (hi - lo))
  end
  for i = 1, PREVIEW_STEPS do
    reaper.ImGui_DrawList_AddLine(dl,
      x + w * (i - 1) / PREVIEW_STEPS, py(vals[i]),
      x + w * i / PREVIEW_STEPS, py(vals[i + 1]), 0xB8FF6DFF, 2)
  end
end

local function draw()
  need_save, need_live = false, false
  local take = target_take()

  reaper.ImGui_Text(ctx, take and ("Take: " .. reaper.GetTakeName(take)) or "Sin MIDI Editor abierto")
  reaper.ImGui_Separator(ctx)

  local tg, terr, t0, t1, source
  if take and last_editor then
    tg, terr = CcCurve.target(last_editor, P)
    t0, t1, source = CcCurve.resolve_range(take)
  end
  local dur_ms = (t0 and t1 > t0) and (t1 - t0) * 1000 or PREVIEW_MS
  local kind = tg and tg.info.kind or (P.lane == "pitchbend" and "pitchbend" or "cc")

  local is_mod = modified()
  combo("preset", "Preset", preset_opts, P.name, select_preset, is_mod and " *" or "")
  reaper.ImGui_SameLine(ctx)
  if not is_mod then reaper.ImGui_BeginDisabled(ctx) end
  if ButtonStyle.button(ctx, "Restaurar###restore", "subtle", { pad = 8 }) then
    select_preset(P.name)
  end
  if not is_mod then reaper.ImGui_EndDisabled(ctx) end

  reaper.ImGui_Text(ctx, tg and string.format("Lane: %s, canal %d", tg.info.label, tg.chan + 1)
    or ("Lane: " .. tostring(terr or "-")))
  reaper.ImGui_Text(ctx, t0 and string.format("Rango: %.3f s (%s)", t1 - t0, source)
    or "Rango: sin time selection ni notas seleccionadas")

  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx, "Lane")
  local lane_cur = (P.lane == "active" or P.lane == "pitchbend") and P.lane or "cc"
  choice_row("lane", LANE_OPTS, lane_cur, function(v)
    if v == "cc" then
      P.lane = type(P.lane) == "number" and P.lane or 1
    else
      P.lane = v
    end
  end, true)
  local cc_fixed = type(P.lane) == "number"
  local cc_tmp = { n = cc_fixed and P.lane or 1 }
  if not cc_fixed then reaper.ImGui_BeginDisabled(ctx) end
  slider_int("Numero###cc_num", cc_tmp, "n", 0, 127, "CC %d", true)
  if not cc_fixed then reaper.ImGui_EndDisabled(ctx) end
  if cc_fixed then P.lane = cc_tmp.n end

  reaper.ImGui_Text(ctx, "Canal")
  local chan_fixed = type(P.channel) == "number"
  choice_row("chan", CHAN_OPTS, chan_fixed and "fixed" or "active", function(v)
    P.channel = (v == "fixed") and (chan_fixed and P.channel or 1) or "active"
  end, true)
  local ch_tmp = { n = chan_fixed and P.channel or 1 }
  if not chan_fixed then reaper.ImGui_BeginDisabled(ctx) end
  slider_int("Numero###chan_num", ch_tmp, "n", 1, 16, "%d", true)
  if not chan_fixed then reaper.ImGui_EndDisabled(ctx) end
  if chan_fixed then P.channel = ch_tmp.n end

  reaper.ImGui_Text(ctx, "Modo")
  choice_row("mode", MODE_OPTS, P.mode, function(v) P.mode = v end)
  reaper.ImGui_Text(ctx, "Resolucion")
  choice_row("res", RES_OPTS, P.resolution, function(v) P.resolution = v end)

  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx, "Forma (" .. P.engine .. ")")
  if P.engine == "osc" then
    choice_row("wave", WAVE_OPTS, P.wave, function(v) P.wave = v end)
    choice_row("rate", RATE_OPTS, P.hz and "hz" or "cycles", function(u) set_rate_unit(u, dur_ms) end)
    if P.hz then
      slider_dbl("Frecuencia###rate_hz", P, "hz", 0.1, 30, "%.2f Hz")
    else
      P.cycles = P.cycles or 1
      slider_dbl("Ciclos###rate_cy", P, "cycles", 0.25, 60, "%.2f")
    end
    slider_dbl("Fase###phase", P, "phase", 0, 1, "%.2f")
    slider_dbl("Fade-in###fade", P, "fade_in", 0, 1, "%.2f")
  else
    combo("shape", "Forma de REAPER", SHAPE_OPTS, P.shape or 1, function(v)
      P.shape = v
      changed_live()
    end)
    if P.engine == "swell" then
      slider_dbl("Pico###peak", P, "peak", 0.01, 0.99, "%.2f")
    end
  end
  local ch, closed = reaper.ImGui_Checkbox(ctx, "Cerrar al valor base###close", P.close and true or false)
  if ch then
    P.close = closed
    changed_live()
  end

  reaper.ImGui_Separator(ctx)
  local vals = P[kind]
  if kind == "pitchbend" then
    reaper.ImGui_Text(ctx, "Valores (pitch bend, en cents)")
    slider_int("Bend range###bend", P, "bend_range_st", 1, 24, "%d st")
  else
    reaper.ImGui_Text(ctx, "Valores (CC)")
  end
  if vals then
    for _, f in ipairs(VALUE_FIELDS[P.engine] or {}) do
      slider_val(f[2] .. "###v_" .. f[1], vals, f[1], kind, f[3])
    end
    if P.engine == "ramp" and ButtonStyle.button(ctx, "Invertir###invert", "neutral", { pad = 8 }) then
      for _, k in ipairs({ "cc", "pitchbend" }) do
        local t = P[k]
        if t then t.from, t.to = t.to, t.from end
      end
      changed_live()
    end
  else
    reaper.ImGui_Text(ctx, "El preset no define valores para esta lane")
  end

  reaper.ImGui_Separator(ctx)
  draw_preview(kind, dur_ms)

  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx, "Punto en el cursor")
  choice_row("pt_mode", POINT_OPTS, point.mode, function(v) point.mode = v end, true)
  if point.mode ~= "value" then reaper.ImGui_BeginDisabled(ctx) end
  slider_val("Valor###pt_val", point, "value", kind, false, true)
  if point.mode ~= "value" then reaper.ImGui_EndDisabled(ctx) end
  if not take then reaper.ImGui_BeginDisabled(ctx) end
  if ButtonStyle.button(ctx, "Insertar punto###point", "neutral", { pad = 8 }) and last_editor then
    local v, lane_label = CcCurve.insert_point(last_editor, P, point.mode, point.value)
    if v then
      local shown = (kind == "pitchbend") and string.format("%.0f cents", v) or tostring(v)
      status = string.format("Punto en %s: %s", lane_label, shown)
    else
      status = tostring(lane_label)
    end
  end
  if not take then reaper.ImGui_EndDisabled(ctx) end

  reaper.ImGui_Separator(ctx)
  if not take then reaper.ImGui_BeginDisabled(ctx) end
  if ButtonStyle.button(ctx, "Aplicar###apply", "primary", { w = 120, h = 28 }) and last_editor then
    local n, info = CcCurve.apply(last_editor, P)
    if n and type(info) == "table" then
      status = n .. " puntos escritos"
    else
      status = tostring(info)
    end
  end
  if not take then reaper.ImGui_EndDisabled(ctx) end
  reaper.ImGui_SameLine(ctx)
  if ButtonStyle.button(ctx, "Copiar preset###copy", "neutral", { pad = 8, h = 28 }) then
    reaper.ImGui_SetClipboardText(ctx, CcCurve.preset_text(P))
    status = "Preset copiado: pegalo en MidiEdit_config.lua"
  end
  reaper.ImGui_SameLine(ctx)
  local lv_changed, lv = reaper.ImGui_Checkbox(ctx, "En vivo###live", live)
  if lv_changed then live = lv end
  reaper.ImGui_Text(ctx, status ~= "" and status or " ")

  if need_save then CcCurve.save(P) end
  if need_live and live and take then
    local n, why = CcCurve.rerun(take, P)
    if n == nil then
      status = (why == "sin sesion")
        and "En vivo: sin sesion (aplica primero, o el take cambio)"
        or ("En vivo: " .. tostring(why))
    else
      status = n .. " puntos re-aplicados"
    end
  end
end

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 430, 780, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, TITLE, true, reaper.ImGui_WindowFlags_NoNav())
  if visible then
    draw()
    if RETURN_FOCUS_TO_EDITOR then focus_tick() end
    reaper.ImGui_End(ctx)
  end
  if open then reaper.defer(loop) end
end

reaper.defer(loop)