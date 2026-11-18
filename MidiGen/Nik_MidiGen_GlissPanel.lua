local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "MidiGen_config.lua")
local Gliss = dofile(script_dir .. "MidiGenGliss_common_logic.lua")
local ButtonStyle = dofile(script_dir .. "../_Shared/ImGuiButtonStyle_common_logic.lua")
local EditorFocus = dofile(script_dir .. "../_Shared/ImGuiEditorFocus_common_logic.lua")

local TITLE = "MidiGen Glissando"
local RETURN_FOCUS_TO_EDITOR = true
local PREVIEW_H = 130
local LABEL_W = 130
local cfg = Config.gliss

local P, err = Gliss.load(Config)
if not P then
  reaper.ShowConsoleMsg("[MidiGen Gliss] " .. err .. "\n")
  return
end

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local SET_LABELS = { white = "Blancas", black = "Negras" }
local preset_names, set_opts = sorted_keys(cfg.presets), {}
for _, key in ipairs(sorted_keys(cfg.sets)) do
  set_opts[#set_opts + 1] = { key, SET_LABELS[key] or key }
end
local TMODE_OPTS = { { "total", "Total" }, { "per_note", "Por nota" } }
local KIND_OPTS = { { "count", "Por cantidad" }, { "pitch", "Por pitch" } }
local DIR_OPTS = { { "up", "Subiendo" }, { "down", "Bajando" } }
local MODE_OPTS = { { "merge", "Mezclar" }, { "replace", "Reemplazar" } }
local CHAN_OPTS = { { "active", "Activo" }, { "fixed", "Fijo" } }
local NOTE_NAMES = { "Do", "Do#", "Re", "Re#", "Mi", "Fa", "Fa#", "Sol", "Sol#", "La", "La#", "Si" }
local TIMING_KEYS = { "total_ms", "note_ms", "curve", "jitter_ms" }
local VEL_KEYS = { "from", "to", "curve", "jitter" }

local function pitch_name(p)
  return string.format("%s%d", NOTE_NAMES[p % 12 + 1], p // 12 - 1)
end

local function differs(cur, base, keys)
  for _, k in ipairs(keys) do
    local a, b = cur[k], base[k]
    if (a == nil) ~= (b == nil) then return true end
    if a and math.abs(a - b) > 1e-6 then return true end
  end
  return false
end

-- Compara contra el preset; canal, modo, origen y rango no cuentan.
local function modified()
  local base = cfg.presets[P.name]
  if not base then return true end
  return P.set_name ~= base.set
    or P.contact ~= math.max(1, math.floor(base.contact or 1))
    or P.timing.mode ~= base.timing.mode
    or differs(P.timing, base.timing, TIMING_KEYS)
    or differs(P.velocity, base.velocity, VEL_KEYS)
end

local ctx = reaper.ImGui_CreateContext(TITLE)
local last_editor
local status = ""
local need_save, need_live = false, false
local live = false
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

-- Cambia de preset conservando canal, modo, origen y rango.
local function select_preset(name)
  local np = Gliss.resolve(Config, name)
  if not np then return end
  np.channel, np.mode, np.single, np.range = P.channel, P.mode, P.single, P.range
  P = np
  changed_live()
end

-- quiet: el cambio se guarda pero no re-aplica en vivo.
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

local function edited(quiet)
  if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
    need_save = true
    if not quiet then need_live = true end
  end
end

-- Sliders a todo el ancho menos la etiqueta; Ctrl+clic escribe un valor exacto.
local function slider_int(label, tbl, key, min, max, fmt, quiet)
  reaper.ImGui_SetNextItemWidth(ctx, -LABEL_W)
  local changed, v = reaper.ImGui_SliderInt(ctx, label, tbl[key] or min, min, max, fmt,
    reaper.ImGui_SliderFlags_AlwaysClamp())
  if changed then tbl[key] = v end
  edited(quiet)
end

local function slider_dbl(label, tbl, key, min, max, fmt, quiet)
  reaper.ImGui_SetNextItemWidth(ctx, -LABEL_W)
  local changed, v = reaper.ImGui_SliderDouble(ctx, label, tbl[key] or min, min, max, fmt,
    reaper.ImGui_SliderFlags_AlwaysClamp())
  if changed then tbl[key] = v end
  edited(quiet)
end

-- Piano roll de lo que escribiria el glissando (barras claras, con opacidad
-- segun la velocity) y de las notas existentes que lo rodean (azul). Devuelve
-- el texto de resumen.
local function draw_preview(take, events, src, input, perr)
  local w = reaper.ImGui_GetContentRegionAvail(ctx)
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
  reaper.ImGui_Dummy(ctx, w, PREVIEW_H)
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + PREVIEW_H, 0x00000066, 4)
  if not events then
    return take and tostring(perr) or "Sin MIDI Editor abierto"
  end

  local existing = {}
  if src.gap then existing[#existing + 1] = input.notes[1] end
  if src.dest.e then existing[#existing + 1] = src.dest end

  local x0, x1, lo, hi = events[1].s, src.ppq_end, 127, 0
  for _, ev in ipairs(events) do
    x1 = math.max(x1, ev.e)
    lo, hi = math.min(lo, ev.pitch), math.max(hi, ev.pitch)
  end
  local cap = src.ppq_end + (src.ppq_end - x0) * 0.25
  for _, n in ipairs(existing) do
    x0, x1 = math.min(x0, n.s), math.max(x1, math.min(n.e, cap))
    lo, hi = math.min(lo, n.pitch), math.max(hi, n.pitch)
  end

  local span = math.max(x1 - x0, 1)
  local rh = PREVIEW_H / (hi - lo + 3)
  local function bar(n, col)
    local top = y + PREVIEW_H - (n.pitch - lo + 2) * rh
    local xa = x + w * (n.s - x0) / span
    local xb = x + w * (math.min(n.e, cap) - x0) / span
    reaper.ImGui_DrawList_AddRectFilled(dl, xa, top, math.max(xb, xa + 2), top + math.max(rh - 1, 2), col, 1)
  end
  for _, n in ipairs(existing) do bar(n, 0x6DB8FFFF) end
  for _, ev in ipairs(events) do
    bar(ev, 0xB8FF6D00 | math.floor(90 + 165 * ev.vel / 127))
  end

  local ms = (reaper.MIDI_GetProjTimeFromPPQPos(take, src.ppq_end)
    - reaper.MIDI_GetProjTimeFromPPQPos(take, events[1].s)) * 1000
  local first, last = events[1].pitch, events[#events].pitch
  return string.format("%d notas, %s a %s, %.0f ms (%s)",
    #events, pitch_name(first), pitch_name(last), ms, src.label)
end

local function draw_time(time_fixed)
  choice_row("tmode", TMODE_OPTS, P.timing.mode, function(v) P.timing.mode = v end)
  if P.timing.mode == "per_note" then
    slider_int("Por nota###t_note", P.timing, "note_ms", 5, 300, "%d ms")
  else
    slider_int("Total###t_total", P.timing, "total_ms", 20, 2000, "%d ms")
  end
  slider_dbl("Curva###t_curve", P.timing, "curve", 0.2, 3.0, "%.2f")
  slider_dbl("Jitter###t_jitter", P.timing, "jitter_ms", 0, 20, "%.1f ms")
  if time_fixed then
    reaper.ImGui_TextWrapped(ctx,
      "El tiempo lo fijan el origen y el destino o la time selection: Total y Por nota no se usan.")
  end
end

local function draw_keys()
  reaper.ImGui_Text(ctx, "Conjunto")
  choice_row("set", set_opts, P.set_name, function(v) P.set_name = v end)
  slider_int("Contacto###contact", P, "contact", 1, 8, "%d")
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx, "Velocity (factor sobre la del destino)")
  slider_dbl("Desde###v_from", P.velocity, "from", 0.2, 1.5, "x%.2f")
  slider_dbl("Hasta###v_to", P.velocity, "to", 0.2, 1.5, "x%.2f")
  slider_dbl("Curva###v_curve", P.velocity, "curve", 0.2, 3.0, "%.2f")
  slider_dbl("Jitter###v_jitter", P.velocity, "jitter", 0, 20, "%.1f")
end

local function draw_origin()
  reaper.ImGui_Text(ctx, "Una nota seleccionada (el destino)")
  choice_row("o_kind", KIND_OPTS, P.single.from_pitch ~= nil and "pitch" or "count", function(v)
    P.single.from_pitch = (v == "pitch") and (P.single.from_pitch or 48) or nil
  end)
  -- se evalua despues del choice_row: un clic cambia from_pitch ahi
  if P.single.from_pitch ~= nil then
    slider_int("Pitch de origen###o_from", P.single, "from_pitch", 0, 127, "%d")
  else
    slider_int("Cantidad###o_count", P.single, "count", 1, 48, "%d notas")
    choice_row("o_dir", DIR_OPTS, P.single.direction, function(v) P.single.direction = v end)
  end
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx, "Time selection sin notas seleccionadas")
  slider_int("Desde pitch###r_from", P.range, "from_pitch", 0, 127, "%d")
  slider_int("Hasta pitch###r_to", P.range, "to_pitch", 0, 127, "%d")
  slider_int("Velocity###r_vel", P.range, "velocity", 1, 127, "%d")
end

local function draw_output()
  reaper.ImGui_Text(ctx, "Canal")
  choice_row("chan", CHAN_OPTS, type(P.channel) == "number" and "fixed" or "active", function(v)
    P.channel = (v == "fixed") and (type(P.channel) == "number" and P.channel or 1) or "active"
  end, true)
  -- se evalua despues del choice_row: un clic cambia P.channel ahi
  local fixed = type(P.channel) == "number"
  local tmp = { n = fixed and P.channel or 1 }
  if not fixed then reaper.ImGui_BeginDisabled(ctx) end
  slider_int("Numero###chan_num", tmp, "n", 1, 16, "%d", true)
  if not fixed then reaper.ImGui_EndDisabled(ctx) end
  if fixed then P.channel = tmp.n end

  reaper.ImGui_Text(ctx, "Modo")
  choice_row("mode", MODE_OPTS, P.mode, function(v) P.mode = v end)
end

local function draw()
  need_save, need_live = false, false
  local take = target_take()

  reaper.ImGui_Text(ctx, take and ("Take: " .. reaper.GetTakeName(take)) or "Sin MIDI Editor abierto")
  reaper.ImGui_Separator(ctx)

  local input, events, src, perr
  if take then
    input = Gliss.read_input(take)
    events, src = Gliss.plan(take, P, input)
    if not events or type(src) ~= "table" then perr, events, src = tostring(src), nil, nil end
  end

  local is_mod = modified()
  reaper.ImGui_SetNextItemWidth(ctx, 200)
  if reaper.ImGui_BeginCombo(ctx, "Preset###preset", P.name .. (is_mod and " *" or "")) then
    for _, name in ipairs(preset_names) do
      if reaper.ImGui_Selectable(ctx, name .. "###p_" .. name, name == P.name) then
        select_preset(name)
      end
    end
    reaper.ImGui_EndCombo(ctx)
  end
  reaper.ImGui_SameLine(ctx)
  if not is_mod then reaper.ImGui_BeginDisabled(ctx) end
  if ButtonStyle.button(ctx, "Restaurar###restore", "subtle", { pad = 8 }) then
    select_preset(P.name)
  end
  if not is_mod then reaper.ImGui_EndDisabled(ctx) end

  reaper.ImGui_Separator(ctx)
  reaper.ImGui_TextWrapped(ctx, draw_preview(take, events, src, input, perr))
  reaper.ImGui_Separator(ctx)

  local time_fixed = input ~= nil and (input.te > input.ts or #input.notes >= 2)
  if reaper.ImGui_BeginTabBar(ctx, "tabs") then
    if reaper.ImGui_BeginTabItem(ctx, "Tiempo###tab_time") then
      draw_time(time_fixed)
      reaper.ImGui_EndTabItem(ctx)
    end
    if reaper.ImGui_BeginTabItem(ctx, "Teclas###tab_keys") then
      draw_keys()
      reaper.ImGui_EndTabItem(ctx)
    end
    if reaper.ImGui_BeginTabItem(ctx, "Origen###tab_origin") then
      draw_origin()
      reaper.ImGui_EndTabItem(ctx)
    end
    if reaper.ImGui_BeginTabItem(ctx, "Salida###tab_output") then
      draw_output()
      reaper.ImGui_EndTabItem(ctx)
    end
    reaper.ImGui_EndTabBar(ctx)
  end

  reaper.ImGui_Separator(ctx)
  if not take then reaper.ImGui_BeginDisabled(ctx) end
  if ButtonStyle.button(ctx, "Aplicar###apply", "primary", { w = 120, h = 28 }) and last_editor then
    local n, info = Gliss.apply(last_editor, P)
    status = (n and type(info) == "table") and (n .. " notas escritas") or tostring(info)
  end
  if not take then reaper.ImGui_EndDisabled(ctx) end
  reaper.ImGui_SameLine(ctx)
  if ButtonStyle.button(ctx, "Copiar preset###copy", "neutral", { pad = 8, h = 28 }) then
    reaper.ImGui_SetClipboardText(ctx, Gliss.preset_text(P))
    status = "Preset copiado: pegalo en MidiGen_config.lua"
  end
  reaper.ImGui_SameLine(ctx)
  local lv_changed, lv = reaper.ImGui_Checkbox(ctx, "En vivo###live", live)
  if lv_changed then live = lv end
  reaper.ImGui_Text(ctx, status ~= "" and status or " ")

  if need_save then Gliss.save(P) end
  if need_live and live and take then
    local n, why = Gliss.rerun(take, P)
    if n == nil then
      status = (why == "sin sesion")
        and "En vivo: sin sesion (aplica primero, o el take cambio)"
        or ("En vivo: " .. tostring(why))
    else
      status = n .. " notas re-aplicadas"
    end
  end
end

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 430, 760, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, TITLE, true, reaper.ImGui_WindowFlags_NoNav())
  if visible then
    draw()
    if RETURN_FOCUS_TO_EDITOR then focus_tick() end
    reaper.ImGui_End(ctx)
  end
  if open then reaper.defer(loop) end
end

reaper.defer(loop)