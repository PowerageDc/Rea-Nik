local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "MidiEdit_config.lua")
local Strum = dofile(script_dir .. "MidiEditStrum_common_logic.lua")
local ButtonStyle = dofile(script_dir .. "../_Shared/ImGuiButtonStyle_common_logic.lua")
local EditorFocus = dofile(script_dir .. "../_Shared/ImGuiEditorFocus_common_logic.lua")

local TITLE = "MidiEdit Strum"
local RETURN_FOCUS_TO_EDITOR = true
local cfg = Config.strum

local P, err = Strum.load(Config)
if not P then
  reaper.ShowConsoleMsg("[MidiEdit Strum] " .. err .. "\n")
  return
end

local function sorted_names(t, by)
  local names = {}
  for k in pairs(t) do names[#names + 1] = k end
  table.sort(names, by)
  return names
end

local style_names = sorted_names(cfg.styles)
local timing_names = sorted_names(cfg.timings, function(a, b)
  return cfg.timings[a].total_ms < cfg.timings[b].total_ms
end)
local dynamics_names = sorted_names(cfg.dynamics)

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

local TIMING_KEYS = { "total_ms", "curve", "jitter_ms" }
local DYNAMICS_KEYS = { "from", "to", "curve", "jitter", "up_scale" }

local function values_differ(cur, base, keys)
  if not base then return true end
  for _, k in ipairs(keys) do
    local a, b = cur[k], base[k]
    if (a == nil) ~= (b == nil) then return true end
    if a and math.abs(a - b) > 1e-6 then return true end
  end
  return false
end

local function timing_modified()
  return values_differ(P.timing, cfg.timings[P.timing_name], TIMING_KEYS)
end

local function dynamics_modified()
  return values_differ(P.dynamics, cfg.dynamics[P.dynamics_name], DYNAMICS_KEYS)
end

local function style_modified(t_mod, d_mod)
  local base = cfg.styles[P.name]
  if not base then return true end
  return t_mod or d_mod
    or P.timing_name ~= base.timing
    or P.dynamics_name ~= base.dynamics
    or P.direction ~= base.direction
end

local ctx = reaper.ImGui_CreateContext(TITLE)
local last_editor
local status = ""
local dirty = false
local retrigger = false
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

local function select_style(name)
  local np = Strum.resolve(Config, name)
  if not np then return end
  P.name, P.timing_name, P.dynamics_name = np.name, np.timing_name, np.dynamics_name
  P.timing, P.dynamics, P.direction = np.timing, np.dynamics, np.direction
  Strum.save(P)
  retrigger = true
end

local function choice_row(id, options, current, on_pick)
  reaper.ImGui_PushID(ctx, id)
  for i, name in ipairs(options) do
    if i > 1 then reaper.ImGui_SameLine(ctx) end
    local kind = (name == current) and "primary" or "neutral"
    if ButtonStyle.button(ctx, name, kind, { pad = 8 }) then
      on_pick(name)
      Strum.save(P)
      retrigger = true
    end
  end
  reaper.ImGui_PopID(ctx)
end

local function drag_int(label, tbl, key, min, max, fmt)
  reaper.ImGui_SetNextItemWidth(ctx, 160)
  local changed, v = reaper.ImGui_DragInt(ctx, label, tbl[key], 1, min, max, fmt)
  if changed then tbl[key] = v end
  if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then dirty = true end
end

local function drag_dbl(label, tbl, key, speed, min, max, fmt)
  reaper.ImGui_SetNextItemWidth(ctx, 160)
  local changed, v = reaper.ImGui_DragDouble(ctx, label, tbl[key], speed, min, max, fmt)
  if changed then tbl[key] = v end
  if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then dirty = true end
end

local function draw()
  dirty = false
  retrigger = false
  local take = target_take()
  local T, D = P.timing, P.dynamics

  reaper.ImGui_Text(ctx, take and ("Take: " .. reaper.GetTakeName(take)) or "Sin MIDI Editor abierto")
  reaper.ImGui_Separator(ctx)

  local t_mod, d_mod = timing_modified(), dynamics_modified()
  local s_mod = style_modified(t_mod, d_mod)

  reaper.ImGui_SetNextItemWidth(ctx, 200)
  if reaper.ImGui_BeginCombo(ctx, "Estilo###style", P.name .. (s_mod and " *" or "")) then
    for _, name in ipairs(style_names) do
      if reaper.ImGui_Selectable(ctx, name .. "###s_" .. name, name == P.name) then
        select_style(name)
      end
    end
    reaper.ImGui_EndCombo(ctx)
  end
  reaper.ImGui_SameLine(ctx)
  if not s_mod then reaper.ImGui_BeginDisabled(ctx) end
  if ButtonStyle.button(ctx, "Restaurar###restore", "subtle", { pad = 8 }) then
    select_style(P.name)
  end
  if not s_mod then reaper.ImGui_EndDisabled(ctx) end

  reaper.ImGui_Text(ctx, t_mod and "Tiempo *" or "Tiempo")
  choice_row("timing", timing_names, P.timing_name, function(name)
    P.timing, P.timing_name = copy(cfg.timings[name]), name
  end)
  drag_int("Total###t_total", T, "total_ms", 1, 600, "%d ms")
  drag_dbl("Curva###t_curve", T, "curve", 0.01, 0.2, 3.0, "%.2f")
  drag_dbl("Jitter###t_jitter", T, "jitter_ms", 0.1, 0, 20, "%.1f ms")

  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx, "Direccion")
  choice_row("direction", { "down", "up", "alternate" }, P.direction, function(name)
    P.direction = name
  end)
  reaper.ImGui_Text(ctx, "Ancla")
  choice_row("anchor", { "first", "last", "center" }, P.anchor, function(name)
    P.anchor = name
  end)
  reaper.ImGui_Text(ctx, "Finales")
  choice_row("ends", { "keep", "duration" }, P.ends, function(name)
    P.ends = name
  end)

  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx, d_mod and "Dinamica *" or "Dinamica")
  choice_row("dynamics", dynamics_names, P.dynamics_name, function(name)
    P.dynamics, P.dynamics_name = copy(cfg.dynamics[name]), name
  end)
  drag_dbl("Desde###d_from", D, "from", 0.005, 0.2, 2.0, "x%.2f")
  drag_dbl("Hasta###d_to", D, "to", 0.005, 0.2, 2.0, "x%.2f")
  drag_dbl("Curva###d_curve", D, "curve", 0.01, 0.2, 3.0, "%.2f")
  drag_dbl("Jitter###d_jitter", D, "jitter", 0.1, 0, 20, "%.1f")
  drag_dbl("Upstroke###d_up", D, "up_scale", 0.005, 0.2, 1.5, "x%.2f")

  reaper.ImGui_Separator(ctx)
  if not take then reaper.ImGui_BeginDisabled(ctx) end
  if ButtonStyle.button(ctx, "Aplicar###apply", "primary", { w = 120, h = 28 }) then
    local n = Strum.run(take, P)
    status = (n > 0) and (n .. " notas modificadas")
      or "Nada para cambiar: sin acorde seleccionado ni bajo el cursor"
  end
  if not take then reaper.ImGui_EndDisabled(ctx) end
  reaper.ImGui_SameLine(ctx)
  if ButtonStyle.button(ctx, "Copiar preset###copy", "neutral", { pad = 8, h = 28 }) then
    reaper.ImGui_SetClipboardText(ctx, Strum.preset_text(P))
    status = "Preset copiado: pegalo en MidiEdit_config.lua"
  end
  reaper.ImGui_SameLine(ctx)
  local ch, v = reaper.ImGui_Checkbox(ctx, "En vivo###live", live)
  if ch then live = v end
  reaper.ImGui_Text(ctx, status ~= "" and status or " ")

  if dirty then
    Strum.save(P)
    retrigger = true
  end
  if retrigger and live and take then
    local n = Strum.rerun(take, P)
    if n == nil then
      status = "En vivo: sin sesion (aplica primero, o el take cambio)"
    else
      status = (n > 0) and (n .. " notas re-aplicadas") or "Sin cambios"
    end
  end
end

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 400, 560, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, TITLE, true, reaper.ImGui_WindowFlags_NoNav())
  if visible then
    draw()
    if RETURN_FOCUS_TO_EDITOR then focus_tick() end
    reaper.ImGui_End(ctx)
  end
  if open then reaper.defer(loop) end
end

reaper.defer(loop)