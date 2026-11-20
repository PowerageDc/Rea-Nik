local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "MidiGen_config.lua")
local Pedal = dofile(script_dir .. "MidiGenPedal_common_logic.lua")
local ButtonStyle = dofile(script_dir .. "../_Shared/ImGuiButtonStyle_common_logic.lua")
local EditorFocus = dofile(script_dir .. "../_Shared/ImGuiEditorFocus_common_logic.lua")

local TITLE = "MidiGen Pedal"
local RETURN_FOCUS_TO_EDITOR = true
local NOTES_H, PEDAL_H, GAP = 90, 54, 6
local PREVIEW_H = NOTES_H + GAP + PEDAL_H
local cfg = Config.pedal

local P, err = Pedal.load(Config)
if not P then
  reaper.ShowConsoleMsg("[MidiGen Pedal] " .. err .. "\n")
  return
end

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local preset_names = sorted_keys(cfg.presets)

local STYLE_OPTS = { { "legato", "Legato" }, { "sustained", "Sostenido" } }
local CHANGE_OPTS = { { "chord", "Acorde" }, { "bar", "Compas" } }
local START_OPTS = { { "range", "Inicio del rango" }, { "first_attack", "Primer ataque" } }
local MODE_OPTS = { { "merge", "Mezclar" }, { "replace", "Reemplazar" } }
local CHAN_OPTS = { { "active", "Activo" }, { "fixed", "Fijo" } }
local SRC_OPTS = { { "all", "Todos" }, { "active", "Activo" }, { "fixed", "Fijo" } }
local CURSOR_OPTS = { { "inherit", "Heredar forma" }, { "square", "Cuadrada" } }

local function cursor_status(v, info)
  if not v or type(info) ~= "table" then return tostring(info) end
  return string.format("Pedal en %.3f s: %d (forma %d%s)", info.time, v, info.shape,
    info.reshaped and ", anterior cuadrado" or "")
end
local SHAPE_NAMES = { [0] = "Cuadrada", "Lineal", "Suave", "Inicio rapido", "Final rapido", "Bezier" }
local LABEL_W = 130

-- Compara contra el preset; canal, origen y modo no cuentan.
local function modified()
  local base = cfg.presets[P.name]
  if not base then return true end
  if P.style ~= base.style or P.change ~= base.change or P.start ~= base.start
     or P.close ~= (base.close == true) or P.lift_first ~= (base.lift_first == true) then
    return true
  end
  for k in pairs(Pedal.LIMITS) do
    if math.abs(P[k] - base[k]) > 1e-6 then return true end
  end
  return false
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

-- Cambia de preset conservando canal, origen y modo.
local function select_preset(name)
  local np = Pedal.resolve(Config, name)
  if not np then return end
  np.channel, np.source_channel, np.mode = P.channel, P.source_channel, P.mode
  np.cursor_shape = P.cursor_shape
  P = np
  need_save = true
  need_live = true
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

-- Slider a todo el ancho menos la etiqueta; Ctrl+clic escribe un valor exacto.
local function slider_int(label, tbl, key, min, max, fmt, quiet)
  reaper.ImGui_SetNextItemWidth(ctx, -LABEL_W)
  local changed, v = reaper.ImGui_SliderInt(ctx, label, tbl[key] or min, min, max, fmt,
    reaper.ImGui_SliderFlags_AlwaysClamp())
  if changed then tbl[key] = v end
  edited(quiet)
end

-- Slider de un numero de P con el rango de Pedal.LIMITS.
local function slider(label, key, fmt)
  local lim = Pedal.LIMITS[key]
  slider_int(label, P, key, lim[1], lim[2], fmt)
end

local function check(label, key)
  local changed, v = reaper.ImGui_Checkbox(ctx, label, P[key])
  if changed then
    P[key] = v
    need_save = true
    need_live = true
  end
end

-- Mantiene down_value mayor que up_value: el slider que se movio arrastra al
-- otro cuando lo pasa.
local value_prev = {}

local function keep_values_order()
  if P.down_value <= P.up_value then
    if P.down_value ~= value_prev.down then
      P.up_value = P.down_value - 1
    else
      P.down_value = P.up_value + 1
    end
  end
  value_prev.down = P.down_value
end

local function draw_change()
  reaper.ImGui_Text(ctx, "Estilo")
  choice_row("style", STYLE_OPTS, P.style, function(v) P.style = v end)
  local sustained = P.style == "sustained"
  if sustained then reaper.ImGui_BeginDisabled(ctx) end
  reaper.ImGui_Text(ctx, "Cambia con")
  choice_row("change", CHANGE_OPTS, P.change, function(v) P.change = v end)
  -- se evalua despues del choice_row: un clic cambia P.change ahi
  if P.change == "chord" then
    slider("Ventana de acorde###chord_win", "chord_window_ms", "%d ms")
    slider("Separacion minima###min_gap", "min_gap_ms", "%d ms")
  end
  slider("Offset###offset", "offset_ms", "%d ms")
  slider("Levantado (dip)###dip", "dip_ms", "%d ms")
  check("Levantar tambien en el primer punto###lift_first", "lift_first")
  if sustained then reaper.ImGui_EndDisabled(ctx) end
end

local function draw_values()
  slider("Presionado###down_value", "down_value", "%d")
  slider("Levantado###up_value", "up_value", "%d")
  keep_values_order()
  reaper.ImGui_SetNextItemWidth(ctx, -LABEL_W)
  if reaper.ImGui_BeginCombo(ctx, "Forma###shape", SHAPE_NAMES[P.shape] or tostring(P.shape)) then
    for i = 0, 5 do
      if reaper.ImGui_Selectable(ctx, SHAPE_NAMES[i] .. "###sh_" .. i, i == P.shape) then
        P.shape = i
        need_save = true
        need_live = true
      end
    end
    reaper.ImGui_EndCombo(ctx)
  end
  -- se evalua despues del combo: un clic cambia P.shape ahi
  if P.shape == 0 then reaper.ImGui_BeginDisabled(ctx) end
  slider("Transicion###transition", "transition_ms", "%d ms")
  if P.shape == 0 then reaper.ImGui_EndDisabled(ctx) end
end

local function draw_output()
  reaper.ImGui_Text(ctx, "Canal de salida")
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

  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx, "Canal de origen (solo afecta al cambio por acorde)")
  choice_row("src", SRC_OPTS, type(P.source_channel) == "number" and "fixed" or P.source_channel, function(v)
    if v == "fixed" then
      P.source_channel = type(P.source_channel) == "number" and P.source_channel or 1
    else
      P.source_channel = v
    end
  end)
  local sfixed = type(P.source_channel) == "number"
  local stmp = { n = sfixed and P.source_channel or 1 }
  if not sfixed then reaper.ImGui_BeginDisabled(ctx) end
  slider_int("Numero###src_num", stmp, "n", 1, 16, "%d")
  if not sfixed then reaper.ImGui_EndDisabled(ctx) end
  if sfixed then P.source_channel = stmp.n end

  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx, "Modo")
  choice_row("mode", MODE_OPTS, P.mode, function(v) P.mode = v end)
  reaper.ImGui_Text(ctx, "Arranque")
  choice_row("start", START_OPTS, P.start, function(v) P.start = v end)
  check("Soltar el pedal al final del rango###close", "close")

  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx, "Forma al presionar o soltar en el cursor")
  choice_row("cursor_shape", CURSOR_OPTS, P.cursor_shape, function(v) P.cursor_shape = v end, true)
end

-- Piano roll de las notas del rango (arriba) y linea del pedal con relleno
-- (abajo), sobre el mismo eje de tiempo. Devuelve el texto de resumen.
local function draw_preview(take, events, data, input, perr)
  local w = reaper.ImGui_GetContentRegionAvail(ctx)
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
  reaper.ImGui_Dummy(ctx, w, PREVIEW_H)
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  local py = y + NOTES_H + GAP
  reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + NOTES_H, 0x00000066, 4)
  reaper.ImGui_DrawList_AddRectFilled(dl, x, py, x + w, py + PEDAL_H, 0x00000066, 4)
  if not events then
    return take and tostring(perr) or "Sin MIDI Editor abierto"
  end

  local span = math.max(data.ppq1 - data.ppq0, 1)
  local function px(ppq)
    local c = math.max(data.ppq0, math.min(data.ppq1, ppq))
    return x + w * (c - data.ppq0) / span
  end

  local shown, lo, hi = {}, 127, 0
  for _, n in ipairs(input.notes) do
    if n.e > data.ppq0 and n.s < data.ppq1 then
      shown[#shown + 1] = n
      lo, hi = math.min(lo, n.pitch), math.max(hi, n.pitch)
    end
  end
  local rh = NOTES_H / (hi - lo + 3)
  for _, n in ipairs(shown) do
    local top = y + NOTES_H - (n.pitch - lo + 2) * rh
    local col = Pedal.from_source(P, input, n.chan)
      and (0xE0E0E000 | math.floor(90 + 165 * n.vel / 127))
      or 0x80808055
    reaper.ImGui_DrawList_AddRectFilled(dl, px(n.s), top, math.max(px(n.e), px(n.s) + 2),
      top + math.max(rh - 1, 2), col, 1)
  end

  for _, pt in ipairs(data.points) do
    local lx = px(pt)
    reaper.ImGui_DrawList_AddLine(dl, lx, y, lx, py + PEDAL_H, 0xFFFFFF26, 1)
  end

  local function vy(v) return py + PEDAL_H - 2 - (PEDAL_H - 4) * v / 127 end
  local base_y = py + PEDAL_H
  local vmin, vmax = 127, 0
  for i, ev in ipairs(events) do
    local nxt = events[i + 1]
    local xa = px(ev.ppq)
    local xb = nxt and px(nxt.ppq) or px(data.ppq1)
    local ya = vy(ev.msg3)
    vmin, vmax = math.min(vmin, ev.msg3), math.max(vmax, ev.msg3)
    if nxt and ev.shape ~= 0 then
      local yb = vy(nxt.msg3)
      reaper.ImGui_DrawList_AddQuadFilled(dl, xa, base_y, xa, ya, xb, yb, xb, base_y, 0xB8FF6D44)
      reaper.ImGui_DrawList_AddLine(dl, xa, ya, xb, yb, 0xB8FF6DFF, 1.5)
    else
      reaper.ImGui_DrawList_AddRectFilled(dl, xa, ya, xb, base_y, 0xB8FF6D44)
      reaper.ImGui_DrawList_AddLine(dl, xa, ya, xb, ya, 0xB8FF6DFF, 1.5)
      if nxt then
        reaper.ImGui_DrawList_AddLine(dl, xb, ya, xb, vy(nxt.msg3), 0xB8FF6DFF, 1.5)
      end
    end
  end

  if P.style == "sustained" then
    return string.format("sostenido, %d a %d", vmin, vmax)
  end
  return string.format("%d cambios, legato por %s, %d a %d", data.changes,
    P.change == "bar" and "compas" or "acorde", vmin, vmax)
end

local function draw()
  need_save, need_live = false, false
  local take = target_take()

  reaper.ImGui_Text(ctx, take and ("Take: " .. reaper.GetTakeName(take)) or "Sin MIDI Editor abierto")
  reaper.ImGui_Separator(ctx)

  local input, events, data, perr
  if take then
    input = Pedal.read_input(take, last_editor)
    events, data = Pedal.plan(take, P, input)
    if not events or type(data) ~= "table" then perr, events, data = tostring(data), nil, nil end
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
  reaper.ImGui_TextWrapped(ctx, draw_preview(take, events, data, input, perr))
  reaper.ImGui_Separator(ctx)

  if reaper.ImGui_BeginTabBar(ctx, "tabs") then
    if reaper.ImGui_BeginTabItem(ctx, "Cambio###tab_change") then
      draw_change()
      reaper.ImGui_EndTabItem(ctx)
    end
    if reaper.ImGui_BeginTabItem(ctx, "Valores###tab_values") then
      draw_values()
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
    local n, info = Pedal.apply(last_editor, P)
    status = (n and type(info) == "table") and (n .. " eventos escritos") or tostring(info)
  end
  if not take then reaper.ImGui_EndDisabled(ctx) end
  reaper.ImGui_SameLine(ctx)
  if ButtonStyle.button(ctx, "Copiar preset###copy", "neutral", { pad = 8, h = 28 }) then
    reaper.ImGui_SetClipboardText(ctx, Pedal.preset_text(P))
    status = "Preset copiado: pegalo en MidiGen_config.lua"
  end
  reaper.ImGui_SameLine(ctx)
  local lv_changed, lv = reaper.ImGui_Checkbox(ctx, "En vivo###live", live)
  if lv_changed then live = lv end
  if not take then reaper.ImGui_BeginDisabled(ctx) end
  if ButtonStyle.button(ctx, "Presionar en el cursor###press", "neutral", { pad = 8, h = 28 }) and last_editor then
    status = cursor_status(Pedal.cursor_point(last_editor, P, true))
  end
  reaper.ImGui_SameLine(ctx)
  if ButtonStyle.button(ctx, "Soltar en el cursor###release", "neutral", { pad = 8, h = 28 }) and last_editor then
    status = cursor_status(Pedal.cursor_point(last_editor, P, false))
  end
  if not take then reaper.ImGui_EndDisabled(ctx) end
  reaper.ImGui_Text(ctx, status ~= "" and status or " ")

  if need_save then Pedal.save(P) end
  if need_live and live and take then
    local n, why = Pedal.rerun(take, P)
    if n == nil then
      status = (why == "sin sesion")
        and "En vivo: sin sesion (aplica primero, o el take cambio)"
        or ("En vivo: " .. tostring(why))
    else
      status = n .. " eventos re-aplicados"
    end
  end
end

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 430, 640, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, TITLE, true, reaper.ImGui_WindowFlags_NoNav())
  if visible then
    draw()
    if RETURN_FOCUS_TO_EDITOR then focus_tick() end
    reaper.ImGui_End(ctx)
  end
  if open then reaper.defer(loop) end
end

reaper.defer(loop)